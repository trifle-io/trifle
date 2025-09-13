defmodule TrifleApp.DatabaseRedirectLive do
  use TrifleApp, :live_view

  def mount(%{"id" => id}, _session, socket) do
    {:ok, assign(socket, database_id: id)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/app/dbs/#{socket.assigns.database_id}/dashboards")}
  end

  def render(assigns) do
    ~H"""
    <div class="p-6 text-center text-sm text-gray-500 dark:text-slate-400">
      Redirecting to Dashboards...
    </div>
    """
  end
end

