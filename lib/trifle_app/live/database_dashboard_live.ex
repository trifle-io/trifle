defmodule TrifleApp.DatabaseDashboardLive do
  use TrifleApp, :live_view
  alias Trifle.Organizations

  def mount(params, _session, socket) do
    case params do
      %{"id" => database_id, "dashboard_id" => dashboard_id} ->
        # Authenticated access
        database = Organizations.get_database!(database_id)
        dashboard = Organizations.get_dashboard!(dashboard_id)

        {:ok,
         socket
         |> assign(:database, database)
         |> assign(:dashboard, dashboard)
         |> assign(:is_public_access, false)
         |> assign(:public_token, nil)
         |> assign(:page_title, ["Database", database.display_name, "Dashboards", dashboard.name])
         |> assign(:breadcrumb_links, [
           {"Database", ~p"/app/dbs"},
           {database.display_name, ~p"/app/dbs/#{database_id}"},
           {"Dashboards", ~p"/app/dbs/#{database_id}/dashboards"},
           dashboard.name
         ])}

      %{"dashboard_id" => dashboard_id} ->
        # Public access - token will be provided in handle_params
        {:ok,
         socket
         |> assign(:is_public_access, true)
         |> assign(:public_token, nil)
         |> assign(:dashboard_id, dashboard_id)}
    end
  end

  def handle_params(params, _url, socket) do
    if socket.assigns.is_public_access do
      # Handle public access with token verification
      token = params["token"]
      dashboard_id = socket.assigns.dashboard_id
      
      case Organizations.get_dashboard_by_token(dashboard_id, token) do
        {:ok, dashboard} ->
          {:noreply,
           socket
           |> assign(:database, dashboard.database)
           |> assign(:dashboard, dashboard)
           |> assign(:public_token, token)
           |> assign(:page_title, ["Dashboard", dashboard.name])
           |> assign(:breadcrumb_links, [])
           |> then(fn s -> apply_action(s, socket.assigns.live_action, params) end)}
        
        {:error, :not_found} ->
          {:noreply,
           socket
           |> put_flash(:error, "Dashboard not found or invalid token")
           |> redirect(to: "/")}
      end
    else
      {:noreply, apply_action(socket, socket.assigns.live_action, params)}
    end
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(:dashboard_changeset, nil)
    |> assign(:dashboard_form, nil)
  end

  defp apply_action(socket, :edit, _params) do
    changeset = Organizations.change_dashboard(socket.assigns.dashboard)
    socket
    |> assign(:dashboard_changeset, changeset)
    |> assign(:dashboard_form, to_form(changeset))
  end

  defp apply_action(socket, :public, _params) do
    socket
    |> assign(:dashboard_changeset, nil)
    |> assign(:dashboard_form, nil)
  end
  
  defp apply_action(socket, :configure, _params) do
    socket
    |> assign(:dashboard_changeset, nil)
    |> assign(:dashboard_form, nil)
    |> assign(:temp_name, socket.assigns.dashboard.name)
  end


  def handle_event("update_temp_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, :temp_name, name)}
  end

  def handle_event("save_name", %{"name" => name}, socket) do
    dashboard = socket.assigns.dashboard
    
    case Organizations.update_dashboard(dashboard, %{name: name}) do
      {:ok, updated_dashboard} ->
        # Update breadcrumbs and page title with new dashboard name
        updated_breadcrumbs = case socket.assigns[:breadcrumb_links] do
          [db_link, db_name, dashboards_link, _old_dashboard_name] ->
            [db_link, db_name, dashboards_link, updated_dashboard.name]
          other -> other
        end
        
        updated_page_title = case socket.assigns[:page_title] do
          ["Database", db_name, "Dashboards", _old_dashboard_name] ->
            ["Database", db_name, "Dashboards", updated_dashboard.name]
          other -> other
        end
        
        {:noreply,
         socket
         |> assign(:dashboard, updated_dashboard)
         |> assign(:temp_name, updated_dashboard.name)
         |> assign(:breadcrumb_links, updated_breadcrumbs)
         |> assign(:page_title, updated_page_title)
         |> put_flash(:info, "Dashboard name updated successfully")}
      
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update dashboard name")}
    end
  end

  def handle_event("toggle_visibility", _params, socket) do
    dashboard = socket.assigns.dashboard
    
    case Organizations.update_dashboard(dashboard, %{visibility: !dashboard.visibility}) do
      {:ok, updated_dashboard} ->
        {:noreply,
         socket
         |> assign(:dashboard, updated_dashboard)
         |> put_flash(:info, "Dashboard visibility updated successfully")}
      
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update dashboard visibility")}
    end
  end

  def handle_event("generate_public_token", _params, socket) do
    dashboard = socket.assigns.dashboard
    
    case Organizations.generate_dashboard_public_token(dashboard) do
      {:ok, updated_dashboard} ->
        {:noreply,
         socket
         |> assign(:dashboard, updated_dashboard)
         |> put_flash(:info, "Public link generated successfully")}
      
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to generate public link")}
    end
  end


  def handle_event("remove_public_token", _params, socket) do
    dashboard = socket.assigns.dashboard
    
    case Organizations.remove_dashboard_public_token(dashboard) do
      {:ok, updated_dashboard} ->
        {:noreply,
         socket
         |> assign(:dashboard, updated_dashboard)
         |> put_flash(:info, "Public link removed successfully")}
      
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to remove public link")}
    end
  end

  def handle_event("delete_dashboard", _params, socket) do
    dashboard = socket.assigns.dashboard
    
    case Organizations.delete_dashboard(dashboard) do
      {:ok, _} ->
        {:noreply,
         socket
         |> push_navigate(to: ~p"/app/dbs/#{socket.assigns.database.id}/dashboards")
         |> put_flash(:info, "Dashboard deleted successfully")}
      
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete dashboard")}
    end
  end

  def handle_event("save_dashboard", %{"dashboard" => dashboard_params}, socket) do
    # Parse JSON payload if provided
    dashboard_params = 
      case dashboard_params["payload"] do
        payload when is_binary(payload) and payload != "" ->
          case Jason.decode(payload) do
            {:ok, parsed_payload} ->
              Map.put(dashboard_params, "payload", parsed_payload)
            {:error, _} ->
              # Keep the string value, let the changeset validation handle the error
              dashboard_params
          end
        _ ->
          Map.put(dashboard_params, "payload", %{})
      end
    
    case Organizations.update_dashboard(socket.assigns.dashboard, dashboard_params) do
      {:ok, dashboard} ->
        {:noreply,
         socket
         |> assign(:dashboard, dashboard)
         |> assign(:dashboard_changeset, nil)
         |> assign(:dashboard_form, nil)
         |> push_patch(to: ~p"/app/dbs/#{socket.assigns.database.id}/dashboards/#{dashboard.id}")
         |> put_flash(:info, "Dashboard updated successfully")}
      
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, 
         socket
         |> assign(:dashboard_changeset, changeset)
         |> assign(:dashboard_form, to_form(changeset))}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:dashboard_changeset, nil)
     |> assign(:dashboard_form, nil)
     |> push_patch(to: ~p"/app/dbs/#{socket.assigns.database.id}/dashboards/#{socket.assigns.dashboard.id}")}
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
      <!-- Header -->
      <div class="mb-6">
        <div class="flex items-center">
          <%= if @is_public_access do %>
            <div class="flex items-center gap-2 w-64">
              <svg class="h-5 w-5 text-gray-400 dark:text-slate-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 3v11.25A2.25 2.25 0 0 0 6 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0 1 18 16.5h-2.25m-7.5 0h7.5m-7.5 0-1 3m8.5-3 1 3m0 0 .5 1.5m-.5-1.5h-9.5m0 0-.5 1.5M9 11.25v1.5M12 9v3.75m3-6v6" />
              </svg>
              <span class="text-sm font-medium text-gray-500 dark:text-slate-400">Public Dashboard</span>
            </div>
          <% else %>
            <div class="flex items-center gap-4 w-64">
              <.link
                navigate={~p"/app/dbs/#{@database.id}/dashboards"}
                class="inline-flex items-center text-sm font-medium text-gray-500 hover:text-gray-700 dark:text-slate-400 dark:hover:text-slate-300"
              >
                <svg class="-ml-1 mr-1 h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M12.79 5.23a.75.75 0 01-.02 1.06L8.832 10l3.938 3.71a.75.75 0 11-1.04 1.08l-4.5-4.25a.75.75 0 010-1.08l4.5-4.25a.75.75 0 011.06.02z" clip-rule="evenodd" />
                </svg>
                Back to Dashboards
              </.link>
            </div>
          <% end %>
          
          <!-- Dashboard Title -->
          <div class="flex-1 text-center">
            <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
              <%= @dashboard.name %>
            </h1>
          </div>
          
          <%= if !@is_public_access && @current_user && @dashboard.user_id == @current_user.id do %>
            <!-- Dashboard owner controls -->
            <div class="flex items-center gap-4 w-64 justify-end">
              <!-- Edit Button -->
              <%= if @live_action == :edit do %>
                <button
                  type="button"
                  phx-click="cancel_edit"
                  class="inline-flex items-center rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                >
                  <svg class="-ml-0.5 mr-1.5 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                  Cancel
                </button>
              <% else %>
                <.link
                  patch={~p"/app/dbs/#{@database.id}/dashboards/#{@dashboard.id}/edit"}
                  class="inline-flex items-center rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                >
                  <svg class="-ml-0.5 mr-1.5 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10" />
                  </svg>
                  Edit
                </.link>
                
                <!-- Configure Button -->
                <.link
                  patch={~p"/app/dbs/#{@database.id}/dashboards/#{@dashboard.id}/configure"}
                  class="inline-flex items-center rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                >
                  <svg class="-ml-0.5 mr-1.5 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z" />
                    <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                  </svg>
                  Configure
                </.link>
              <% end %>
              
              <!-- Status Icon Badges -->
              <div id="status-badges" class="flex items-center gap-2" phx-hook="FastTooltip">
                <!-- Visibility Badge -->
                <div 
                  class={[
                    "inline-flex items-center rounded-md px-3 py-2 text-xs font-medium",
                    if(@dashboard.visibility, 
                      do: "bg-teal-50 dark:bg-teal-900 text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30",
                      else: "bg-teal-50 dark:bg-teal-900 text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30"
                    )
                  ]}
                  data-tooltip={if(@dashboard.visibility, do: "Visible to everyone in organization", else: "Private - only you can see this")}>
                  <%= if @dashboard.visibility do %>
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z" />
                    </svg>
                  <% else %>
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z" />
                    </svg>
                  <% end %>
                </div>
                
                <!-- Public Link Badge -->
                <%= if @dashboard.access_token do %>
                  <!-- Hidden element with the URL to copy -->
                  <span id="dashboard-public-url" class="hidden"><%= url(@socket, ~p"/d/#{@dashboard.id}?token=#{@dashboard.access_token}") %></span>
                  
                  <!-- Has token: clickable teal badge with visual feedback -->
                  <button 
                    type="button"
                    phx-click={
                      JS.dispatch("phx:copy", to: "#dashboard-public-url")
                      |> JS.hide(to: "#header-link-icon")
                      |> JS.show(to: "#header-check-icon") 
                      |> JS.hide(to: "#header-check-icon", transition: {"", "", ""}, time: 2000)
                      |> JS.show(to: "#header-link-icon", transition: {"", "", ""}, time: 2000)
                    }
                    class="cursor-pointer inline-flex items-center rounded-md bg-teal-50 dark:bg-teal-900 px-3 py-2 text-xs font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30 hover:bg-teal-100 dark:hover:bg-teal-800"
                    data-tooltip="Click to copy public dashboard link"
                  >
                    <!-- Link Icon (default) -->
                    <svg id="header-link-icon" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M8.288 15.038a5.25 5.25 0 0 1 7.424 0M5.106 11.856c3.807-3.808 9.98-3.808 13.788 0M1.924 8.674c5.565-5.565 14.587-5.565 20.152 0M12.53 18.22l-.53.53-.53-.53a.75.75 0 0 1 1.06 0Z" />
                    </svg>
                    
                    <!-- Check Icon (shown temporarily when copied) -->
                    <svg id="header-check-icon" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5 text-green-600 hidden">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                  </button>
                <% else %>
                  <!-- No token: gray badge -->
                  <div 
                    class="inline-flex items-center rounded-md bg-gray-50 dark:bg-gray-900 px-3 py-2 text-xs font-medium text-gray-500 dark:text-gray-400 ring-1 ring-inset ring-gray-600/20 dark:ring-gray-500/30"
                    data-tooltip="No public link available">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M8.288 15.038a5.25 5.25 0 0 1 7.424 0M5.106 11.856c3.807-3.808 9.98-3.808 13.788 0M1.924 8.674c5.565-5.565 14.587-5.565 20.152 0M12.53 18.22l-.53.53-.53-.53a.75.75 0 0 1 1.06 0Z" />
                    </svg>
                  </div>
                <% end %>
              </div>
            </div>
          <% else %>
            <!-- Non-owner or public access view -->
            <%= if !@is_public_access do %>
              <div class="flex items-center gap-2 w-64 justify-end">
                <span class={[
                  "inline-flex items-center rounded-md px-2 py-1 text-xs font-medium",
                  if(@dashboard.visibility, 
                    do: "bg-blue-50 dark:bg-blue-900 text-blue-700 dark:text-blue-200 ring-1 ring-inset ring-blue-600/20 dark:ring-blue-500/30",
                    else: "bg-gray-50 dark:bg-gray-900 text-gray-700 dark:text-gray-200 ring-1 ring-inset ring-gray-600/20 dark:ring-gray-500/30"
                  )
                ]}>
                  <%= Trifle.Organizations.Dashboard.visibility_display(@dashboard.visibility) %>
                </span>
              </div>
            <% else %>
              <div class="w-64"></div>
            <% end %>
          <% end %>
        </div>
      </div>

      <!-- Edit Form (only shown in edit mode for authenticated users) -->
      <%= if !@is_public_access && @live_action == :edit && @dashboard_form do %>
        <div class="mb-6">
          <div class="bg-white dark:bg-slate-800 rounded-lg shadow p-6">
            <h2 class="text-lg font-medium text-gray-900 dark:text-white mb-4">Edit Dashboard</h2>
            
            <.form 
              for={@dashboard_form} 
              phx-submit="save_dashboard"
              class="space-y-4"
            >
              <div>
                <label for="dashboard_key" class="block text-sm font-medium text-gray-700 dark:text-slate-300">Key</label>
                <textarea 
                  name="dashboard[key]" 
                  id="dashboard_key"
                  rows="3"
                  class="mt-1 block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                  placeholder="e.g., sales.metrics"
                  required
                ><%= Phoenix.HTML.Form.input_value(@dashboard_form, :key) %></textarea>
                <%= if @dashboard_changeset.errors[:key] do %>
                  <p class="mt-1 text-sm text-red-600 dark:text-red-400"><%= elem(hd(@dashboard_changeset.errors[:key]), 0) %></p>
                <% end %>
              </div>
              
              <div>
                <label for="dashboard_payload" class="block text-sm font-medium text-gray-700 dark:text-slate-300">Payload</label>
                <textarea 
                  name="dashboard[payload]" 
                  id="dashboard_payload"
                  rows="10"
                  class="mt-1 block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm font-mono"
                  placeholder="JSON configuration for dashboard visualization"
                ><%= if @dashboard.payload, do: Jason.encode!(@dashboard.payload, pretty: true), else: "" %></textarea>
                <%= if @dashboard_changeset.errors[:payload] do %>
                  <p class="mt-1 text-sm text-red-600 dark:text-red-400"><%= elem(hd(@dashboard_changeset.errors[:payload]), 0) %></p>
                <% end %>
                <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">Enter valid JSON configuration for the dashboard visualization</p>
              </div>
              
              <div class="flex items-center justify-end gap-3 pt-4">
                <button 
                  type="button" 
                  phx-click="cancel_edit"
                  class="inline-flex items-center rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                >
                  Cancel
                </button>
                <button 
                  type="submit"
                  class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600"
                >
                  Save Changes
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>

      <!-- Configure Modal -->
      <%= if !@is_public_access && @live_action == :configure do %>
        <.app_modal id="configure-modal" show={true} on_cancel={JS.patch(~p"/app/dbs/#{@database.id}/dashboards/#{@dashboard.id}")}>
          <:title>Configure Dashboard</:title>
          <:body>
            <div class="space-y-6">
              <!-- Dashboard Name -->
              <div>
                <label for="configure_name" class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">Dashboard Name</label>
                <div class="flex gap-2">
                  <input 
                    type="text" 
                    id="configure_name"
                    name="name"
                    value={@temp_name || @dashboard.name}
                    phx-keyup="update_temp_name"
                    class="flex-1 block rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm" 
                    placeholder="Dashboard name"
                  />
                  <button
                    type="button"
                    phx-click="save_name"
                    phx-value-name={@temp_name || @dashboard.name}
                    class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600"
                  >
                    Save
                  </button>
                </div>
              </div>
              
              <!-- Visibility Toggle -->
              <div class="flex items-center justify-between">
                <div>
                  <span class="text-sm font-medium text-gray-700 dark:text-slate-300">Visibility</span>
                  <p class="text-xs text-gray-500 dark:text-slate-400">Make this dashboard visible to everyone in the organization</p>
                </div>
                <button 
                  type="button"
                  phx-click="toggle_visibility"
                  class={[
                    "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-teal-600 focus:ring-offset-2",
                    if(@dashboard.visibility, do: "bg-teal-600", else: "bg-gray-200 dark:bg-gray-700")
                  ]}
                >
                  <span class={[
                    "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                    if(@dashboard.visibility, do: "translate-x-5", else: "translate-x-0")
                  ]}></span>
                </button>
              </div>
              
              <!-- Public Link Management -->
              <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
                <div class="flex items-center justify-between mb-4">
                  <div>
                    <span class="text-sm font-medium text-gray-700 dark:text-slate-300">Public Link</span>
                    <p class="text-xs text-gray-500 dark:text-slate-400">Allow unauthenticated Read-only access to this dashboard</p>
                  </div>
                </div>
                
                <%= if @dashboard.access_token do %>
                  <!-- Hidden element with the URL to copy -->
                  <span id="modal-dashboard-public-url" class="hidden"><%= url(@socket, ~p"/d/#{@dashboard.id}?token=#{@dashboard.access_token}") %></span>
                  
                  <div class="flex items-center gap-3">
                    <!-- Copy Link Button -->
                    <span 
                      id="modal-copy-dashboard-link"
                      x-data="{ copied: false }"
                      phx-click={JS.dispatch("phx:copy", to: "#modal-dashboard-public-url")}
                      x-on:click="copied = true; setTimeout(() => copied = false, 3000)"
                      class="flex-1 cursor-pointer inline-flex items-center justify-center rounded-md bg-teal-50 dark:bg-teal-900 px-3 py-2 text-sm font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30 hover:bg-teal-100 dark:hover:bg-teal-800"
                      title="Copy public link to clipboard"
                      phx-update="ignore"
                    >
                      <!-- Copy Icon (show when not copied) -->
                      <svg x-show="!copied" class="-ml-0.5 mr-2 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M15.666 3.888A2.25 2.25 0 0 0 13.5 2.25h-3c-1.03 0-1.9.693-2.166 1.638m7.332 0c.055.194.084.4.084.612v0a.75.75 0 0 1-.75.75H9a.75.75 0 0 1-.75-.75v0c0-.212.03-.418.084-.612m7.332 0c.646.049 1.288.11 1.927.184 1.1.128 1.907 1.077 1.907 2.185V19.5a2.25 2.25 0 0 1-2.25 2.25H6.75A2.25 2.25 0 0 1 4.5 19.5V6.257c0-1.108.806-2.057 1.907-2.185a48.208 48.208 0 0 1 1.927-.184" />
                      </svg>
                      
                      <!-- Check Icon (show when copied) -->
                      <svg x-show="copied" class="-ml-0.5 mr-2 h-4 w-4 text-green-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                      </svg>
                      
                      <!-- Text -->
                      <span x-show="!copied">Copy Public Link</span>
                      <span x-show="copied" class="text-green-600">Copied!</span>
                    </span>
                    
                    <!-- Remove Button -->
                    <button 
                      type="button"
                      phx-click="remove_public_token"
                      data-confirm="Are you sure you want to remove the public link? Anyone with the current link will lose access."
                      class="inline-flex items-center rounded-md bg-red-50 dark:bg-red-900 px-3 py-2 text-sm font-medium text-red-700 dark:text-red-200 ring-1 ring-inset ring-red-600/20 dark:ring-red-500/30 hover:bg-red-100 dark:hover:bg-red-800"
                      title="Remove public link"
                    >
                      <svg class="-ml-0.5 mr-2 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" />
                      </svg>
                      Remove Link
                    </button>
                  </div>
                <% else %>
                  <!-- No token: show generate -->
                  <button 
                    type="button"
                    phx-click="generate_public_token"
                    class="w-full inline-flex items-center justify-center rounded-md bg-teal-50 dark:bg-teal-900 px-3 py-2 text-sm font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30 hover:bg-teal-100 dark:hover:bg-teal-800"
                    title="Generate public link for unauthenticated access"
                  >
                    <svg class="-ml-0.5 mr-2 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M13.19 8.688a4.5 4.5 0 0 1 1.242 7.244l-4.5 4.5a4.5 4.5 0 0 1-6.364-6.364l1.757-1.757m13.35-.622 1.757-1.757a4.5 4.5 0 0 0-6.364-6.364l-4.5 4.5a4.5 4.5 0 0 0 1.242 7.244" />
                    </svg>
                    Generate Public Link
                  </button>
                <% end %>
              </div>
              
              <!-- Danger Zone -->
              <div class="border-t border-red-200 dark:border-red-800 pt-6">
                <div class="mb-4">
                  <span class="text-sm font-medium text-red-700 dark:text-red-400">Danger Zone</span>
                  <p class="text-xs text-red-600 dark:text-red-400">This action cannot be undone</p>
                </div>
                
                <button 
                  type="button"
                  phx-click="delete_dashboard"
                  data-confirm="Are you sure you want to delete this dashboard? This action cannot be undone."
                  class="w-full inline-flex items-center justify-center rounded-md bg-red-50 dark:bg-red-900 px-3 py-2 text-sm font-medium text-red-700 dark:text-red-200 ring-1 ring-inset ring-red-600/20 dark:ring-red-500/30 hover:bg-red-100 dark:hover:bg-red-800"
                  title="Delete this dashboard"
                >
                  <svg class="-ml-0.5 mr-2 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" />
                  </svg>
                  Delete Dashboard
                </button>
              </div>
            </div>
          </:body>
        </.app_modal>
      <% end %>

      <!-- Dashboard Content -->
      <div class="flex-1">
        <div class="bg-white dark:bg-slate-800 rounded-lg shadow">
          <div class="p-6">
            <%= if @dashboard.payload && map_size(@dashboard.payload) > 0 do %>
              <!-- Dashboard has content - render it -->
              <div class="dashboard-content">
                <div class="text-sm text-gray-500 dark:text-slate-400 mb-4">
                  Dashboard content will be rendered here based on the payload.
                </div>
                
                <!-- Temporary payload display for development -->
                <div class="bg-gray-50 dark:bg-slate-700 rounded-lg p-4">
                  <h3 class="text-sm font-medium text-gray-900 dark:text-white mb-2">Payload (JSON):</h3>
                  <pre class="text-xs text-gray-600 dark:text-slate-300 overflow-x-auto"><%= Jason.encode!(@dashboard.payload, pretty: true) %></pre>
                </div>
              </div>
            <% else %>
              <!-- Empty state -->
              <div class="text-center py-12">
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
                <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">Dashboard is empty</h3>
                <p class="mt-1 text-sm text-gray-500 dark:text-slate-400">
                  This dashboard doesn't have any visualization data yet. Edit the dashboard to add charts and metrics.
                </p>
                <%= if !@is_public_access do %>
                  <div class="mt-6">
                    <.link
                      patch={~p"/app/dbs/#{@database.id}/dashboards/#{@dashboard.id}/edit"}
                      class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
                    >
                      <svg class="-ml-0.5 mr-1.5 h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10" />
                      </svg>
                      Edit Dashboard
                    </.link>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Dashboard Info -->
      <div class="mt-6">
        <div class="bg-white dark:bg-slate-800 rounded-lg shadow p-4">
          <h3 class="text-sm font-medium text-gray-900 dark:text-white mb-2">Dashboard Information</h3>
          <dl class="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <%= if @dashboard.user do %>
              <div>
                <dt class="text-sm font-medium text-gray-500 dark:text-slate-400">Created By</dt>
                <dd class="mt-1 flex items-center gap-2">
                  <img src={gravatar_url(@dashboard.user.email)} class="h-5 w-5 rounded-full" />
                  <span class="text-sm text-gray-900 dark:text-white"><%= @dashboard.user.email %></span>
                </dd>
              </div>
            <% end %>
            <div>
              <dt class="text-sm font-medium text-gray-500 dark:text-slate-400">Created</dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white">
                <%= Calendar.strftime(@dashboard.inserted_at, "%B %d, %Y at %I:%M %p") %>
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500 dark:text-slate-400">Last Updated</dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white">
                <%= Calendar.strftime(@dashboard.updated_at, "%B %d, %Y at %I:%M %p") %>
              </dd>
            </div>
          </dl>
        </div>
      </div>
    </div>
    """
  end
end