defmodule TrifleApp.ProjectRedirectLive do
  use TrifleApp, :live_view

  def mount(%{"id" => id}, _session, socket) do
    {:ok, assign(socket, project_id: id, page_title: "Redirecting")}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/projects/#{socket.assigns.project_id}/transponders")}
  end

  def render(assigns) do
    ~H"""
    <div class="p-6 text-center text-sm text-gray-500 dark:text-slate-400">
      Redirecting to Transponders...
    </div>
    """
  end
end
