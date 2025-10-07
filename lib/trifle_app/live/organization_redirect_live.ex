defmodule TrifleApp.OrganizationRedirectLive do
  use TrifleApp, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Redirecting")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/organization/profile")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 text-center text-sm text-gray-500 dark:text-slate-400">
      Redirecting to Organization profile...
    </div>
    """
  end
end
