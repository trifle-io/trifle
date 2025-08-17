defmodule TrifleAdmin.AdminLive do
  use TrifleAdmin, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Admin Dashboard")}
  end

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <div class="sm:flex sm:items-center">
        <div class="sm:flex-auto">
          <h1 class="text-base font-semibold leading-6 text-gray-900">Admin Dashboard</h1>
          <p class="mt-2 text-sm text-gray-700">
            Welcome to the admin area. Use the navigation above to manage the system.
          </p>
        </div>
      </div>
    </div>
    """
  end
end