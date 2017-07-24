require 'pry'
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
      project_name: 'labors'
      model_name: 'all',
      record_names: [],
      attribute_names: "all"
    )
    expect(last_response).to(be_ok)
  end

  it "complains if there are record names for all models" do
    retrieve(
      model_name: "all",
      record_names: [ "record1", "record2" ],
      attribute_names: []
    )

    expect(last_response.status).to eq(422)
  end

  it "retrieves records by identifier" do
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

  it "can retrieve records by id if there is no identifier" do
    prizes = create_list(:prize,3)
    retrieve(
      model_name: "prize",
      record_names: prizes[0..1].map(&:id),
      attribute_names: "all" 
    )

    json = JSON.parse(last_response.body)

    expect(json["models"]["prize"]["documents"]).to have_key(prizes[0].id.to_s)
    expect(json["models"]["prize"]["documents"]).not_to have_key(prizes[2].id.to_s)
  end

  it "can retrieve a TSV of data from the endpoint" do
    labor_list = create_list(:labor, 12)
    required_atts = ["name", "number", "completed"]
    retrieve(
      model_name: 'labor',
      record_names: 'all',
      attribute_names: required_atts,
      format: 'tsv',
      project_name: 'labors'
    )
    header, *table = CSV.parse(last_response.body, col_sep: "\t")

    expect(header).to eq(required_atts)
    expect(table.length).to eq(12)
  end

  it "can retrieve a TSV of data without an identifier" do
    prize_list = create_list(:prize, 12)
    retrieve(
      model_name: "prize",
      record_names: "all",
      attribute_names: "all",
      format: "tsv"
    )
    header, *table = CSV.parse(last_response.body, col_sep: "\t")

    expect(table.length).to eq(12)
  end

  it "can use a filter" do
    lion = create(:labor, name: "Nemean Lion", number: 1, completed: true)
    hydra = create(:labor, name: "Lernean Hydra", number: 2, completed: false)
    stables = create(:labor, name: "Augean Stables", number: 5, completed: false)
    retrieve(
      model_name: "labor",
      record_names: "all",
      attribute_names: "all",
      filter: "name~L"
    )

    json = JSON.parse(last_response.body)
    expect(json["models"]["labor"]["documents"].count).to eq(2)
  end

  it "can page results" do
    labor_list = create_list(:labor, 9)
    names = labor_list.sort_by(&:name)[6..8].map(&:name)

    retrieve(
      model_name: "labor",
      record_names: "all",
      attribute_names: "all",
      page_size: 3,
      page: 3
    )

    json = JSON.parse(last_response.body)
    expect(json["models"]["labor"]["documents"].keys).to eq(names)
  end
end
