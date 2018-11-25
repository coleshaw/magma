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

    it 'fails for non-editors' do
      load({ }, :viewer)
      expect(last_response.status).to eq(403)
    end

    it 'fails for invalid loaders' do
      expect(last_response.status).to eq(200)
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
