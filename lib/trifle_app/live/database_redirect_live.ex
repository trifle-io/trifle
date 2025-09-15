defmodule TrifleApp.DatabaseRedirectLive do
  use TrifleApp, :live_view

  def mount(%{"id" => id}, _session, socket) do
    {:ok, assign(socket, database_id: id)}
  end

  def handle_params(_params, _uri, socket) do
    # Redirect database root to Transponders (since database-scoped Dashboards were removed)
    {:noreply, push_navigate(socket, to: ~p"/app/dbs/#{socket.assigns.database_id}/transponders")}
  end

  def render(assigns) do
    ~H"""
    <div class="p-6 text-center text-sm text-gray-500 dark:text-slate-400">
      Redirecting to Transponders...
    </div>
    """
  end
end
