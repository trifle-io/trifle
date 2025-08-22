defmodule TrifleAdmin.DatabasesLive.DetailsComponent do
  use TrifleAdmin, :live_component

  alias Trifle.Organizations

  @impl true
  def render(assigns) do
    ~H"""
    <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
      <div class="px-4 py-6 sm:px-6">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="text-base/7 font-semibold text-gray-900"><%= @database.display_name %></h3>
            <p class="mt-1 max-w-2xl text-sm/6 text-gray-500"><%= String.capitalize(@database.driver) %> database connection</p>
          </div>
          <span class={status_badge_class(@database.last_check_status)}>
            <%= status_text(@database.last_check_status) %>
          </span>
        </div>
      </div>
      <div class="border-t border-gray-100">
        <dl class="divide-y divide-gray-100">
          <div class="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
            <dt class="text-sm font-medium text-gray-900">Driver</dt>
            <dd class="mt-1 text-sm/6 text-gray-700 sm:col-span-2 sm:mt-0">
              <span class={driver_badge_class(@database.driver)}>
                <%= String.capitalize(@database.driver) %>
              </span>
            </dd>
          </div>
            
          <%= if @database.host do %>
            <div class="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-900">Host</dt>
              <dd class="mt-1 text-sm/6 text-gray-700 sm:col-span-2 sm:mt-0 font-mono">
                <%= @database.host %><%= if @database.port, do: ":#{@database.port}" %>
              </dd>
            </div>
          <% end %>
            
          <div class="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
            <dt class="text-sm font-medium text-gray-900">
              <%= cond do %>
                <% @database.driver == "sqlite" -> %>Database file
                <% @database.driver == "redis" -> %>Database
                <% true -> %>Database name
              <% end %>
            </dt>
            <dd class="mt-1 text-sm/6 text-gray-700 sm:col-span-2 sm:mt-0 font-mono break-all">
              <%= cond do %>
                <% @database.driver == "sqlite" -> %>
                  <%= @database.file_path || "—" %>
                <% @database.driver == "redis" -> %>
                  Default (0)
                <% true -> %>
                  <%= @database.database_name || "—" %>
              <% end %>
            </dd>
          </div>
            
          <%= if @database.username do %>
            <div class="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-900">Username</dt>
              <dd class="mt-1 text-sm/6 text-gray-700 sm:col-span-2 sm:mt-0"><%= @database.username %></dd>
            </div>
          <% end %>

          <%= if @database.last_check_at do %>
            <div class="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-900">Last checked</dt>
              <dd class="mt-1 text-sm/6 text-gray-700 sm:col-span-2 sm:mt-0">
                <%= Calendar.strftime(@database.last_check_at, "%B %d, %Y at %I:%M %p UTC") %>
              </dd>
            </div>
          <% end %>

          <!-- Granularities -->
          <div class="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
            <dt class="text-sm font-medium text-gray-900">Time granularities</dt>
            <dd class="mt-1 text-sm/6 text-gray-700 sm:col-span-2 sm:mt-0">
              <%= if @database.granularities && length(@database.granularities) > 0 do %>
                <div class="flex flex-wrap gap-1">
                  <%= for granularity <- @database.granularities do %>
                    <span class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20">
                      <%= granularity %>
                    </span>
                  <% end %>
                </div>
              <% else %>
                <span class="text-gray-500">Using defaults (1m, 1h, 1d, 1w, 1mo, 1q, 1y)</span>
              <% end %>
            </dd>
          </div>
          
          <!-- Time Zone -->
          <div class="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
            <dt class="text-sm font-medium text-gray-900">Time Zone</dt>
            <dd class="mt-1 text-sm/6 text-gray-700 sm:col-span-2 sm:mt-0">
              <%= @database.time_zone || "UTC" %>
            </dd>
          </div>

          <%= for {key, value} <- (@database.config || %{}) do %>
            <div class="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-900"><%= humanize_config_key(key) %></dt>
              <dd class="mt-1 text-sm/6 text-gray-700 sm:col-span-2 sm:mt-0"><%= format_config_value(value) %></dd>
            </div>
          <% end %>
        </dl>
      </div>
      
      <%= if @database.last_error do %>
        <div class="border-t border-gray-100 px-4 py-6 sm:px-6">
          <div class="rounded-md bg-red-50 p-4">
            <div class="flex">
              <div class="flex-shrink-0">
                <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clip-rule="evenodd" />
                </svg>
              </div>
              <div class="ml-3">
                <h3 class="text-sm font-medium text-red-800">Connection Error</h3>
                <div class="mt-2 text-sm text-red-700">
                  <p><%= @database.last_error %></p>
                </div>
              </div>
            </div>
          </div>
        </div>
      <% end %>
      
      <div class="border-t border-gray-100 px-4 py-6 sm:px-6">
        <div class="flex items-center justify-end gap-x-6">
          <button
            phx-click="check_status"
            phx-value-id={@database.id}
            phx-target={@myself}
            type="button"
            class="text-sm font-semibold leading-6 text-gray-900"
          >
            Check status
          </button>
          
          <.link
            patch={~p"/admin/databases/#{@database}/edit"}
            class="text-sm font-semibold leading-6 text-gray-900"
          >
            Edit
          </.link>
          
          <button
            phx-click="setup"
            phx-value-id={@database.id}
            phx-target={@myself}
            type="button"
            class="rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
          >
            Setup database
          </button>
        </div>
        
        <div class="mt-6 border-t border-gray-100 pt-6">
          <div class="flex items-center justify-between">
            <p class="text-sm text-gray-500">Danger zone</p>
            <div class="flex gap-x-4">
              <button
                phx-click="nuke"
                phx-value-id={@database.id}
                phx-target={@myself}
                data-confirm="Are you sure you want to delete all data? This action cannot be undone."
                type="button"
                class="text-sm font-semibold text-red-600 hover:text-red-500"
              >
                Nuke data
              </button>
              <button
                phx-click="delete"
                phx-value-id={@database.id}
                phx-target={@myself}
                data-confirm="Are you sure you want to delete this database configuration?"
                type="button"
                class="text-sm font-semibold text-red-600 hover:text-red-500"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("check_status", %{"id" => id}, socket) do
    database = Organizations.get_database!(id)
    
    case Organizations.check_database_status(database) do
      {:ok, updated_database, _setup_exists} ->
        send(self(), {:flash, :info, "Status check completed successfully"})
        send(self(), :refresh_databases)
        {:noreply, assign(socket, :database, updated_database)}
      {:error, updated_database, error_msg} ->
        send(self(), {:flash, :error, "Status check failed: #{error_msg}"})
        send(self(), :refresh_databases)
        {:noreply, assign(socket, :database, updated_database)}
    end
  end

  def handle_event("setup", %{"id" => id}, socket) do
    database = Organizations.get_database!(id)
    
    case Organizations.setup_database(database) do
      {:ok, message} ->
        {:ok, updated_database, _setup_exists} = Organizations.check_database_status(database)
        send(self(), {:flash, :info, message})
        send(self(), :refresh_databases)
        {:noreply, assign(socket, :database, updated_database)}
      {:error, error} ->
        send(self(), {:flash, :error, "Setup failed: #{error}"})
        send(self(), :refresh_databases)
        {:noreply, socket}
    end
  end

  def handle_event("nuke", %{"id" => id}, socket) do
    database = Organizations.get_database!(id)
    
    case Organizations.nuke_database(database) do
      {:ok, message} ->
        # Refresh the database record after nuke operation
        updated_database = Organizations.get_database!(id)
        send(self(), {:flash, :info, message})
        send(self(), :refresh_databases)
        {:noreply, assign(socket, :database, updated_database)}
      {:error, error} ->
        send(self(), {:flash, :error, error})
        send(self(), :refresh_databases)
        {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    database = Organizations.get_database!(id)
    {:ok, _} = Organizations.delete_database(database)

    send(self(), {:flash, :info, "Database deleted successfully"})
    send(self(), :refresh_and_close)
    {:noreply, socket}
  end

  defp status_badge_class("success"), do: "inline-flex items-center rounded-md bg-green-50 px-2 py-1 text-xs font-medium text-green-700 ring-1 ring-inset ring-green-600/20"
  defp status_badge_class("error"), do: "inline-flex items-center rounded-md bg-red-50 px-2 py-1 text-xs font-medium text-red-700 ring-1 ring-inset ring-red-600/20"
  defp status_badge_class("pending"), do: "inline-flex items-center rounded-md bg-yellow-50 px-2 py-1 text-xs font-medium text-yellow-800 ring-1 ring-inset ring-yellow-600/20"
  defp status_badge_class(_), do: "inline-flex items-center rounded-md bg-gray-50 px-2 py-1 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10"
  
  defp driver_badge_class("redis"), do: "inline-flex items-center rounded-md bg-red-50 px-2 py-1 text-xs font-medium text-red-700 ring-1 ring-inset ring-red-600/10"
  defp driver_badge_class("postgres"), do: "inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-700/10"
  defp driver_badge_class("mongo"), do: "inline-flex items-center rounded-md bg-green-50 px-2 py-1 text-xs font-medium text-green-700 ring-1 ring-inset ring-green-600/20"
  defp driver_badge_class("sqlite"), do: "inline-flex items-center rounded-md bg-gray-50 px-2 py-1 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10"
  defp driver_badge_class(_), do: "inline-flex items-center rounded-md bg-gray-50 px-2 py-1 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10"

  defp status_text("success"), do: "Connected"
  defp status_text("error"), do: "Error"
  defp status_text("pending"), do: "Pending"
  defp status_text(_), do: "Unknown"


  defp humanize_config_key(key) do
    key
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_config_value(nil), do: "Not set"
  defp format_config_value(true), do: "Enabled"
  defp format_config_value(false), do: "Disabled"
  defp format_config_value(value) when is_binary(value), do: value
  defp format_config_value(value), do: to_string(value)
end