defmodule TrifleApp.TranspondersLive do
  use TrifleApp, :live_view
  alias Ecto.NoResultsError
  alias Trifle.Organizations
  alias Trifle.Organizations.{Database, Project, Transponder}

  def mount(params, _session, socket) do
    case resolve_source(socket.assigns.live_action, params, socket.assigns) do
      {:ok, source_assigns} ->
        transponders = list_transponders_for_source(source_assigns.source)

        {:ok,
         socket
         |> assign(source_assigns)
         |> assign(:transponder, nil)
         |> assign(:ui_action, :index)
         |> assign(:transponders_empty, Enum.empty?(transponders))
         |> stream(:transponders, transponders)}

      {:redirect, to} ->
        {:ok, redirect(socket, to: to)}
    end
  end

  defp resolve_source(action, params, assigns) do
    cond do
      action in [:database_index, :database_new, :database_show, :database_edit] ->
        resolve_database_source(params, assigns)

      action in [:project_index, :project_new, :project_show, :project_edit] ->
        resolve_project_source(params, assigns)

      true ->
        {:redirect, ~p"/"}
    end
  end

  defp resolve_database_source(%{"id" => _database_id}, %{current_membership: nil}) do
    {:redirect, ~p"/organization"}
  end

  defp resolve_database_source(%{"id" => database_id}, %{current_membership: membership}) do
    database = Organizations.get_database_for_org!(membership.organization_id, database_id)

    {:ok,
     %{
       source_type: :database,
       source: database,
       database: database,
       nav_section: :databases,
       breadcrumb_links: [
         {"Database", ~p"/dbs"},
         {database.display_name, ~p"/dashboards"},
         "Transponders"
       ],
       page_title: page_title_for_action(:index, :database, database)
     }}
  end

  defp resolve_project_source(%{"id" => project_id}, assigns) do
    project = Organizations.get_project!(project_id)

    current_user = assigns[:current_user]

    cond do
      is_nil(current_user) ->
        {:redirect, ~p"/projects"}

      project.user_id != current_user.id ->
        {:redirect, ~p"/projects"}

      true ->
        {:ok,
         %{
           source_type: :project,
           source: project,
           project: project,
           nav_section: :projects,
           breadcrumb_links: [
             {"Projects", ~p"/projects"},
             {project.name || "Project", ~p"/projects/#{project.id}/transponders"}
           ],
           page_title: page_title_for_action(:index, :project, project)
         }}
    end
  rescue
    Ecto.NoResultsError -> {:redirect, ~p"/projects"}
  end

  defp list_transponders_for_source(%Database{} = database) do
    Organizations.list_transponders_for_database(database)
  end

  defp list_transponders_for_source(%Project{} = project) do
    Organizations.list_transponders_for_project(project)
  end

  defp base_action(action) when action in [:database_index, :project_index], do: :index
  defp base_action(action) when action in [:database_new, :project_new], do: :new
  defp base_action(action) when action in [:database_show, :project_show], do: :show
  defp base_action(action) when action in [:database_edit, :project_edit], do: :edit
  defp base_action(_), do: :index

  defp page_title_for_action(action, source_type, source, transponder \\ nil)

  defp page_title_for_action(:index, :database, %Database{} = database, _transponder) do
    "Database · #{database.display_name} · Transponders"
  end

  defp page_title_for_action(:index, :project, %Project{} = project, _transponder) do
    "Projects · #{project.name} · Transponders"
  end

  defp page_title_for_action(:new, :database, %Database{} = database, _transponder) do
    "Database · #{database.display_name} · New Transponder"
  end

  defp page_title_for_action(:new, :project, %Project{} = project, _transponder) do
    "Projects · #{project.name} · New Transponder"
  end

  defp page_title_for_action(:show, source_type, source, %Transponder{} = transponder) do
    base = page_title_for_action(:index, source_type, source)
    transponder_label = transponder.name || transponder.key
    base <> " · " <> (transponder_label || "Transponder")
  end

  defp page_title_for_action(:edit, source_type, source, %Transponder{} = transponder) do
    base = page_title_for_action(:index, source_type, source)
    transponder_label = transponder.name || transponder.key
    base <> " · Edit #{transponder_label || "Transponder"}"
  end

  defp page_title_for_action(_other, _source_type, _source, _transponder) do
    "Transponders"
  end

  defp load_transponder(%Database{} = database, id) do
    Organizations.get_transponder_for_source!(database, id)
  end

  defp load_transponder(%Project{} = project, id) do
    Organizations.get_transponder_for_source!(project, id)
  end

  defp create_transponder_for_source(%Database{} = database, attrs) do
    Organizations.create_transponder_for_database(database, attrs)
  end

  defp create_transponder_for_source(%Project{} = project, attrs) do
    Organizations.create_transponder_for_project(project, attrs)
  end

  defp maybe_put_database_id(attrs, %Database{} = database) do
    Map.put(attrs, "database_id", database.id)
  end

  defp maybe_put_database_id(attrs, _), do: attrs

  defp transponder_index_path(:database, %Database{id: id}), do: ~p"/dbs/#{id}/transponders"
  defp transponder_index_path(:project, %Project{id: id}), do: ~p"/projects/#{id}/transponders"

  defp transponder_new_path(:database, %Database{id: id}), do: ~p"/dbs/#{id}/transponders/new"
  defp transponder_new_path(:project, %Project{id: id}), do: ~p"/projects/#{id}/transponders/new"

  defp transponder_show_path(:database, %Database{id: id}, transponder_id),
    do: ~p"/dbs/#{id}/transponders/#{transponder_id}"

  defp transponder_show_path(:project, %Project{id: id}, transponder_id),
    do: ~p"/projects/#{id}/transponders/#{transponder_id}"

  defp transponder_edit_path(:database, %Database{id: id}, transponder_id),
    do: ~p"/dbs/#{id}/transponders/#{transponder_id}/edit"

  defp transponder_edit_path(:project, %Project{id: id}, transponder_id),
    do: ~p"/projects/#{id}/transponders/#{transponder_id}/edit"

  defp transponder_form_cancel_path(source_type, source) do
    transponder_index_path(source_type, source)
  end

  defp transponder_settings_path(:database, %Database{id: id}), do: ~p"/dbs/#{id}/settings"
  defp transponder_settings_path(:project, %Project{id: id}), do: ~p"/projects/#{id}/settings"
  defp transponder_settings_path(_, _), do: nil

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, live_action, params) do
    source_type = socket.assigns.source_type
    source = socket.assigns.source
    base_action = base_action(live_action)

    socket =
      socket
      |> assign(:page_title, page_title_for_action(base_action, source_type, source))
      |> assign(:ui_action, base_action)

    case {base_action, params} do
      {:index, _} ->
        assign(socket, :transponder, nil)

      {:new, _} ->
        assign(socket, :transponder, %Transponder{source_type: Atom.to_string(source_type)})

      {action, %{"transponder_id" => transponder_id}} when action in [:show, :edit] ->
        transponder = load_transponder(source, transponder_id)

        assign(socket, :transponder, transponder)
        |> assign(:page_title, page_title_for_action(action, source_type, source, transponder))

      _ ->
        assign(socket, :transponder, nil)
    end
  end

  def handle_info({TrifleApp.TranspondersLive.FormComponent, {:saved, transponder}}, socket) do
    {:noreply,
     socket
     |> assign(:transponders_empty, false)
     |> stream_insert(:transponders, transponder)}
  end

  def handle_info({TrifleApp.TranspondersLive.FormComponent, {:updated, transponder}}, socket) do
    {:noreply,
     socket
     |> assign(:transponders_empty, false)
     |> stream_insert(:transponders, transponder)}
  end

  def handle_event("delete_transponder", %{"id" => id}, socket) do
    source = socket.assigns.source
    transponder = load_transponder(source, id)
    {:ok, _} = Organizations.delete_transponder(transponder)

    remaining_transponders = list_transponders_for_source(source)
    remaining_ids = Enum.map(remaining_transponders, & &1.id)
    {:ok, _} = Organizations.update_transponder_order(source, remaining_ids)

    transponders = list_transponders_for_source(source)

    {:noreply,
     socket
     |> assign(:transponders_empty, Enum.empty?(transponders))
     |> stream(:transponders, transponders, reset: true)
     |> put_flash(:info, "Transponder deleted successfully")}
  end

  def handle_event("toggle_transponder", %{"id" => id}, socket) do
    source = socket.assigns.source
    transponder = load_transponder(source, id)

    {:ok, updated_transponder} =
      Organizations.update_transponder(transponder, %{enabled: !transponder.enabled})

    {:noreply, stream_insert(socket, :transponders, updated_transponder)}
  end

  def handle_event("duplicate_transponder", %{"id" => id}, socket) do
    source = socket.assigns.source
    original = load_transponder(source, id)
    next_order = Organizations.get_next_transponder_order(source)

    attrs =
      %{
        "name" => (original.name || original.key) <> " (copy)",
        "key" => original.key,
        "type" => original.type,
        "config" => original.config || %{},
        "enabled" => false,
        "order" => next_order
      }
      |> maybe_put_database_id(source)

    case create_transponder_for_source(source, attrs) do
      {:ok, transponder} ->
        {:noreply,
         socket
         |> assign(:transponders_empty, false)
         |> stream_insert(:transponders, transponder)
         |> put_flash(:info, "Transponder duplicated")}

      {:error, _cs} ->
        {:noreply, put_flash(socket, :error, "Could not duplicate transponder")}
    end
  end

  def handle_event("reorder_transponders", %{"ids" => ids}, socket) do
    source = socket.assigns.source

    case Organizations.update_transponder_order(source, ids) do
      {:ok, _} ->
        # Reload the transponders to reflect the new order
        transponders = list_transponders_for_source(source)

        {:noreply,
         socket
         |> assign(:transponders_empty, Enum.empty?(transponders))
         |> stream(:transponders, transponders, reset: true)
         |> put_flash(:info, "Transponder order updated successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update transponder order")}
    end
  end

  # Row click navigations and helpers
  def handle_event("transponder_clicked", %{"id" => id}, socket) do
    path = transponder_show_path(socket.assigns.source_type, socket.assigns.source, id)
    {:noreply, push_patch(socket, to: path)}
  end

  # No-op click to prevent row click bubbling
  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col dark:bg-slate-900 min-h-screen">
      <% index_path = transponder_index_path(@source_type, @source) %>
      <% new_path = transponder_new_path(@source_type, @source) %>
      <% settings_path = transponder_settings_path(@source_type, @source) %>
      <% show_path = fn id -> transponder_show_path(@source_type, @source, id) end %>
      <% edit_path = fn id -> transponder_edit_path(@source_type, @source, id) end %>
      <% cancel_path = transponder_form_cancel_path(@source_type, @source) %>

      <div class="space-y-6">
        <div class="sm:p-4">
          <%= if @source_type == :database do %>
            <div class="border-b border-gray-200 dark:border-slate-700">
              <nav class="-mb-px flex space-x-4 sm:space-x-8" aria-label="Database tabs">
                <.link
                  navigate={index_path}
                  class="group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium border-teal-500 text-teal-600 dark:text-teal-300"
                  aria-current="page"
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
                      d="M21 7.5l-2.25-1.313M21 7.5v2.25m0-2.25l-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3l2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75l2.25-1.313M12 21.75V19.5m0 2.25l-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25"
                    />
                  </svg>
                  <span class="hidden sm:block">Transponders</span>
                </.link>

                <%= if settings_path do %>
                  <.link
                    navigate={settings_path}
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
                        d="M11.42 15.17L17.25 21A2.652 2.652 0 0021 17.25l-5.877-5.877M11.42 15.17l2.496-3.03c.317-.384.74-.626 1.208-.766M11.42 15.17l-4.655 5.653a2.548 2.548 0 11-3.586-3.586l6.837-5.63m5.108-.233c.55-.164 1.163-.188 1.743-.14a4.5 4.5 0 004.486-6.336l-3.276 3.277a3.004 3.004 0 01-2.25-2.25l3.276-3.276a4.5 4.5 0 00-6.336 4.486c.091 1.076-.071 2.264-.904 2.95l-.102.085m-1.745 1.437L5.909 7.5H4.5L2.25 3.75l1.5-1.5L7.5 4.5v1.409l4.26 4.26m-1.745 1.437l1.745-1.437m6.615 8.206L15.75 15.75M4.867 19.125h.008v.008h-.008v-.008z"
                      />
                    </svg>
                    <span class="hidden sm:block">Settings</span>
                  </.link>
                <% end %>
              </nav>
            </div>
          <% else %>
            <.project_nav project={@project} current={:transponders} />
          <% end %>
        </div>

        <div class="px-4 pb-6 sm:px-6 lg:px-8">
          <div class="bg-white dark:bg-slate-800 rounded-lg shadow">
            <div class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 dark:text-white sm:pl-3 border-b border-gray-100 dark:border-slate-700 flex items-center justify-between">
              <div class="flex items-center gap-2">
                <span>Transponders</span>
                <span class="inline-flex items-center rounded-md bg-teal-50 dark:bg-teal-900 px-2 py-1 text-xs font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30">
                  {Enum.count(@streams.transponders)}
                </span>
              </div>
              <.link
                patch={new_path}
                class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
              >
                <svg class="h-5 w-5 md:-ml-0.5 md:mr-1.5" viewBox="0 0 20 20" fill="currentColor">
                  <path d="M10.75 4.75a.75.75 0 00-1.5 0v4.5h-4.5a.75.75 0 000 1.5h4.5v4.5a.75.75 0 001.5 0v-4.5h4.5a.75.75 0 000-1.5h-4.5v-4.5z" />
                </svg>
                <span class="hidden md:inline">New Transponder</span>
              </.link>
            </div>

            <div class="divide-y divide-gray-100 dark:divide-slate-700">
              <%= if @transponders_empty do %>
                <div class="py-12 text-center">
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
                      d="M21 7.5l-2.25-1.313M21 7.5v2.25m0-2.25l-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3l2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75l2.25-1.313M12 21.75V19.5m0 2.25l-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25"
                    />
                  </svg>
                  <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
                    No transponders
                  </h3>
                  <p class="mt-1 text-sm text-gray-500 dark:text-slate-400">
                    Get started by creating a new transponder.
                  </p>
                </div>
              <% end %>

              <div
                id="transponders"
                phx-update="stream"
                phx-hook="Sortable"
                data-group="transponders"
                data-handle=".drag-handle"
                class={[@transponders_empty && "hidden"]}
              >
                <%= for {dom_id, transponder} <- @streams.transponders do %>
                  <div
                    id={dom_id}
                    class="px-4 py-4 sm:px-6 group border-b border-gray-100 dark:border-slate-700 last:border-b-0 cursor-pointer hover:bg-gray-50 dark:hover:bg-slate-700/50"
                    data-id={transponder.id}
                    phx-click="transponder_clicked"
                    phx-value-id={transponder.id}
                  >
                    <div class="flex items-center justify-between">
                      <div class="flex items-center gap-3">
                        <div class="flex-shrink-0 text-gray-400 dark:text-slate-500 text-lg font-medium min-w-[2rem] text-center">
                          {transponder.order + 1}
                        </div>

                        <div class="min-w-0 flex-1">
                          <div class="flex items-center gap-2 mb-1">
                            <span class="inline-flex items-center rounded-md bg-teal-50 dark:bg-teal-900 px-2 py-1 text-xs font-medium text-teal-700 dark:text-teal-200">
                              {Transponder.get_type_display_name(transponder.type)}
                            </span>
                            <.link
                              patch={show_path.(transponder.id)}
                              class="text-sm font-medium text-gray-900 dark:text-white hover:text-teal-600 dark:hover:text-teal-400"
                            >
                              {transponder.name || transponder.key}
                            </.link>
                          </div>
                          <p class="text-xs text-gray-500 dark:text-slate-400">
                            Key Pattern:
                            <code class="bg-gray-100 dark:bg-slate-700 px-1 py-0.5 rounded font-mono">
                              {transponder.key}
                            </code>
                            <span class="mx-3">•</span>
                            Response Path:
                            <code class="bg-gray-100 dark:bg-slate-700 px-1 py-0.5 rounded font-mono">
                              {Map.get(transponder.config, "response_path", "N/A")}
                            </code>
                          </p>
                        </div>
                      </div>

                      <div class="flex items-center gap-2" phx-click="noop">
                        <div class="flex items-center gap-2 opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none group-hover:pointer-events-auto">
                          <!-- Duplicate -->
                          <button
                            type="button"
                            phx-click="duplicate_transponder"
                            phx-value-id={transponder.id}
                            title="Duplicate"
                            aria-label="Duplicate transponder"
                            class="inline-flex items-center justify-center rounded-md border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 p-1.5 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-50 dark:hover:bg-slate-700"
                          >
                            <svg
                              xmlns="http://www.w3.org/2000/svg"
                              fill="none"
                              viewBox="0 0 24 24"
                              stroke-width="1.5"
                              stroke="currentColor"
                              class="h-5 w-5"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                d="M15.75 17.25v3.375c0 .621-.504 1.125-1.125 1.125h-9.75a1.125 1.125 0 0 1-1.125-1.125V7.875c0-.621.504-1.125 1.125-1.125H6.75a9.06 9.06 0 0 1 1.5.124m7.5 10.376h3.375c.621 0 1.125-.504 1.125-1.125V11.25c0-4.46-3.243-8.161-7.5-8.876a9.06 9.06 0 0 0-1.5-.124H9.375c-.621 0-1.125.504-1.125 1.125v3.5m7.5 10.375H9.375a1.125 1.125 0 0 1-1.125-1.125v-9.25m12 6.625v-1.875a3.375 3.375 0 0 0-3.375-3.375h-1.5a1.125 1.125 0 0 1-1.125-1.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H9.75"
                              />
                            </svg>
                          </button>
                          <!-- Edit -->
                          <.link
                            patch={edit_path.(transponder.id)}
                            title="Edit"
                            aria-label="Edit transponder"
                            class="inline-flex items-center justify-center rounded-md border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 p-1.5 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-50 dark:hover:bg-slate-700"
                          >
                            <svg
                              xmlns="http://www.w3.org/2000/svg"
                              fill="none"
                              viewBox="0 0 24 24"
                              stroke-width="1.5"
                              stroke="currentColor"
                              class="h-5 w-5"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10"
                              />
                            </svg>
                          </.link>
                          
    <!-- Delete -->
                          <button
                            type="button"
                            phx-click="delete_transponder"
                            phx-value-id={transponder.id}
                            data-confirm="Are you sure you want to delete this transponder?"
                            title="Delete"
                            aria-label="Delete transponder"
                            class="inline-flex items-center justify-center rounded-md border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 p-1.5 text-xs text-red-600 dark:text-red-400 hover:bg-gray-50 dark:hover:bg-slate-700"
                          >
                            <svg
                              xmlns="http://www.w3.org/2000/svg"
                              fill="none"
                              viewBox="0 0 24 24"
                              stroke-width="1.5"
                              stroke="currentColor"
                              class="h-5 w-5"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"
                              />
                            </svg>
                          </button>
                        </div>
                        
    <!-- Toggle -->
                        <button
                          type="button"
                          phx-click="toggle_transponder"
                          phx-value-id={transponder.id}
                          class={[
                            "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-teal-600 focus:ring-offset-2 dark:focus:ring-offset-slate-800",
                            if(transponder.enabled,
                              do: "bg-teal-600",
                              else: "bg-gray-200 dark:bg-slate-600"
                            )
                          ]}
                        >
                          <span class="sr-only">Toggle transponder</span>
                          <span class={[
                            "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                            if(transponder.enabled, do: "translate-x-5", else: "translate-x-0")
                          ]} />
                        </button>
                        
    <!-- Reorder (Drag Handle) -->
                        <div
                          class="drag-handle cursor-move text-gray-400 dark:text-slate-500 hover:text-gray-600 dark:hover:text-slate-300"
                          phx-click="noop"
                        >
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            fill="none"
                            viewBox="0 0 24 24"
                            stroke-width="1.5"
                            stroke="currentColor"
                            class="h-5 w-5"
                          >
                            <path stroke-linecap="round" stroke-linejoin="round" d="M3 8h18M3 16h18" />
                          </svg>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Modals -->
      <.app_modal
        :if={@ui_action in [:new, :edit]}
        id="transponder-modal"
        show
        on_cancel={JS.patch(cancel_path)}
      >
        <:title>{if @ui_action == :new, do: "New Transponder", else: "Edit Transponder"}</:title>
        <:body>
          <.live_component
            module={TrifleApp.TranspondersLive.FormComponent}
            id={@transponder.id || :new}
            title={if @ui_action == :new, do: "New Transponder", else: "Edit Transponder"}
            action={@ui_action}
            transponder={@transponder}
            source={@source}
            source_type={@source_type}
            patch={cancel_path}
          />
        </:body>
      </.app_modal>

      <.app_modal
        :if={@ui_action == :show}
        id="transponder-details-modal"
        show
        on_cancel={JS.patch(cancel_path)}
      >
        <:title>Transponder Details</:title>
        <:body>
          <.live_component
            module={TrifleApp.TranspondersLive.DetailsComponent}
            id={@transponder.id}
            transponder={@transponder}
            source={@source}
            patch={cancel_path}
          />
        </:body>
      </.app_modal>
    </div>
    """
  end
end
