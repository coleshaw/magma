describe Magma::TSVLoader do
  include Rack::Test::Methods

  def app
    OUTER_APP
  end

  after(:each) do
    stubs.clear
  end

  def stub_tsv txt
    stubs.create_file('tmp', 'file.tsv', txt)
  end

  it 'bulk-creates records' do
    labor_tsv = stub_tsv( <<EOT
name\tnumber\tcompleted
Nemean Lion\t1\ttrue
Lernean Hydra\t2\tfalse
Augean Stables\t5\tfalse
EOT
    )
    loader = Magma::TSVLoader.new(:labors, file: labor_tsv, model_name: 'labor')

    loader.load

    expect(Labors::Labor.count).to eq(3)
  end

  it 'bulk-updates records' do
    lion = create(:labor, name: 'Nemean Lion', number: 1, completed: false)
    hydra = create(:labor, name: "Lernean Hydra", number: 2, completed: false)

    labor_tsv = stub_tsv(<<EOT
name\tcompleted
Nemean Lion\ttrue
Augean Stables\tfalse
EOT
    )
    loader = Magma::TSVLoader.new(:labors, file: labor_tsv, model_name: 'labor')

    loader.load
    lion.refresh

    expect(Labors::Labor.count).to eq(3)
    expect(lion.completed).to eq(true)
  end

  it 'validates records' do
    labor_tsv = stub_tsv(<<EOT
name\tspecies
Nemean Lion\tLion
EOT
    )
    loader = Magma::TSVLoader.new(:labors,
      file: labor_tsv, model_name: 'monster')

    expect { loader.load }.to raise_error(Magma::LoadFailed)
  end

  it 'creates associations' do
    lion = create(:labor, name: 'Nemean Lion', number: 1, completed: false)

    prize_tsv = stub_tsv(<<EOT
labor\tname
Nemean Lion\thide
EOT
    )
    loader = Magma::TSVLoader.new(:labors,
      file: prize_tsv, model_name: 'prize')

    loader.load
    lion = Labors::Labor[name: 'Nemean Lion']

    expect(lion.prize.first.name).to eq('hide')
    expect(Labors::Prize.first.labor).to eq(lion)
  end

  it 'complains about invalid associations' do
    prize_tsv = stub_tsv(<<EOT
labor\tname
Nemean Lion\thide
EOT
    )
    loader = Magma::TSVLoader.new(:labors, file: prize_tsv, model_name: 'prize')

    expect { loader.load }.to raise_error(Magma::LoadFailed)
    expect(Labors::Prize.count).to eq(0)
  end
end
