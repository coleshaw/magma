require_relative 'controller'

class LoadController < Magma::Controller
  def initialize(request, action)
    super
    require_param(:loader)
  end

  def status
    tasks = LoaderTask.for_project(@params[:project_name])

    success(tasks.map(&:to_hash).to_json, 'application/json')
  end

  def schedule
    require_params(:project_name, :loader_name)

    arguments = @params.except(:project_name, :loader_name)

    loader = Magma.instance.get_project(@params[:project_name]).get_loader(@params[:loader_name])

    raise Etna::BadRequest, "No such loader #{@params[:loader_name]}." unless loader

    missing_arguments = loader.missing_arguments(arguments)
    unless missing_arguments.empty?
      raise Etna::BadRequest, "Missing params #{missing_arguments.join(', ')} for loader #{@params[:loader_name]}."
    end

    invalid_arguments = loader.invalid_arguments(arguments)
    unless invalid_arguments.empty?
      raise Etna::BadRequest, "Invalid params #{invalid_arguments.join(', ')} for loader #{@params[:loader_name]}."
    end

    task = LoadRequest.create(
      project_name: @params[:project_name],
      loader_name: @params[:loader_name],
      user: @user.email,
      arguments: {},
      status: LoadRequest::STATUS_OPEN,
      message: 'Request is queued.'
    )
    task.update_arguments!(arguments)
    task.save

    success(task.to_hash.to_json, 'application/json')
  end
end
