defmodule TrifleApp.DatabaseSettingsLive do
  use TrifleApp, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.Database

  @impl true
  def mount(_params, _session, %{assigns: %{current_membership: nil}} = socket) do
    {:ok, redirect(socket, to: ~p"/organization")}
  end

  def mount(%{"id" => id}, _session, %{assigns: %{current_membership: membership}} = socket) do
    if Organizations.membership_owner?(membership) do
      database = Organizations.get_database_for_org!(membership.organization_id, id)

      {:ok,
       socket
       |> assign(:can_manage_databases, true)
       |> assign(:show_edit_modal, false)
       |> assign(:config_entries, build_config_entries(database))
       |> assign_database(database)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Only organization owners can access database settings.")
       |> push_navigate(to: ~p"/dbs")}
    end
  end

  @impl true
  def handle_event("check_status", _params, socket) do
    with {:ok, updated_database, _} <- Organizations.check_database_status(load_database(socket)) do
      {:noreply,
       socket
       |> put_flash(:info, "Status check completed successfully")
       |> assign(:config_entries, build_config_entries(updated_database))
       |> assign_database(updated_database)}
    else
      {:error, updated_database, error_msg} ->
        {:noreply,
         socket
         |> put_flash(:error, "Status check failed: #{error_msg}")
         |> assign(:config_entries, build_config_entries(updated_database))
         |> assign_database(updated_database)}
    end
  end

  def handle_event("setup", _params, socket) do
    database = load_database(socket)

    case Organizations.setup_database(database) do
      {:ok, message} ->
        {:ok, updated_database, _} = Organizations.check_database_status(database)

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> assign(:config_entries, build_config_entries(updated_database))
         |> assign_database(updated_database)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Setup failed: #{error}")}
    end
  end

  def handle_event("edit", _params, socket) do
    {:noreply, assign(socket, :show_edit_modal, true)}
  end

  def handle_event("close_edit_modal", _params, socket) do
    {:noreply, assign(socket, :show_edit_modal, false)}
  end

  def handle_event("nuke", _params, socket) do
    database = load_database(socket)

    case Organizations.nuke_database(database) do
      {:ok, message} ->
        updated_database = load_database(socket)

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> assign(:config_entries, build_config_entries(updated_database))
         |> assign_database(updated_database)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error)}
    end
  end

  def handle_event("delete", _params, socket) do
    database = load_database(socket)

    case Organizations.delete_database(database) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Database deleted successfully")
         |> push_navigate(to: ~p"/dbs")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not delete database. Please try again.")}
    end
  end

  defp assign_database(socket, %Database{} = database) do
    socket
    |> assign(:database, database)
    |> assign(:page_title, "Databases · #{database.display_name} · Settings")
  end

  defp load_database(socket) do
    membership = socket.assigns.current_membership
    database_id = socket.assigns.database.id

    Organizations.get_database_for_org!(membership.organization_id, database_id)
  end

  defp build_config_entries(%Database{config: nil}), do: []

  defp build_config_entries(%Database{config: config}) when config == %{}, do: []

  defp build_config_entries(%Database{config: config}) do
    config
    |> Enum.sort_by(fn {key, _value} -> config_sort_key(key) end)
  end

  defp config_sort_key("table_name"), do: {0, "table_name"}
  defp config_sort_key("collection_name"), do: {1, "collection_name"}
  defp config_sort_key(key), do: {2, key}

  @impl true
  def handle_info({TrifleApp.DatabasesLive.FormComponent, {:saved, database}}, socket) do
    {:noreply,
     socket
     |> assign(:show_edit_modal, false)
     |> assign(:config_entries, build_config_entries(database))
     |> assign_database(database)}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, %{assigns: %{current_membership: membership}} = socket) do
    database = Organizations.get_database_for_org!(membership.organization_id, id)

    {:noreply,
     socket
     |> assign(:show_edit_modal, false)
     |> assign(:config_entries, build_config_entries(database))
     |> assign_database(database)}
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="sm:p-4">
        <div class="border-b border-gray-200 dark:border-slate-700">
          <nav class="-mb-px flex space-x-4 sm:space-x-8" aria-label="Database tabs">
            <.link
              navigate={~p"/dbs/#{@database.id}/transponders"}
              class="group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium border-transparent text-gray-500 dark:text-slate-400 hover:border-gray-300 dark:hover:border-slate-500 hover:text-gray-700 dark:hover:text-slate-300"
            >
              <svg
                class="text-gray-400 dark:text-slate-400 group-hover:text-gray-500 dark:group-hover:text-slate-300 -ml-0.5 mr-2 h-5 w-5"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M21 7.5l-2.25-1.313M21 7.5v2.25m0-2.25l-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3l2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75l2.25-1.313M12 21.75V19.5m0 2.25l-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25"
                />
              </svg>
              <span class="hidden sm:block">Transponders</span>
            </.link>
            <.link
              navigate={~p"/dbs/#{@database.id}/settings"}
              aria-current="page"
              class="group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium border-teal-500 text-teal-600 dark:text-teal-300"
            >
              <svg
                class="text-teal-400 group-hover:text-teal-500 -ml-0.5 mr-2 h-5 w-5"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M11.42 15.17L17.25 21A2.652 2.652 0 0021 17.25l-5.877-5.877M11.42 15.17l2.496-3.03c.317-.384.74-.626 1.208-.766M11.42 15.17l-4.655 5.653a2.548 2.548 0 11-3.586-3.586l6.837-5.63m5.108-.233c.55-.164 1.163-.188 1.743-.14a4.5 4.5 0 004.486-6.336l-3.276 3.277a3.004 3.004 0 01-2.25-2.25l3.276-3.276a4.5 4.5 0 00-6.336 4.486c.091 1.076-.071 2.264-.904 2.95l-.102.085m-1.745 1.437L5.909 7.5H4.5L2.25 3.75l1.5-1.5L7.5 4.5v1.409l4.26 4.26m-1.745 1.437l1.745-1.437m6.615 8.206L15.75 15.75M4.867 19.125h.008v.008h-.008v-.008z"
                />
              </svg>
              <span class="hidden sm:block">Settings</span>
            </.link>
          </nav>
        </div>
      </div>

      <div class="space-y-6 px-4 pb-6 sm:px-6 lg:px-8">
        <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg dark:bg-slate-800">
          <div class="px-4 py-6 sm:px-6">
            <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">
                  Connection overview
                </h2>
                <p class="mt-1 max-w-2xl text-sm/6 text-gray-500 dark:text-slate-400">
                  {String.capitalize(@database.driver)} database connection
                </p>
              </div>
              <div class="flex flex-wrap items-center gap-3">
                <span class={status_badge_class(@database.last_check_status)}>
                  {status_text(@database.last_check_status)}
                </span>
                <button
                  type="button"
                  phx-click="edit"
                  class="inline-flex items-center rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-semibold text-gray-700 shadow-sm hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
                >
                  Edit database
                </button>
              </div>
            </div>
          </div>
          <div class="border-t border-gray-100 dark:border-slate-700">
            <dl class="divide-y divide-gray-100 dark:divide-slate-700">
              <.detail_row label="Display name">
                {@database.display_name}
              </.detail_row>
              <.detail_row label="Driver">
                <.database_label driver={@database.driver} />
              </.detail_row>

              <%= if @database.host do %>
                <.detail_row label="Host">
                  <span class="font-mono text-sm text-gray-700 dark:text-slate-200">
                    {@database.host}{if @database.port, do: ":#{@database.port}"}
                  </span>
                </.detail_row>
              <% end %>

              <.detail_row label={database_identifier_label(@database)}>
                <span class="font-mono text-sm text-gray-700 dark:text-slate-200 break-all">
                  {database_identifier_value(@database)}
                </span>
              </.detail_row>

              <%= if @database.username do %>
                <.detail_row label="Username">
                  {@database.username}
                </.detail_row>
              <% end %>

              <%= if @database.last_check_at do %>
                <.detail_row label="Last checked">
                  {Calendar.strftime(@database.last_check_at, "%B %d, %Y at %I:%M %p UTC")}
                </.detail_row>
              <% end %>
            </dl>
          </div>
        </div>

        <%= if @database.last_error do %>
          <div class="overflow-hidden rounded-lg border border-red-100 bg-red-50 p-4 text-sm text-red-800 dark:border-red-900/40 dark:bg-red-900/20 dark:text-red-200">
            <div class="flex">
              <div class="flex-shrink-0">
                <svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                  <path
                    fill-rule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z"
                    clip-rule="evenodd"
                  />
                </svg>
              </div>
              <div class="ml-3">
                <h3 class="text-sm font-semibold">Connection error</h3>
                <p class="mt-2 text-sm">{@database.last_error}</p>
              </div>
            </div>
          </div>
        <% end %>

        <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg dark:bg-slate-800">
          <div class="px-4 py-6 sm:px-6">
            <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">
              Time configuration
            </h2>
            <p class="mt-1 max-w-2xl text-sm/6 text-gray-500 dark:text-slate-400">
              Defaults that shape how dashboards and Explore interpret timestamps.
            </p>
          </div>
          <div class="border-t border-gray-100 dark:border-slate-700">
            <dl class="divide-y divide-gray-100 dark:divide-slate-700">
              <.detail_row label="Granularities">
                <%= if @database.granularities && @database.granularities != [] do %>
                  <div class="flex flex-wrap gap-2">
                    <%= for granularity <- @database.granularities do %>
                      <span class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20 dark:bg-blue-500/10 dark:text-blue-200 dark:ring-blue-400/30">
                        {granularity}
                      </span>
                    <% end %>
                  </div>
                <% else %>
                  <span class="text-sm text-gray-500 dark:text-slate-400">
                    Using defaults (1m, 1h, 1d, 1w, 1mo, 1q, 1y)
                  </span>
                <% end %>
              </.detail_row>
              <.detail_row label="Time zone">
                {@database.time_zone || "UTC"}
              </.detail_row>
              <.detail_row label="Default timeframe">
                <%= if present?(@database.default_timeframe) do %>
                  <span class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20 dark:bg-blue-500/10 dark:text-blue-200 dark:ring-blue-400/30">
                    {@database.default_timeframe}
                  </span>
                <% else %>
                  <span class="text-sm text-gray-500 dark:text-slate-400">Not set</span>
                <% end %>
              </.detail_row>
              <.detail_row label="Default granularity">
                <%= if present?(@database.default_granularity) do %>
                  <span class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20 dark:bg-blue-500/10 dark:text-blue-200 dark:ring-blue-400/30">
                    {@database.default_granularity}
                  </span>
                <% else %>
                  <span class="text-sm text-gray-500 dark:text-slate-400">Not set</span>
                <% end %>
              </.detail_row>
            </dl>
          </div>
        </div>

        <%= if @config_entries != [] do %>
          <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg dark:bg-slate-800">
            <div class="px-4 py-6 sm:px-6">
              <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">
                Configuration options
              </h2>
              <p class="mt-1 max-w-2xl text-sm/6 text-gray-500 dark:text-slate-400">
                Driver-specific settings applied when connecting to this database.
              </p>
            </div>
            <div class="border-t border-gray-100 dark:border-slate-700">
              <dl class="divide-y divide-gray-100 dark:divide-slate-700">
                <%= for {key, value} <- @config_entries do %>
                  <.detail_row label={humanize_config_key(key)}>
                    {format_config_value(value)}
                  </.detail_row>
                <% end %>
              </dl>
            </div>
          </div>
        <% end %>

        <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg dark:bg-slate-800">
          <div class="px-4 py-6 sm:px-6">
            <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">
              Connection actions
            </h2>
            <p class="mt-1 max-w-2xl text-sm/6 text-gray-500 dark:text-slate-400">
              Use these tools to verify connectivity or rebuild supporting tables.
            </p>
          </div>
          <div class="border-t border-gray-100 px-4 py-5 sm:px-6 dark:border-slate-700">
            <div class="flex flex-wrap items-center gap-3">
              <button
                phx-click="check_status"
                type="button"
                class="inline-flex items-center rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-semibold text-gray-700 shadow-sm hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
              >
                Check status
              </button>
              <button
                phx-click="setup"
                type="button"
                class="inline-flex items-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
              >
                Setup database
              </button>
            </div>
          </div>
        </div>

        <div class="overflow-hidden border border-red-200 bg-white shadow-sm sm:rounded-lg dark:border-red-900/40 dark:bg-slate-900">
          <div class="px-4 py-6 sm:px-6">
            <div class="flex items-center justify-between">
              <div>
                <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Danger zone</h2>
                <p class="mt-1 max-w-2xl text-sm/6 text-gray-500 dark:text-slate-400">
                  Destructive actions that permanently delete data or configuration.
                </p>
              </div>
            </div>
          </div>
          <div class="border-t border-red-100 px-4 py-5 sm:px-6 dark:border-red-900/40">
            <div class="flex flex-wrap items-center justify-between gap-4">
              <div class="max-w-xl text-sm text-gray-600 dark:text-slate-300">
                <p>Remove metrics data or delete this configuration entirely.</p>
              </div>
              <div class="flex flex-wrap items-center gap-3">
                <button
                  phx-click="nuke"
                  type="button"
                  data-confirm="Are you sure you want to delete all metrics data for this database? This action cannot be undone."
                  class="inline-flex items-center rounded-md border border-red-300 bg-white px-3 py-2 text-sm font-semibold text-red-600 shadow-sm hover:bg-red-50 dark:border-red-500/40 dark:bg-transparent dark:text-red-300 dark:hover:bg-red-500/10"
                >
                  Nuke data
                </button>
                <button
                  phx-click="delete"
                  type="button"
                  data-confirm="Are you sure you want to delete this database configuration? This action cannot be undone."
                  class="inline-flex items-center rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600"
                >
                  Delete database
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <.app_modal
      :if={@show_edit_modal}
      id="database-edit-modal"
      show
      on_cancel={JS.push("close_edit_modal")}
    >
      <:title>Edit Database</:title>
      <:body>
        <.live_component
          module={TrifleApp.DatabasesLive.FormComponent}
          id={@database.id}
          title="Edit Database"
          action={:edit}
          database={@database}
          patch={~p"/dbs/#{@database.id}/settings"}
        />
      </:body>
    </.app_modal>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp detail_row(assigns) do
    ~H"""
    <div class="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
      <dt class="text-sm font-medium text-gray-900 dark:text-white">{@label}</dt>
      <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
        {render_slot(@inner_block)}
      </dd>
    </div>
    """
  end

  defp status_badge_class("success"),
    do:
      "inline-flex items-center rounded-md bg-green-50 px-2 py-1 text-xs font-medium text-green-700 ring-1 ring-inset ring-green-600/20 dark:bg-green-500/10 dark:text-green-200 dark:ring-green-400/40"

  defp status_badge_class("error"),
    do:
      "inline-flex items-center rounded-md bg-red-50 px-2 py-1 text-xs font-medium text-red-700 ring-1 ring-inset ring-red-600/20 dark:bg-red-500/10 dark:text-red-200 dark:ring-red-400/40"

  defp status_badge_class("pending"),
    do:
      "inline-flex items-center rounded-md bg-yellow-50 px-2 py-1 text-xs font-medium text-yellow-800 ring-1 ring-inset ring-yellow-600/20 dark:bg-yellow-500/10 dark:text-yellow-200 dark:ring-yellow-400/40"

  defp status_badge_class(_),
    do:
      "inline-flex items-center rounded-md bg-gray-50 px-2 py-1 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10 dark:bg-slate-700 dark:text-slate-200 dark:ring-slate-600/40"

  defp status_text("success"), do: "Connected"
  defp status_text("error"), do: "Error"
  defp status_text("pending"), do: "Pending"
  defp status_text(_), do: "Unknown"

  defp database_identifier_label(%Database{driver: "sqlite"}), do: "Database file"
  defp database_identifier_label(%Database{driver: "redis"}), do: "Database"
  defp database_identifier_label(_), do: "Database name"

  defp database_identifier_value(%Database{driver: "sqlite", file_path: nil}), do: "—"
  defp database_identifier_value(%Database{driver: "sqlite", file_path: path}), do: path
  defp database_identifier_value(%Database{driver: "redis"}), do: "Default (0)"
  defp database_identifier_value(%Database{database_name: nil}), do: "—"
  defp database_identifier_value(%Database{database_name: name}), do: name

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

  defp present?(value) when value in [nil, ""], do: false
  defp present?(_), do: true
end
