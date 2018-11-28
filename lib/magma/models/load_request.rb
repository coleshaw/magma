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
    self.arguments = replace_file_arguments(new_arguments) do |file_arg_name, file|
       save_file(file_arg_name, file[:tempfile])
    end
    save
  end


  def execute!
    task = loader.new(
      project_name,
      replace_file_arguments do |file_arg_name|
        filename(file_arg_name)
      end
    )
    task.load

    set_state(
      LoadRequest::STATUS_COMPLETE,
      "Loading complete, #{task.insert_count} records inserted and #{task.update_count} updated."
    )
  rescue Magma::LoadFailed => e
    set_state(
      LoadRequest::STATUS_FAILED,
      "Loading failed with these complaints:\n#{e.complaints.map{|c| " - #{c}"}.join("\n")}"
    )
  rescue Exception => e
    set_state(
      LoadRequest::STATUS_FAILED, 'Loading failed: the loader crashed.'
    )
  ensure
    cleanup!
  end

  def files
    arguments.select do |arg_name, arg|
      loader.file_argument?(arg_name)
    end.map do |arg_name, arg|
      filename(arg_name)
    end
  end

  private

  def cleanup!
    files.each do |file|
      ::File.unlink(file) if ::File.exists?(file)
    end
  end

  def set_state(status, message)
    self.status = status
    self.message = message
    self.save
  end

  def loader
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

  def replace_file_arguments(new_arguments=nil)
    (new_arguments || self.arguments).map do |arg_name, arg|
      [
        arg_name.to_sym,
        loader.file_argument?(arg_name) ?
        yield(arg_name, arg) : arg
      ]
    end.to_h
  end
end
