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

    it 'complains with missing params.' do
      load(project_name: 'labors')
      expect(last_response.status).to eq(422)
    end
  end

  context '#status' do
    it 'gets a list of current running jobs' do
    end
  end
end
