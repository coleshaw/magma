class Stubs
  def initialize
    @stubs = []
    @bucket_name = 'files'
  end

  def create_file(project_name, name, contents)
    file_path = project_path(project_name,name)
    stub_file(file_path, contents)
    add_stub(file_path)
  end

  def create_partial(project_name, name, contents, metis_uid)
    partial_path = project_path(
      project_name,
      "uploads/#{Metis::File.safe_file_name("#{metis_uid}-#{name}")}"
    )
    stub_file(partial_path, contents)
    add_stub(partial_path)
  end

  def create_data(project_name, name, contents)
    data_path = project_path(project_name, name)
    stub_file(data_path, contents)
    add_stub(data_path)
  end

  def create_folder(project_name, name)
    folder_path = project_path(project_name, name)
    stub_dir(folder_path)
    add_stub(folder_path)
  end

  def add_file(project_name, name)
    file_path = project_path(project_name, name)
    add_stub(file_path)
  end

  def add_folder(project_name, name)
    folder_path = project_path(project_name, name)
    add_stub(folder_path)
  end

  private

  def project_path(project_name, name)
    ::File.expand_path("spec/#{project_name}/#{name}")
  end

  def stub_dir(path)
    FileUtils.mkdir_p(path)
  end

  def add_stub(path)
    return nil if path =~ %r!/files$! || path =~ %r!/\.$!
    stubs.push(path) unless stubs.include?(path)
    return path
  end

  def stub_file(path, contents)
    stub_dir(File.dirname(path))
    File.open(path,"w") do |f|
      f.print contents
    end
  end

  public

  def contents(project)
    [ :athena, :labors ].map do |project|
      [ :uploads, :files ].map do |bucket|
        Dir.glob("spec/#{project}/#{bucket}/*").to_a
      end
    end.flatten
  end

  def ensure
    [ :athena, :labors ].each do |project|
      [ :uploads, :files ].each do |bucket|
        dir = "spec/#{project}/#{bucket}"
        FileUtils.rm_r(dir) if Dir.exists?(dir)
        FileUtils.mkdir_p(dir)
      end
    end
  end

  def clear
    existing_stub_files.each { |stub| File.delete(stub) }
    existing_stub_dirs.each { |stub| FileUtils.rm_r(stub) }
    @stubs = []
  end

  private

  def existing_stub_files
    @stubs.select do |stub|
      File.exists?(stub) && !File.directory?(stub)
    end.sort_by(&:size).reverse
  end

  def existing_stub_dirs
    @stubs.select do |stub|
      File.exists?(stub) && File.directory?(stub)
    end.sort_by(&:size).reverse
  end
end
