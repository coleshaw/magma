describe LoadController do
  include Rack::Test::Methods

  def app
    OUTER_APP
  end

  after(:each) do
    stubs.clear
  end

  context '#schedule' do
    def load(post, user_type=:editor)
      auth_header(user_type)
      json_post(:load, post)
    end

    context 'basic scheduling' do
      before(:each) do
        module Labors
          class MonsterLoader < Magma::Loader
            arguments monster_name: String, species: String
          end
        end

        Timecop.freeze
        @now = DateTime.now.iso8601
      end

      after(:each) do
        Labors.send :remove_const, :MonsterLoader
        Timecop.return
      end

      it 'creates a load request' do
        # we try to load test
        load({
          project_name: 'labors',
          loader_name: 'monster',
          monster_name: 'Nemean Lion',
          species: 'lion'
        })

        # we get the load_request as response
        expect(last_response.status).to eq(200)
        expect(json_body).to eq(
          arguments: {
            monster_name: 'Nemean Lion',
            species: 'lion'
          },
          project_name: 'labors',
          loader_name: 'monster',
          message: 'Request is queued.',
          status: 'open',
          user: AUTH_USERS[:editor][:email],
          created_at: @now,
          updated_at: @now
        )

        # we have created a record
        expect(LoadRequest.first).not_to be_nil
      end

      it 'complains if the loader does not exist for the project' do
        # we try to run a non-existent loader
        load({ project_name: 'labors', loader_name: 'sisyphus'})

        # no record is created
        expect(LoadRequest.first).to be_nil

        # we get a client error in response
        expect(last_response.status).to eq(422)
        expect(json_body).to eq(error: 'No such loader sisyphus.' )
      end

      it 'fails for non-editors' do
        load({ }, :viewer)
        expect(last_response.status).to eq(403)
      end

      it 'complains with missing params.' do
        load(project_name: 'labors', loader_name: 'monster',
             monster_name: 'Nemean Lion')
        expect(last_response.status).to eq(422)
        expect(json_body[:error]).to eq(
          'Missing params species for loader monster.'
        )
      end

      it 'complains with invalid params.' do
        load(
          project_name: 'labors', loader_name: 'monster',
          monster_name: [ 'Nemean Lion', 'Lernean Hydra' ],
          species: [ 'lion', 'hydra' ]
        )
        expect(last_response.status).to eq(422)
        expect(json_body[:error]).to eq(
          'Invalid params monster_name, species for loader monster.'
        )
      end
    end

    context '#scheduling with files' do
      before(:each) do
        module Labors
          class FileLoader < Magma::Loader
            arguments file: ::File
          end
        end

        Timecop.freeze
        @now = DateTime.now.iso8601
        @labors_file = stubs.create_file('tmp', 'labors.txt', 'The Twelve Labors of Hercules')
      end

      after(:each) do
        Labors.send :remove_const, :FileLoader
        Timecop.return
        ::File.unlink(@labors_file) if ::File.exists?(@labors_file)

        LoadRequest.each do |req|
          unless req.files.empty?
            req.files.each do |file|
              File.unlink(file)
            end
          end
        end
      end

      it 'creates a load request' do
        # we try to load a file
        auth_header(:editor)
        post(
          '/load',
          project_name: 'labors',
          loader_name: 'file',
          file: Rack::Test::UploadedFile.new(
            @labors_file, 'application/octet-stream'
          )
        )

        # we get the load_request as response
        expect(last_response.status).to eq(200)
        expect(json_body).to eq(
          arguments: { file: 'file'},
          project_name: 'labors',
          loader_name: 'file',
          message: 'Request is queued.',
          status: 'open',
          user: AUTH_USERS[:editor][:email],
          created_at: @now,
          updated_at: @now
        )

        # we have created a record
        task = LoadRequest.first
        expect(task).to be

        # there is a file on disk
        expect(task.files).to eq(["#{Magma.instance.config(:load_requests_path)}load-request-#{task.id}-file-file"])
        expect(File.exists?(task.files.first)).to be_truthy
      end
    end
  end

  context 'execution' do
    before(:each) do
      module Labors
        class MonsterTSVLoader < Magma::Loader
          arguments monster_list: File

          def load
            csv = CSV.read(
              @arguments[:monster_list],
              col_sep: "\t"
            )
            header = [ :name, :species ]
            csv.each do |record|
              push_record(Labors::Monster, header.zip( record ).to_h)
            end

            dispatch_record_set
          end
        end
      end
    end
    after(:each) do
      Labors.send :remove_const, :MonsterTSVLoader
    end

    it 'runs the load request and updates status' do
      @monster_tsv = stubs.create_file(
        'tmp', 'monster.tsv',
        [ "Nemean Lion\tlion", "Stymphalian Birds\tmarsh bird" ].join("\n")
      )
      # we try to load a monster table
      auth_header(:editor)
      post(
        '/load',
        project_name: 'labors',
        loader_name: 'monster_tsv',
        monster_list: Rack::Test::UploadedFile.new(
          @monster_tsv, 'application/octet-stream'
        )
      )

      # First, the load request is created
      expect(last_response.status).to eq(200)
      monster_load_request = LoadRequest.first
      expect(monster_load_request).to be

      # Next, somewhere the load_request is executed
      monster_load_request.execute!

      # The actual data is created
      expect(Labors::Monster.count).to eq(2)
      expect(Labors::Monster.select_map(:species)).to eq(['lion', 'marsh bird'])

      # The load_request is updated to note the new status
      monster_load_request.refresh
      expect(monster_load_request.status).to eq(LoadRequest::STATUS_COMPLETE)

      # The message returns the number of records inserted into the database
      expect(monster_load_request.message).to eq('Loading complete, 2 records inserted and 0 updated.')

      # The inputs are no longer needed and thus discarded
      expect(monster_load_request.files).to all( satisfy {|f| !::File.exists?(f) } )
    end

    it 'runs the load request and reports validation errors' do
      @monster_tsv = stubs.create_file(
        'tmp', 'monster.tsv',
        [ "Nemean Lion\tLion", "Stymphalian Birds\tmarsh bird" ].join("\n")
      )
      # we try to load a monster table
      auth_header(:editor)
      post(
        '/load',
        project_name: 'labors',
        loader_name: 'monster_tsv',
        monster_list: Rack::Test::UploadedFile.new(
          @monster_tsv, 'application/octet-stream'
        )
      )

      # First, the load request is created
      expect(last_response.status).to eq(200)
      monster_load_request = LoadRequest.first
      expect(monster_load_request).to be

      # Next, somewhere the load_request is executed
      monster_load_request.execute!

      # The records are not created due to a validation error
      expect(Labors::Monster.count).to eq(0)
      expect(Labors::Monster.select_map(:species)).to eq([])

      # The load_request is updated to note the new status
      monster_load_request.refresh
      expect(monster_load_request.status).to eq(LoadRequest::STATUS_FAILED)

      # The message returns the problem
      expect(monster_load_request.message).to eq("Loading failed with these complaints:\n - On species, 'Lion' is improperly formatted.")

      # The inputs, being suspicious, are discarded
      expect(monster_load_request.files).to all( satisfy {|f| !::File.exists?(f) } )
    end
  end

  context '#status' do
    def create_load_request(type, status, user_type=:editor)
      create(
        :load_request,
        type,
        project_name: 'labors',
        loader_name: 'test',
        message: "Request is #{status}.",
        status: status,
        user: AUTH_USERS[user_type][:email]
      )
    end

    def load_requests(key=nil)
      key ?
        json_body[:load_requests].map{|a|a[key]}
      :
        json_body[:load_requests]
    end

    it 'shows open jobs' do
      lion = create_load_request(:lion, LoadRequest::STATUS_OPEN)
      hydra = create_load_request(:hydra, LoadRequest::STATUS_OPEN)

      auth_header(:editor)
      get('/load/labors')
      expect(last_response.status).to eq(200)
      expect(load_requests.map(&:keys)).to all(eq(LoadRequest.visible_attributes))
      expect(load_requests(:status)).to all(eq(LoadRequest::STATUS_OPEN))
    end

    it 'shows running jobs' do
      lion = create_load_request(:lion, LoadRequest::STATUS_RUNNING)
      hydra = create_load_request(:hydra, LoadRequest::STATUS_RUNNING)

      auth_header(:editor)
      get('/load/labors')
      expect(last_response.status).to eq(200)
      expect(load_requests.length).to eq(2)
      expect(load_requests.map(&:keys)).to all(eq(LoadRequest.columns - [:id]))
      expect(load_requests(:status)).to all(eq(LoadRequest::STATUS_RUNNING))
    end

    it 'does not show canceled jobs' do
      lion = create_load_request(:lion, LoadRequest::STATUS_CANCELED)
      hydra = create_load_request(:hydra, LoadRequest::STATUS_CANCELED)

      auth_header(:editor)
      get('/load/labors')
      expect(last_response.status).to eq(200)
      expect(load_requests).to eq([])
    end

    it 'only shows recently completed jobs' do
      # The lion request was completed more than a week ago
      Timecop.freeze(Date.today - 30) do
        lion = create_load_request(:lion, LoadRequest::STATUS_COMPLETE)
      end
      # The hydra request was completed today
      Timecop.freeze(Date.today) do
        hydra = create_load_request(:hydra, LoadRequest::STATUS_COMPLETE)
      end

      auth_header(:editor)
      get('/load/labors')

      # only the hydra is returned
      expect(last_response.status).to eq(200)
      expect(load_requests.length).to eq(1)
      expect(load_requests.first[:arguments][:species_name]).to eq('hydra')
    end

    it 'only shows recently failed jobs' do
      # The lion request failed more than a week ago
      Timecop.freeze(Date.today - 30) do
        lion = create_load_request(:lion, LoadRequest::STATUS_FAILED)
      end
      # The hydra request failed today
      Timecop.freeze(Date.today) do
        hydra = create_load_request(:hydra, LoadRequest::STATUS_FAILED)
      end

      auth_header(:editor)
      get('/load/labors')

      # only the hydra is returned
      expect(last_response.status).to eq(200)
      expect(load_requests.length).to eq(1)
      expect(load_requests.first[:arguments][:species_name]).to eq('hydra')
    end

    it 'only returns jobs for the requesting user' do
      # The lion and bird requests were made by someone else
      lion = create_load_request(:lion, LoadRequest::STATUS_OPEN,:restricted_editor)
      birds = create_load_request(:lion, LoadRequest::STATUS_FAILED,:restricted_editor)

      # The hydra and hind requests were made by us
      hydra = create_load_request(:hydra, LoadRequest::STATUS_OPEN)
      hind = create_load_request(:hind, LoadRequest::STATUS_FAILED)

      auth_header(:editor)
      get('/load/labors')

      # only the hydra and hind are returned
      expect(last_response.status).to eq(200)
      expect(load_requests.length).to eq(2)
      expect(load_requests(:arguments).map{|a| a[:species_name]}).to eq(
        ['hydra', 'red deer']
      )
    end
  end
end
