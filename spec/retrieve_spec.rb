describe Magma::Server::Retrieve do
  include Rack::Test::Methods

  def app
    OUTER_APP
  end

  def retrieve(post)
    json_post(:retrieve, post)
  end

  it 'calls the retrieve endpoint and returns a template.' do
    retrieve(
      model_name: 'labor',
      record_names: [],
      attribute_names: [],
      project_name: 'labors'
    )
    expect(last_response).to(be_ok)
  end

  it 'complains with missing params.' do
    retrieve({})
    expect(last_response.status).to eq(422)
  end

  it 'can get all models from the retrieve endpoint.' do
    retrieve(
      model_name: 'all',
      record_names: [],
      attribute_names: [],
      project_name: 'labors'
    )
    expect(last_response).to(be_ok)
  end

  it 'retrieves records by name' do
    labors = create_list(:labor,3)

    names = labors.map(&:name).map(&:to_sym)

    retrieve(
      model_name: 'labor',
      record_names: names[0..1],
      attribute_names: 'all',
      project_name: 'labors'
    )

    json = json_body(last_response.body)

    expect(json[:models][:labor][:documents]).to have_key(names.first)
    expect(json[:models][:labor][:documents]).not_to have_key(names.last)
  end

  it 'can retrieve a TSV of data from the endpoint' do
    labor_list = create_list(:labor, 3)
    retrieve(
      model_name: 'labor',
      record_names: 'all',
      attribute_names: 'all',
      format: 'tsv',
      project_name: 'labors'
    )
    # strong assumption about how columns should be ordered, may
    # be inappropriate for this test - unavoidable?
    expect(last_response.body.split(/\n/).length).to eq(4)
  end
end
