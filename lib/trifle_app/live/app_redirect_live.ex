defmodule TrifleApp.AppRedirectLive do
  use TrifleApp, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/dashboards")}
  end

  def render(assigns) do
    ~H"""
    <div class="p-6 text-center text-sm text-gray-500 dark:text-slate-400">
      Redirecting to Dashboards...
    </div>
    """
  end
end
