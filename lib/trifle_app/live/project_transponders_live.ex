defmodule TrifleApp.ProjectTranspondersLive do
  use TrifleApp, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.Project

  def render(assigns) do
    ~H"""
    <div class="sm:p-4">
      <.project_nav project={@project} current={:transponders} />
    </div>
    """
  end

  def mount(params, _session, socket) do
    project = Organizations.get_project!(params["id"])

    {:ok,
     assign(socket, page_title: "Projects · #{project.name} · Transponders", project: project)}
  end
end
