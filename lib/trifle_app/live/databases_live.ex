defmodule TrifleApp.DatabasesLive do
  use TrifleApp, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.Database

  @impl true
  def mount(_params, _session, %{assigns: %{current_membership: nil}} = socket) do
    {:ok, redirect(socket, to: ~p"/organization")}
  end

  def mount(params, _session, %{assigns: %{current_membership: membership}} = socket) do
    can_manage = Organizations.membership_owner?(membership)
    databases = Organizations.list_databases_for_org(membership.organization_id)

    socket =
      socket
      |> assign(:page_title, "Databases")
      |> assign(:databases, databases)
      |> assign(:database, nil)
      |> assign(:can_manage_databases, can_manage)

    if length(databases) == 1 and not can_manage and socket.assigns.live_action == :index do
      {:ok, push_navigate(socket, to: ~p"/dbs/#{hd(databases).id}/transponders")}
    else
      {:ok, apply_action(socket, socket.assigns.live_action, params)}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    if socket.assigns.can_manage_databases do
      socket
      |> assign(:page_title, "Databases · New")
      |> assign(:database, %Database{})
    else
      socket
      |> put_flash(:error, "Only organization owners can create databases.")
      |> push_patch(to: ~p"/dbs")
    end
  end

  defp apply_action(socket, :index, _params) do
    membership = socket.assigns.current_membership
    databases = Organizations.list_databases_for_org(membership.organization_id)

    socket
    |> assign(:page_title, "Databases")
    |> assign(:database, nil)
    |> assign(:databases, databases)
    |> maybe_redirect_single_database()
  end

  defp apply_action(socket, _action, _params), do: socket

  @impl true
  def handle_info({TrifleApp.DatabasesLive.FormComponent, {:saved, _database}}, socket) do
    {:noreply, reload_databases(socket)}
  end

  defp reload_databases(socket) do
    membership = socket.assigns.current_membership
    databases = Organizations.list_databases_for_org(membership.organization_id)

    assign(socket, :databases, databases)
  end

  defp maybe_redirect_single_database(
         %{assigns: %{databases: [single_database], can_manage_databases: false}} = socket
       ) do
    push_navigate(socket, to: ~p"/dbs/#{single_database.id}/transponders")
  end

  defp maybe_redirect_single_database(socket), do: socket

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
          <h1 class="text-base font-semibold leading-6 text-gray-900 dark:text-white">
            Your Databases
          </h1>
          <p class="mt-2 text-sm text-gray-700 dark:text-gray-300">
            Pick a database to open Dashboards, Transponders, or Explore.
          </p>
        </div>
        <%= if @can_manage_databases do %>
          <div class="mt-4 sm:mt-0 sm:ml-16 sm:flex-none">
            <.link
              patch={~p"/dbs/new"}
              class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600"
            >
              Add Database
            </.link>
          </div>
        <% end %>
      </div>

      <div class="mt-6 space-y-3">
        <%= for database <- @databases do %>
          <%= if is_supported_driver?(database.driver) do %>
            <div
              class="group flex items-center justify-between rounded-lg border border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-800 hover:bg-gray-50 dark:hover:bg-slate-700/40 transition-colors cursor-pointer"
              phx-click={JS.navigate(~p"/dbs/#{database.id}/transponders")}
            >
              <div class="flex items-center gap-3 pl-3 py-3">
                <div class={"h-10 w-1.5 rounded " <> driver_accent_class(database.driver)}></div>
                <div>
                  <div class="text-sm font-semibold text-gray-900 dark:text-white group-hover:text-teal-600 dark:group-hover:text-teal-400">
                    {database.display_name}
                  </div>
                  <div class="text-xs text-gray-500 dark:text-gray-400">
                    <.database_label driver={database.driver} />
                    <%= if database.host do %>
                      <span class="mx-2">•</span>
                      {database.host}{if database.port, do: ":#{database.port}"}
                    <% end %>
                  </div>
                </div>
              </div>
              <div class="flex items-center gap-3 pr-3">
                <%= if @can_manage_databases do %>
                  <.link
                    navigate={~p"/dbs/#{database.id}/settings"}
                    onclick="event.stopPropagation();"
                    class="hidden rounded-md border border-gray-200 dark:border-slate-600 px-2 py-1 text-xs font-medium text-gray-600 dark:text-slate-300 hover:border-teal-400 hover:text-teal-600 dark:hover:border-teal-400 dark:hover:text-teal-300 sm:inline-flex"
                  >
                    Settings
                  </.link>
                <% end %>
                <svg
                  class="h-4 w-4 text-gray-400 group-hover:text-teal-500 dark:text-gray-500 dark:group-hover:text-teal-400"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3"
                  />
                </svg>
              </div>
            </div>
          <% else %>
            <div class="group flex items-center justify-between rounded-lg border border-gray-200 dark:border-slate-700 bg-gray-50 dark:bg-slate-700/50 opacity-75">
              <div class="flex items-center gap-3 pl-3 py-3">
                <div class={"h-10 w-1.5 rounded " <> driver_accent_class(database.driver)}></div>
                <div>
                  <div class="text-sm font-semibold text-gray-700 dark:text-gray-300">
                    {database.display_name}
                  </div>
                  <div class="text-xs text-gray-500 dark:text-gray-400">
                    <.database_label driver={database.driver} />
                    <%= if database.host do %>
                      <span class="mx-2">•</span>
                      {database.host}{if database.port, do: ":#{database.port}"}
                    <% end %>
                  </div>
                </div>
              </div>
              <div class="flex items-center gap-2 pr-3">
                <%= if @can_manage_databases do %>
                  <.link
                    navigate={~p"/dbs/#{database.id}/settings"}
                    onclick="event.stopPropagation();"
                    class="hidden rounded-md border border-gray-200 dark:border-slate-600 px-2 py-1 text-xs font-medium text-gray-600 dark:text-slate-300 hover:border-teal-400 hover:text-teal-600 dark:hover:border-teal-400 dark:hover:text-teal-300 sm:inline-flex"
                  >
                    Settings
                  </.link>
                <% end %>
                <span class="inline-flex items-center rounded-md bg-gray-100 dark:bg-slate-600 px-2 py-0.5 text-[11px] font-medium text-gray-600 dark:text-gray-100 ring-1 ring-inset ring-gray-500/10 dark:ring-slate-500/40">
                  Unsupported
                </span>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>

      <%= if Enum.empty?(@databases) do %>
        <div class="text-center py-12">
          <svg
            class="mx-auto h-12 w-12 text-gray-400 dark:text-gray-500"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125"
            />
          </svg>
          <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
            No databases configured
          </h3>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            Get started by configuring your first database connection.
          </p>
          <%= if @can_manage_databases do %>
            <div class="mt-6">
              <.link
                patch={~p"/dbs/new"}
                class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600"
              >
                Add Database
              </.link>
            </div>
          <% else %>
            <p class="mt-6 text-sm text-gray-500 dark:text-gray-400">
              Ask an organization owner to add one for your team.
            </p>
          <% end %>
        </div>
      <% end %>
    </div>

    <.app_modal
      :if={@live_action == :new and @database}
      id="database-modal"
      show
      on_cancel={JS.patch(~p"/dbs")}
    >
      <:title>New Database</:title>
      <:body>
        <.live_component
          module={TrifleApp.DatabasesLive.FormComponent}
          id={@database.id || :new}
          title={@page_title}
          action={@live_action}
          database={@database}
          patch={~p"/dbs"}
        />
      </:body>
    </.app_modal>
    """
  end

  # Icon helpers for database cards
  attr :driver, :string, required: true

  defp database_icon_svg(assigns) do
    ~H"""
    <svg
      class="h-5 w-5 text-white"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="currentColor"
    >
      <%= case @driver do %>
        <% "postgres" -> %>
          <path d="M4 6c0-1.657 3.582-3 8-3s8 1.343 8 3-3.582 3-8 3-8-1.343-8-3Zm16 4c0 1.657-3.582 3-8 3s-8-1.343-8-3v4c0 1.657 3.582 3 8 3s8-1.343 8-3v-4Zm0 8c0 1.657-3.582 3-8 3s-8-1.343-8-3v2c0 1.657 3.582 3 8 3s8-1.343 8-3v-2Z" />
        <% "sqlite" -> %>
          <path d="M6 3.75A2.25 2.25 0 0 1 8.25 1.5h7.5A2.25 2.25 0 0 1 18 3.75v16.5A2.25 2.25 0 0 1 15.75 22.5h-7.5A2.25 2.25 0 0 1 6 20.25V3.75Zm3 1.5h6v1.5H9v-1.5Zm0 3h6v1.5H9v-1.5Zm0 3h6v1.5H9v-1.5Z" />
        <% "redis" -> %>
          <path d="M3.5 8.25 12 5l8.5 3.25L12 11.5 3.5 8.25Zm0 4L12 9l8.5 3.25L12 15.5 3.5 12.25Zm0 4L12 13l8.5 3.25L12 19.5 3.5 16.25Z" />
        <% "mongo" -> %>
          <path d="M12 2c.5 2 3.5 4 3.5 7.5S13 17 12 22c-1-5-3.5-9.5-3.5-12.5S11.5 4 12 2Z" />
        <% _ -> %>
          <path d="M4 6c0-1.657 3.582-3 8-3s8 1.343 8 3-3.582 3-8 3-8-1.343-8-3Zm16 4c0 1.657-3.582 3-8 3s-8-1.343-8-3v4c0 1.657 3.582 3 8 3s8-1.343 8-3v-4Zm0 8c0 1.657-3.582 3-8 3s-8-1.343-8-3v2c0 1.657 3.582 3 8 3s8-1.343 8-3v-2Z" />
      <% end %>
    </svg>
    """
  end

  defp database_icon_bg_class(driver) do
    case driver do
      "postgres" -> "h-9 w-9 rounded-md bg-blue-500/90 flex items-center justify-center shadow-sm"
      "sqlite" -> "h-9 w-9 rounded-md bg-purple-500/90 flex items-center justify-center shadow-sm"
      "redis" -> "h-9 w-9 rounded-md bg-red-500/90 flex items-center justify-center shadow-sm"
      "mongo" -> "h-9 w-9 rounded-md bg-emerald-600/90 flex items-center justify-center shadow-sm"
      _ -> "h-9 w-9 rounded-md bg-slate-500/90 flex items-center justify-center shadow-sm"
    end
  end

  defp driver_accent_class(driver) do
    case driver do
      "postgres" -> "bg-blue-500"
      "sqlite" -> "bg-purple-500"
      "redis" -> "bg-red-500"
      "mongo" -> "bg-emerald-600"
      _ -> "bg-slate-500"
    end
  end
end
