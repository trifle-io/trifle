defmodule TrifleApp.DatabaseTranspondersLive do
  use TrifleApp, :live_view
  alias Trifle.Organizations
  alias Trifle.Organizations.{Database, Transponder}

  def mount(_params, _session, %{assigns: %{current_membership: nil}} = socket) do
    {:ok, redirect(socket, to: ~p"/organization")}
  end

  def mount(
        %{"id" => database_id},
        _session,
        %{assigns: %{current_membership: membership}} = socket
      ) do
    database = Organizations.get_database_for_org!(membership.organization_id, database_id)

    {:ok,
     socket
     |> assign(:database, database)
     |> assign(:page_title, "Database · #{database.display_name} · Transponders")
     |> assign(:breadcrumb_links, [
       {"Database", ~p"/dbs"},
       {database.display_name, ~p"/dashboards"},
       "Transponders"
     ])
     |> stream(:transponders, Organizations.list_transponders_for_database(database))}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:transponder, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:transponder, %Transponder{})
  end

  defp apply_action(socket, :show, %{"transponder_id" => transponder_id}) do
    membership = socket.assigns.current_membership

    socket
    |> assign(
      :transponder,
      Organizations.get_transponder_for_org!(membership.organization_id, transponder_id)
    )
  end

  defp apply_action(socket, :edit, %{"transponder_id" => transponder_id}) do
    membership = socket.assigns.current_membership

    socket
    |> assign(
      :transponder,
      Organizations.get_transponder_for_org!(membership.organization_id, transponder_id)
    )
  end

  def handle_info(
        {TrifleApp.DatabaseTranspondersLive.FormComponent, {:saved, transponder}},
        socket
      ) do
    {:noreply, stream_insert(socket, :transponders, transponder)}
  end

  def handle_info(
        {TrifleApp.DatabaseTranspondersLive.FormComponent, {:updated, transponder}},
        socket
      ) do
    {:noreply, stream_insert(socket, :transponders, transponder)}
  end

  def handle_event("delete_transponder", %{"id" => id}, socket) do
    membership = socket.assigns.current_membership
    transponder = Organizations.get_transponder_for_org!(membership.organization_id, id)
    {:ok, _} = Organizations.delete_transponder(transponder)

    # Reprioritize remaining transponders to close gaps
    remaining_transponders = Organizations.list_transponders_for_database(socket.assigns.database)
    remaining_ids = Enum.map(remaining_transponders, & &1.id)
    {:ok, _} = Organizations.update_transponder_order(socket.assigns.database, remaining_ids)

    # Reload the list with new priorities
    transponders = Organizations.list_transponders_for_database(socket.assigns.database)

    {:noreply,
     socket
     |> stream(:transponders, transponders, reset: true)
     |> put_flash(:info, "Transponder deleted successfully")}
  end

  def handle_event("toggle_transponder", %{"id" => id}, socket) do
    membership = socket.assigns.current_membership
    transponder = Organizations.get_transponder_for_org!(membership.organization_id, id)

    {:ok, updated_transponder} =
      Organizations.update_transponder(transponder, %{enabled: !transponder.enabled})

    {:noreply, stream_insert(socket, :transponders, updated_transponder)}
  end

  def handle_event("duplicate_transponder", %{"id" => id}, socket) do
    membership = socket.assigns.current_membership
    original = Organizations.get_transponder_for_org!(membership.organization_id, id)
    database = socket.assigns.database
    next_order = Organizations.get_next_transponder_order(database)

    attrs = %{
      "database_id" => database.id,
      "name" => (original.name || original.key) <> " (copy)",
      "key" => original.key,
      "type" => original.type,
      "config" => original.config || %{},
      "enabled" => false,
      "order" => next_order
    }

    case Organizations.create_transponder(attrs) do
      {:ok, transponder} ->
        {:noreply,
         socket
         |> stream_insert(:transponders, transponder)
         |> put_flash(:info, "Transponder duplicated")}

      {:error, _cs} ->
        {:noreply, put_flash(socket, :error, "Could not duplicate transponder")}
    end
  end

  def handle_event("reorder_transponders", %{"ids" => ids}, socket) do
    case Organizations.update_transponder_order(socket.assigns.database, ids) do
      {:ok, _} ->
        # Reload the transponders to reflect the new order
        transponders = Organizations.list_transponders_for_database(socket.assigns.database)

        {:noreply,
         socket
         |> stream(:transponders, transponders, reset: true)
         |> put_flash(:info, "Transponder order updated successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update transponder order")}
    end
  end

  # Row click navigations and helpers
  def handle_event("transponder_clicked", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/dbs/#{socket.assigns.database.id}/transponders/#{id}")}
  end

  # No-op click to prevent row click bubbling
  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col dark:bg-slate-900 min-h-screen">
      <!-- Tab Navigation -->
      <div class="mb-6 border-b border-gray-200 dark:border-slate-700">
        <nav class="-mb-px space-x-8" aria-label="Tabs">
          <.link
            navigate={~p"/dashboards"}
            class="border-transparent text-gray-500 dark:text-slate-400 hover:border-gray-300 dark:hover:border-slate-500 hover:text-gray-700 dark:hover:text-slate-300 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium"
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
                d="M3.75 3v11.25A2.25 2.25 0 0 0 6 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0 1 18 16.5h-2.25m-7.5 0h7.5m-7.5 0-1 3m8.5-3 1 3m0 0 .5 1.5m-.5-1.5h-9.5m0 0-.5 1.5M9 11.25v1.5M12 9v3.75m3-6v6"
              />
            </svg>
            <span class="hidden sm:block">Dashboards</span>
          </.link>
          <.link
            navigate={~p"/dbs/#{@database.id}/transponders"}
            class="border-teal-500 text-teal-600 dark:text-teal-400 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium"
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
          <.link
            navigate={~p"/explore?#{[database_id: @database.id]}"}
            class="border-transparent text-gray-500 dark:text-slate-400 hover:border-gray-300 dark:hover:border-slate-500 hover:text-gray-700 dark:hover:text-slate-300 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium"
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
                d="M3.375 19.5h17.25m-17.25 0a1.125 1.125 0 01-1.125-1.125M3.375 19.5h7.5c.621 0 1.125-.504 1.125-1.125m-9.75 0V5.625m0 12.75v-1.5c0-.621.504-1.125 1.125-1.125m18.375 2.625V5.625m0 12.75c0 .621-.504 1.125-1.125 1.125m1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125m0 3.75h-7.5A1.125 1.125 0 0112 18.375m9.75-12.75c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125m19.5 0v1.5c0 .621.504 1.125 1.125 1.125M2.25 5.625v1.5c0 .621.504 1.125 1.125 1.125m0 0h17.25m-17.25 0h7.5c.621 0 1.125.504 1.125 1.125M3.375 8.25c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125m17.25-3.75h-7.5c-.621 0-1.125.504-1.125 1.125m8.625-1.125c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125m-17.25 0h7.5m-7.5 0c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125M12 10.875v-1.5m0 1.5c0 .621-.504 1.125-1.125 1.125M12 10.875c0 .621.504 1.125 1.125 1.125m-2.25 0c.621 0 1.125.504 1.125 1.125M13.125 12h7.5m-7.5 0c-.621 0-1.125.504-1.125 1.125M20.625 12c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125m-17.25 0h7.5M12 14.625v-1.5m0 1.5c0 .621-.504 1.125-1.125 1.125M12 14.625c0 .621.504 1.125 1.125 1.125m-2.25 0c.621 0 1.125.504 1.125 1.125m0 1.5v-1.5m0 0c0-.621.504-1.125 1.125-1.125m0 0h7.5"
              />
            </svg>
            <span class="hidden sm:block">Explore</span>
          </.link>
          <.link
            navigate={~p"/dbs/#{@database.id}/settings"}
            class="float-right border-transparent text-gray-500 dark:text-slate-400 hover:border-gray-300 dark:hover:border-slate-500 hover:text-gray-700 dark:hover:text-slate-300 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium"
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
        </nav>
      </div>
      
    <!-- Transponders Index -->
      <div class="mb-6">
        <div class="bg-white dark:bg-slate-800 rounded-lg shadow">
          <div class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 dark:text-white sm:pl-3 border-b border-gray-100 dark:border-slate-700 flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span>Transponders</span>
              <span class="inline-flex items-center rounded-md bg-teal-50 dark:bg-teal-900 px-2 py-1 text-xs font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30">
                {Enum.count(@streams.transponders)}
              </span>
            </div>
            <.link
              patch={~p"/dbs/#{@database.id}/transponders/new"}
              class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
            >
              <svg class="h-5 w-5 md:-ml-0.5 md:mr-1.5" viewBox="0 0 20 20" fill="currentColor">
                <path d="M10.75 4.75a.75.75 0 00-1.5 0v4.5h-4.5a.75.75 0 000 1.5h4.5v4.5a.75.75 0 001.5 0v-4.5h4.5a.75.75 0 000-1.5h-4.5v-4.5z" />
              </svg>
              <span class="hidden md:inline">New Transponder</span>
            </.link>
          </div>

          <div class="divide-y divide-gray-100 dark:divide-slate-700">
            <%= if @streams.transponders.inserts == [] do %>
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
            <% else %>
              <div
                id="transponders"
                phx-update="stream"
                phx-hook="Sortable"
                data-group="transponders"
                data-handle=".drag-handle"
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
                              patch={~p"/dbs/#{@database.id}/transponders/#{transponder.id}"}
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
                            patch={~p"/dbs/#{@database.id}/transponders/#{transponder.id}/edit"}
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
            <% end %>
          </div>
        </div>
      </div>
      
    <!-- Modals -->
      <.app_modal
        :if={@live_action in [:new, :edit]}
        id="transponder-modal"
        show
        on_cancel={JS.patch(~p"/dbs/#{@database.id}/transponders")}
      >
        <:title>{if @live_action == :new, do: "New Transponder", else: "Edit Transponder"}</:title>
        <:body>
          <.live_component
            module={TrifleApp.DatabaseTranspondersLive.FormComponent}
            id={@transponder.id || :new}
            title={if @live_action == :new, do: "New Transponder", else: "Edit Transponder"}
            action={@live_action}
            transponder={@transponder}
            database={@database}
            patch={~p"/dbs/#{@database.id}/transponders"}
          />
        </:body>
      </.app_modal>

      <.app_modal
        :if={@live_action == :show}
        id="transponder-details-modal"
        show
        on_cancel={JS.patch(~p"/dbs/#{@database.id}/transponders")}
      >
        <:title>Transponder Details</:title>
        <:body>
          <.live_component
            module={TrifleApp.DatabaseTranspondersLive.DetailsComponent}
            id={@transponder.id}
            transponder={@transponder}
            database={@database}
            patch={~p"/dbs/#{@database.id}/transponders"}
          />
        </:body>
      </.app_modal>
    </div>
    """
  end
end
