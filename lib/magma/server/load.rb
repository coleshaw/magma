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
    require_params(:project_name)
  end
end
