defmodule TrifleApp.DatabaseDashboardsLive do
  use TrifleApp, :live_view
  alias Trifle.Organizations
  alias Trifle.Organizations.{Database, Dashboard}

  def mount(%{"id" => database_id}, _session, socket) do
    database = Organizations.get_database!(database_id)

    {:ok,
     socket
     |> assign(:database, database)
     |> assign(:page_title, ["Database", database.display_name, "Dashboards"])
     |> assign(:breadcrumb_links, [
       {"Database", ~p"/app/dbs"},
       {database.display_name, ~p"/app/dbs/#{database_id}"},
       "Dashboards"
     ])
     |> stream(:dashboards, Organizations.list_dashboards_for_database(database))}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:dashboard, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:dashboard, %Dashboard{})
  end

  def handle_info({TrifleApp.DatabaseDashboardsLive.FormComponent, {:saved, dashboard}}, socket) do
    {:noreply, stream_insert(socket, :dashboards, dashboard)}
  end

  def handle_event("delete_dashboard", %{"id" => id}, socket) do
    dashboard = Organizations.get_dashboard!(id)
    {:ok, _} = Organizations.delete_dashboard(dashboard)

    # Reload the list to ensure consistency
    dashboards = Organizations.list_dashboards_for_database(socket.assigns.database)

    {:noreply,
     socket
     |> stream(:dashboards, dashboards, reset: true)
     |> put_flash(:info, "Dashboard deleted successfully")}
  end

  def handle_event("dashboard_clicked", %{"id" => dashboard_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/app/dbs/#{socket.assigns.database.id}/dashboards/#{dashboard_id}")}
  end

  defp gravatar_url(email) do
    hash = email
      |> String.trim()
      |> String.downcase()
      |> :erlang.md5()
      |> Base.encode16(case: :lower)

    "https://www.gravatar.com/avatar/#{hash}?s=150&d=identicon"
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col dark:bg-slate-900 min-h-screen">
      <!-- Tab Navigation -->
      <div class="mb-6 border-b border-gray-200 dark:border-slate-700">
        <nav class="-mb-px space-x-8" aria-label="Tabs">
          <.link
            navigate={~p"/app/dbs/#{@database.id}"}
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
            navigate={~p"/app/dbs/#{@database.id}/transponders"}
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
                d="M21 7.5l-2.25-1.313M21 7.5v2.25m0-2.25l-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3l2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75l2.25-1.313M12 21.75V19.5m0 2.25l-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25"
              />
            </svg>
            <span class="hidden sm:block">Transponders</span>
          </.link>
          <.link
            navigate={~p"/app/dbs/#{@database.id}/dashboards"}
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
                d="M3.75 3v11.25A2.25 2.25 0 0 0 6 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0 1 18 16.5h-2.25m-7.5 0h7.5m-7.5 0-1 3m8.5-3 1 3m0 0 .5 1.5m-.5-1.5h-9.5m0 0-.5 1.5M9 11.25v1.5M12 9v3.75m3-6v6"
              />
            </svg>
            <span class="hidden sm:block">Dashboards</span>
          </.link>
          <.link
            navigate={~p"/app/dbs/#{@database.id}/settings"}
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

      <!-- Dashboards Index -->
      <div class="mb-6">
        <div class="bg-white dark:bg-slate-800 rounded-lg shadow">
          <div class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 dark:text-white sm:pl-3 border-b border-gray-100 dark:border-slate-700 flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span>Dashboards</span>
              <span class="inline-flex items-center rounded-md bg-teal-50 dark:bg-teal-900 px-2 py-1 text-xs font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30">
                <%= Enum.count(@streams.dashboards) %>
              </span>
            </div>
            <.link
              patch={~p"/app/dbs/#{@database.id}/dashboards/new"}
              class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
            >
              <svg class="-ml-0.5 mr-1.5 h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                <path d="M10.75 4.75a.75.75 0 00-1.5 0v4.5h-4.5a.75.75 0 000 1.5h4.5v4.5a.75.75 0 001.5 0v-4.5h4.5a.75.75 0 000-1.5h-4.5v-4.5z" />
              </svg>
              New Dashboard
            </.link>
          </div>

          <div class="divide-y divide-gray-100 dark:divide-slate-700">
            <%= if @streams.dashboards.inserts == [] do %>
              <div class="py-12 text-center">
                <svg
                  class="mx-auto h-12 w-12 text-gray-400"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  aria-hidden="true"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M3.75 3v11.25A2.25 2.25 0 0 0 6 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0 1 18 16.5h-2.25m-7.5 0h7.5m-7.5 0-1 3m8.5-3 1 3m0 0 .5 1.5m-.5-1.5h-9.5m0 0-.5 1.5M9 11.25v1.5M12 9v3.75m3-6v6"
                  />
                </svg>
                <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">No dashboards</h3>
                <p class="mt-1 text-sm text-gray-500 dark:text-slate-400">Get started by creating a new dashboard.</p>
              </div>
            <% else %>
              <div id="dashboards" phx-update="stream">
                <%= for {dom_id, dashboard} <- @streams.dashboards do %>
                  <div 
                    id={dom_id} 
                    class="px-4 py-4 sm:px-6 group border-b border-gray-100 dark:border-slate-700 last:border-b-0 cursor-pointer hover:bg-gray-50 dark:hover:bg-slate-700/50" 
                    phx-click="dashboard_clicked"
                    phx-value-id={dashboard.id}
                  >
                    <div class="flex items-center justify-between">
                      <div class="min-w-0 flex-1">
                        <div class="flex items-center gap-3 mb-1">
                          <!-- User Avatar -->
                          <%= if dashboard.user do %>
                            <div class="h-6 w-6 flex-shrink-0" title={"Created by #{dashboard.user.email}"}>
                              <img src={gravatar_url(dashboard.user.email)} class="h-6 w-6 rounded-full" />
                            </div>
                          <% end %>
                          
                          <span class="text-sm font-medium text-gray-900 dark:text-white hover:text-teal-600 dark:hover:text-teal-400">
                            <%= dashboard.name %>
                          </span>
                        </div>
                        <p class="text-xs text-gray-500 dark:text-slate-400">
                          Key: <code class="bg-gray-100 dark:bg-slate-700 px-1 py-0.5 rounded font-mono"><%= dashboard.key %></code>
                        </p>
                      </div>

                      <!-- Status Icons -->
                      <div id="dashboard-status-icons" class="flex items-center gap-2" phx-hook="FastTooltip">
                        <!-- Visibility Icon -->
                        <div 
                          class={[
                            if(dashboard.visibility, 
                              do: "text-teal-600 dark:text-teal-400",
                              else: "text-teal-600 dark:text-teal-400"
                            )
                          ]}
                          data-tooltip={if(dashboard.visibility, do: "Visible to everyone in organization", else: "Private - only creator can see this")}>
                          <%= if dashboard.visibility do %>
                            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5">
                              <path stroke-linecap="round" stroke-linejoin="round" d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z" />
                            </svg>
                          <% else %>
                            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5">
                              <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z" />
                            </svg>
                          <% end %>
                        </div>
                        
                        <!-- Public Link Icon -->
                        <div 
                          class={[
                            if(dashboard.access_token, 
                              do: "text-teal-600 dark:text-teal-400",
                              else: "text-gray-400 dark:text-gray-500"
                            )
                          ]}
                          data-tooltip={if(dashboard.access_token, do: "Has public link", else: "No public link")}>
                          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M8.288 15.038a5.25 5.25 0 0 1 7.424 0M5.106 11.856c3.807-3.808 9.98-3.808 13.788 0M1.924 8.674c5.565-5.565 14.587-5.565 20.152 0M12.53 18.22l-.53.53-.53-.53a.75.75 0 0 1 1.06 0Z" />
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
      <.app_modal :if={@live_action == :new} id="dashboard-modal" show on_cancel={JS.patch(~p"/app/dbs/#{@database.id}/dashboards")}>
        <:title>New Dashboard</:title>
        <:body>
          <.live_component
            module={TrifleApp.DatabaseDashboardsLive.FormComponent}
            id={@dashboard.id || :new}
            action={@live_action}
            dashboard={@dashboard}
            database={@database}
            current_user={@current_user}
            patch={~p"/app/dbs/#{@database.id}/dashboards"}
          />
        </:body>
      </.app_modal>
    </div>
    """
  end
end