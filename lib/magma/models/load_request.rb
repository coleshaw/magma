class LoadRequest < Sequel::Model
  STATUS_OPEN='open'
  STATUS_COMPLETE='complete'
  STATUS_RUNNING='running'
  STATUS_FAILED='failed'
  STATUS_CANCELED='canceled'

  class << self
    def visible_attributes
      columns - [:id]
    end

    def validate
      super
      validates_includes [
        STATUS_OPEN, STATUS_COMPLETE, STATUS_RUNNING, STATUS_FAILED, STATUS_CANCELED
      ], :status
    end
  end

  def to_hash
    LoadRequest.visible_attributes.map do |attribute_name|
      [attribute_name, self[attribute_name]]
    end.to_h.merge(
      updated_at: updated_at.iso8601,
      created_at: created_at.iso8601
    )
  end

  def update_arguments!(new_arguments)
    self.arguments = new_arguments.map do |arg_name, arg|
      [
        arg_name,
        loader_class.arguments[arg_name] == File ?
          save_file(arg_name, arg[:tempfile]) : arg
      ]
    end.to_h
    save
  end

  def execute!
  end

  def files
    arguments.select do |arg_name, arg|
      loader_class.arguments[arg_name.to_sym] == File
    end.map do |arg_name, arg|
      filename(arg_name)
    end
  end

  private

  def loader_class
    Magma.instance.get_project(project_name).get_loader(loader_name)
  end

  def save_file(arg_name, tempfile)
    FileUtils.copy(tempfile.path, filename(arg_name))
    :file
  end

  def filename(arg_name)
    ::File.join(
      Magma.instance.config(:load_requests_path),
      "load-request-#{id}-#{loader_name}-#{arg_name}"
    )
  end
end
