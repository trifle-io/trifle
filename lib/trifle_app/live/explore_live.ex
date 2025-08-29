defmodule TrifleApp.ExploreLive do
  use TrifleApp, :live_view

  alias Trifle.Organizations

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Databases", databases: list_databases())}
  end

  defp list_databases do
    Organizations.list_databases()
  end

  defp driver_badge_class("redis"), do: "inline-flex items-center rounded-md bg-teal-50 px-2 py-1 text-xs font-medium text-teal-700 ring-1 ring-inset ring-teal-600/10"
  defp driver_badge_class("mongo"), do: "inline-flex items-center rounded-md bg-teal-50 px-2 py-1 text-xs font-medium text-teal-700 ring-1 ring-inset ring-teal-600/10"
  defp driver_badge_class("postgres"), do: "inline-flex items-center rounded-md bg-teal-50 px-2 py-1 text-xs font-medium text-teal-700 ring-1 ring-inset ring-teal-600/10"
  defp driver_badge_class("sqlite"), do: "inline-flex items-center rounded-md bg-teal-50 px-2 py-1 text-xs font-medium text-teal-700 ring-1 ring-inset ring-teal-600/10"
  defp driver_badge_class(_), do: "inline-flex items-center rounded-md bg-gray-50 px-2 py-1 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10"

  defp is_supported_driver?("redis"), do: true
  defp is_supported_driver?("mongo"), do: true
  defp is_supported_driver?("postgres"), do: true
  defp is_supported_driver?("sqlite"), do: true
  defp is_supported_driver?(_), do: false

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <div class="sm:flex sm:items-center">
        <div class="sm:flex-auto">
          <h1 class="text-base font-semibold leading-6 text-gray-900">Select Database to Explore</h1>
          <p class="mt-2 text-sm text-gray-700">
            Choose a database connection to explore your Trifle::Stats data.
          </p>
        </div>
      </div>
      
      <div class="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <%= for database <- @databases do %>
          <%= if is_supported_driver?(database.driver) do %>
            <.link navigate={~p"/app/dbs/#{database.id}"} class="group block">
              <div class="rounded-lg border border-gray-200 bg-white p-6 shadow-sm hover:shadow-md transition-shadow duration-200 hover:border-gray-300">
                <div class="flex items-center justify-between">
                  <h3 class="text-lg font-medium text-gray-900 group-hover:text-teal-600">
                    <%= database.display_name %>
                  </h3>
                  <svg class="h-5 w-5 text-gray-400 group-hover:text-teal-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3" />
                  </svg>
                </div>
                
                <div class="mt-4 flex items-center space-x-4">
                  <span class={driver_badge_class(database.driver)}>
                    <%= String.capitalize(database.driver) %>
                  </span>
                  
                  <%= if database.host do %>
                    <span class="text-sm text-gray-500">
                      <%= database.host %><%= if database.port, do: ":#{database.port}" %>
                    </span>
                  <% end %>
                </div>
                
                <div class="mt-2 text-sm text-gray-600">
                  <%= cond do %>
                    <% database.driver == "sqlite" -> %>
                      <%= database.file_path || "No file path configured" %>
                    <% database.driver == "redis" -> %>
                      Redis cache database
                    <% true -> %>
                      <%= database.database_name || "No database name" %>
                  <% end %>
                </div>
              </div>
            </.link>
          <% else %>
            <div class="group block opacity-60">
              <div class="rounded-lg border border-gray-200 bg-gray-50 p-6 shadow-sm">
                <div class="flex items-center justify-between">
                  <h3 class="text-lg font-medium text-gray-700">
                    <%= database.display_name %>
                  </h3>
                  <svg class="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728L5.636 5.636m12.728 12.728L18.364 5.636M5.636 18.364l12.728-12.728" />
                  </svg>
                </div>
                
                <div class="mt-4 flex items-center space-x-4">
                  <span class={driver_badge_class(database.driver)}>
                    <%= String.capitalize(database.driver) %>
                  </span>
                  
                  <%= if database.host do %>
                    <span class="text-sm text-gray-400">
                      <%= database.host %><%= if database.port, do: ":#{database.port}" %>
                    </span>
                  <% end %>
                </div>
                
                <div class="mt-2 text-sm text-gray-500">
                  Driver not yet supported for exploration
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
      
      <%= if Enum.empty?(@databases) do %>
        <div class="text-center py-12">
          <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125" />
          </svg>
          <h3 class="mt-2 text-sm font-semibold text-gray-900">No databases configured</h3>
          <p class="mt-1 text-sm text-gray-500">Get started by configuring your first database connection.</p>
          <%= if @current_user.is_admin do %>
            <div class="mt-6">
              <.link navigate={~p"/admin/databases/new"} class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600">
                Add Database
              </.link>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end