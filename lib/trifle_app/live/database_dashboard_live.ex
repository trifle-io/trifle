defmodule TrifleApp.DatabaseDashboardLive do
  use TrifleApp, :live_view
  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  alias Trifle.Stats.SeriesFetcher
  alias TrifleApp.TimeframeParsing
  alias TrifleApp.TimeframeParsing.Url, as: UrlParsing

  def mount(params, _session, socket) do
    case params do
      %{"id" => database_id, "dashboard_id" => dashboard_id} ->
        # Authenticated access
        database = Organizations.get_database!(database_id)
        dashboard = Organizations.get_dashboard!(dashboard_id)
        
        # Initialize dashboard data state
        socket = initialize_dashboard_state(socket, database, dashboard, false, nil)

        {:ok,
         socket
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
          # Initialize dashboard data state for public access
          socket = initialize_dashboard_state(socket, dashboard.database, dashboard, true, token)
          
          socket = apply_url_params(socket, params)
          
          {:noreply,
           socket
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
      socket = apply_url_params(socket, params)
      {:noreply, apply_action(socket, socket.assigns.live_action, params)}
    end
  end

  defp apply_action(socket, :show, _params) do
    socket = socket
      |> assign(:dashboard_changeset, nil)
      |> assign(:dashboard_form, nil)
    
    # Load dashboard data if key is configured
    if dashboard_has_key?(socket) do
      load_dashboard_data(socket)
    else
      socket
    end
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
  
  # Filter bar message handling
  def handle_info({:filter_bar, {:filter_changed, changes}}, socket) do
    # Update socket with filter changes from FilterBar component
    socket = Enum.reduce(changes, socket, fn {key, value}, acc ->
      case key do
        :from -> assign(acc, :from, value)
        :to -> assign(acc, :to, value)
        :granularity -> assign(acc, :granularity, value)
        :smart_timeframe_input -> assign(acc, :smart_timeframe_input, value)
        :use_fixed_display -> assign(acc, :use_fixed_display, value)
        :reload -> acc  # Just trigger reload
        _ -> acc
      end
    end)
    
    # Update URL with new parameters
    params = build_url_params(socket)
    path = if socket.assigns.is_public_access do
      ~p"/d/#{socket.assigns.dashboard.id}?#{params}"
    else
      ~p"/app/dbs/#{socket.assigns.database.id}/dashboards/#{socket.assigns.dashboard.id}?#{params}"
    end
    
    socket = push_patch(socket, to: path)
    
    # Reload dashboard data
    socket = if dashboard_has_key?(socket) do
      load_dashboard_data(socket)
    else
      socket
    end
    
    {:noreply, socket}
  end

  # Progress message handling
  def handle_info({:loading_progress, progress_map}, socket) do
    {:noreply, assign(socket, :loading_progress, progress_map)}
  end

  def handle_info({:transponding, state}, socket) do
    {:noreply, assign(socket, :transponding, state)}
  end

  # Dashboard Data Management
  
  defp initialize_dashboard_state(socket, database, dashboard, is_public_access, public_token) do
    # Parse timeframe from URL or use default
    {from, to, granularity, smart_timeframe_input, use_fixed_display} = get_default_timeframe_params(database)
    
    # Cache config to avoid recalculation on every render
    database_config = Database.stats_config(database)
    available_granularities = get_available_granularities(database)
    
    # Load transponders to identify response paths and their names
    transponders = Organizations.list_transponders_for_database(database)
    transponder_info = transponders
    |> Enum.map(fn transponder ->
      response_path = Map.get(transponder.config, "response_path", "")
      transponder_name = transponder.name || transponder.key
      if response_path != "", do: {response_path, transponder_name}, else: nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{})

    transponder_response_paths = Map.keys(transponder_info)
    
    socket
    |> assign(:database, database)
    |> assign(:dashboard, dashboard)
    |> assign(:is_public_access, is_public_access)
    |> assign(:public_token, public_token)
    |> assign(:database_config, database_config)
    |> assign(:available_granularities, available_granularities)
    |> assign(:transponder_response_paths, transponder_response_paths)
    |> assign(:transponder_info, transponder_info)
    |> assign(:from, from)
    |> assign(:to, to)
    |> assign(:granularity, granularity)
    |> assign(:smart_timeframe_input, smart_timeframe_input)
    |> assign(:use_fixed_display, use_fixed_display)
    |> assign(:stats, nil)
    |> assign(:timeline, "[]")
    |> assign(:transponder_results, %{successful: [], failed: [], errors: []})
    |> assign(:transponder_errors, [])
    |> assign(:show_error_modal, false)
    |> assign(:loading, false)
    |> assign(:loading_chunks, false)
    |> assign(:loading_progress, nil)
    |> assign(:transponding, false)
    |> assign(:load_duration_microseconds, nil)
  end
  
  defp apply_url_params(socket, params) do
    # Parse URL parameters for filters
    config = socket.assigns.database_config
    
    {from, to, granularity, smart_timeframe_input, use_fixed_display} = 
      UrlParsing.parse_url_params(params, config, socket.assigns.available_granularities)
    
    socket
    |> assign(:from, from)
    |> assign(:to, to)
    |> assign(:granularity, granularity)
    |> assign(:smart_timeframe_input, smart_timeframe_input)
    |> assign(:use_fixed_display, use_fixed_display)
  end
  
  defp get_default_timeframe_params(database) do
    config = Database.stats_config(database)
    granularities = get_available_granularities(database)
    
    # Default to 24h timeframe
    case TimeframeParsing.parse_smart_timeframe("24h", config) do
      {:ok, from, to, smart_input, use_fixed} ->
        {from, to, Enum.at(granularities, 3, "1h"), smart_input, use_fixed}
      {:error, _} ->
        # Fallback
        now = DateTime.utc_now() |> DateTime.shift_zone!(config.time_zone || "UTC")
        from = DateTime.add(now, -24 * 60 * 60, :second)
        {from, now, "1h", "24h", false}
    end
  end
  
  defp get_available_granularities(database) do
    config = Database.stats_config(database)
    config.track_granularities
  end
  
  defp dashboard_has_key?(socket) when is_struct(socket, Phoenix.LiveView.Socket) do
    case socket.assigns.dashboard.key do
      nil -> false
      "" -> false
      _key -> true
    end
  end
  
  defp dashboard_has_key?(assigns) when is_map(assigns) do
    case assigns.dashboard.key do
      nil -> false
      "" -> false
      _key -> true
    end
  end
  
  defp load_dashboard_data(socket) do
    if dashboard_has_key?(socket) do
      socket = assign(socket, 
        load_start_time: System.monotonic_time(:microsecond), 
        loading: true,
        loading_chunks: true,
        loading_progress: nil,
        transponding: false
      )
      
      # Extract values to avoid async socket warnings
      database = socket.assigns.database
      key = socket.assigns.dashboard.key
      granularity = socket.assigns.granularity
      from = socket.assigns.from
      to = socket.assigns.to
      liveview_pid = self() # Capture LiveView PID before async task
      
      start_async(socket, :dashboard_data_task, fn ->
        # Get transponders that match the dashboard key
        matching_transponders = Organizations.list_transponders_for_database(database)
        |> Enum.filter(&(&1.enabled))
        |> Enum.filter(fn transponder -> key_matches_pattern?(key, transponder.key) end)
        |> Enum.sort_by(& &1.order)
        
        # Create progress callback to send updates back to LiveView
        progress_callback = fn progress_info ->
          case progress_info do
            {:chunk_progress, current, total} ->
              send(liveview_pid, {:loading_progress, %{current: current, total: total}})
            {:transponder_progress, :starting} ->
              send(liveview_pid, {:transponding, true})
          end
        end
        
        case SeriesFetcher.fetch_series(database, key, from, to, granularity, matching_transponders, progress_callback: progress_callback) do
          {:ok, result} -> result
          {:error, error} -> {:error, error}
        end
      end)
    else
      socket
    end
  end
  
  defp build_url_params(socket) do
    %{
      "from" => TimeframeParsing.format_for_datetime_input(socket.assigns.from),
      "to" => TimeframeParsing.format_for_datetime_input(socket.assigns.to),
      "granularity" => socket.assigns.granularity,
      "timeframe" => socket.assigns.smart_timeframe_input || "24h"
    }
  end
  
  def handle_async(:dashboard_data_task, {:ok, result}, socket) do
    # Calculate load duration
    load_duration = System.monotonic_time(:microsecond) - socket.assigns.load_start_time
    
    # SeriesFetcher now returns %{series: stats, transponder_results: %{successful: [...], failed: [...], errors: [...]}}
    {:noreply, 
     socket
     |> assign(loading: false)
     |> assign(loading_chunks: false)
     |> assign(loading_progress: nil)
     |> assign(transponding: false)
     |> assign(stats: result.series)
     |> assign(transponder_results: result.transponder_results)
     |> assign(load_duration_microseconds: load_duration)}
  end
  
  def handle_async(:dashboard_data_task, {:error, error}, socket) do
    load_duration = System.monotonic_time(:microsecond) - socket.assigns.load_start_time
    
    {:noreply, 
     socket
     |> assign(loading: false)
     |> assign(loading_chunks: false)
     |> assign(loading_progress: nil)
     |> assign(transponding: false)
     |> assign(stats: nil)
     |> assign(load_duration_microseconds: load_duration)
     |> put_flash(:error, "Failed to load dashboard data: #{inspect(error)}")}
  end
  
  def handle_async(:dashboard_data_task, {:exit, reason}, socket) do
    IO.inspect(reason, label: "Dashboard data fetch failed")
    {:noreply, assign(socket, loading: false)}
  end
  
  
  defp gravatar_url(email) do
    hash = email
      |> String.trim()
      |> String.downcase()
      |> :erlang.md5()
      |> Base.encode16(case: :lower)

    "https://www.gravatar.com/avatar/#{hash}?s=150&d=identicon"
  end
  
  # Summary stats for footer (with transponder statistics)
  def get_summary_stats(assigns) do
    case assigns do
      %{dashboard: %{key: key}, stats: stats, transponder_info: transponder_info, transponder_results: transponder_results} when not is_nil(key) and key != "" and not is_nil(stats) ->
        # Count columns (timeline points)
        column_count = if stats[:at], do: length(stats[:at]), else: 0
        
        # Count paths (rows)
        path_count = if stats[:paths], do: length(stats[:paths]), else: 0
        
        # Use actual transponder results from SeriesFetcher
        successful_transponders = length(transponder_results.successful)
        failed_transponders = length(transponder_results.failed)
        transponder_errors = transponder_results.errors

        result = %{
          key: key,
          column_count: column_count,
          path_count: path_count,
          matching_transponders: successful_transponders + failed_transponders,
          successful_transponders: successful_transponders,
          failed_transponders: failed_transponders,
          transponder_errors: transponder_errors
        }
        
        # Debug logging to help troubleshoot
        IO.inspect(result, label: "Dashboard summary stats")
        result
        
      %{dashboard: %{key: key}} when not is_nil(key) and key != "" ->
        # Dashboard has key but no stats loaded yet - show basic info
        result = %{
          key: key,
          column_count: 0,
          path_count: 0,
          matching_transponders: 0,
          successful_transponders: 0,
          failed_transponders: 0,
          transponder_errors: []
        }
        IO.inspect(result, label: "Dashboard summary stats (no data)")
        result
        
      assigns ->
        IO.inspect(%{
          has_dashboard: Map.has_key?(assigns, :dashboard),
          dashboard_key: assigns[:dashboard][:key],
          has_stats: Map.has_key?(assigns, :stats),
          stats_nil: is_nil(assigns[:stats]),
          has_transponder_results: Map.has_key?(assigns, :transponder_results)
        }, label: "Dashboard summary stats conditions")
        nil
    end
  end
  
  def handle_event("show_transponder_errors", _params, socket) do
    {:noreply, assign(socket, show_error_modal: true)}
  end
  
  def handle_event("hide_transponder_errors", _params, socket) do
    {:noreply, assign(socket, show_error_modal: false)}
  end
  
  def handle_event("reload_data", _params, socket) do
    reload_current_timeframe(socket)
  end

  def handle_event("dashboard_changed", params, socket) do
    %{
      "change_type" => change_type,
      "payload" => payload,
      "event_details" => event_details
    } = params

    require Logger

    # Only save if user owns the dashboard
    if socket.assigns.dashboard.user_id == socket.assigns.current_user.id do
      
      # Validate payload and save only on edit mode exit
      cond do
        is_nil(payload) or payload == %{} or map_size(payload) == 0 ->
          {:noreply, socket}
          
        change_type == "editModeExit" ->
          case Organizations.update_dashboard(socket.assigns.dashboard, %{payload: payload}) do
            {:ok, updated_dashboard} ->
              Logger.info("Dashboard configuration saved")
              {:noreply, assign(socket, dashboard: updated_dashboard)}
              
            {:error, changeset} ->
              Logger.error("Failed to save dashboard: #{inspect(changeset.errors)}")
              {:noreply, socket}
          end
          
        true ->
          # Don't save during active editing
          {:noreply, socket}
      end
    else
      Logger.warn("Unauthorized dashboard change attempt")
      {:noreply, socket}
    end
  end
  
  def format_duration(microseconds) when is_nil(microseconds), do: nil
  
  def format_duration(microseconds) when is_integer(microseconds) do
    cond do
      microseconds < 1_000 ->
        "#{microseconds}μs"
      
      microseconds < 1_000_000 ->
        ms = div(microseconds, 1_000)
        "#{ms}ms"
      
      microseconds < 60_000_000 ->
        seconds = div(microseconds, 1_000_000)
        "#{seconds}s"
      
      true ->
        minutes = div(microseconds, 60_000_000)
        "#{minutes}m"
    end
  end

  def render(assigns) do
    ~H"""
    <!-- Loading Indicator -->
    <%= if (@loading_chunks && @loading_progress) || @transponding do %>
      <div class="fixed inset-0 bg-white bg-opacity-75 dark:bg-slate-900 dark:bg-opacity-90 flex items-center justify-center z-50">
        <div class="flex flex-col items-center space-y-3">
          <div class="flex items-center space-x-2">
            <div class="animate-spin rounded-full h-6 w-6 border-2 border-gray-300 dark:border-slate-600 border-t-teal-500"></div>
            <span class="text-sm text-gray-600 dark:text-white">
              <%= if @transponding do %>
                Transponding data...
              <% else %>
                Scientificating piece <%= @loading_progress.current %> of <%= @loading_progress.total %>...
              <% end %>
            </span>
          </div>
          <!-- Always reserve space for progress bar to keep text position consistent -->
          <div class="w-64 h-2">
            <%= if @loading_chunks && @loading_progress do %>
              <div class="w-full bg-gray-200 dark:bg-slate-600 rounded-full h-2">
                <div
                  class="bg-teal-500 h-2 rounded-full transition-all duration-300"
                  style={"width: #{(@loading_progress.current / @loading_progress.total * 100)}%"}
                ></div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>

    <div class="flex flex-col dark:bg-slate-900 min-h-screen">
      <div class="container mx-auto px-4 sm:px-6 lg:px-8">
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
                <span class="hidden md:inline">Back to Dashboards</span>
                <span class="md:hidden">Back</span>
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
                  <svg class="md:-ml-0.5 md:mr-1.5 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10" />
                  </svg>
                  <span class="hidden md:inline">Edit</span>
                </.link>
                
                <!-- Configure Button -->
                <.link
                  patch={~p"/app/dbs/#{@database.id}/dashboards/#{@dashboard.id}/configure"}
                  class="inline-flex items-center rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                >
                  <svg class="md:-ml-0.5 md:mr-1.5 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z" />
                    <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                  </svg>
                  <span class="hidden md:inline">Configure</span>
                </.link>
              <% end %>
              
              <!-- Status Icon Badges -->
              <div id="status-badges" class="flex items-center gap-2" phx-hook="FastTooltip">
                <!-- Visibility Badge - hidden on XS screens -->
                <div 
                  class={[
                    "hidden sm:inline-flex items-center rounded-md px-3 py-2 text-xs font-medium",
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
                  
                  <!-- Has token: clickable teal badge with visual feedback - hidden on XS screens -->
                  <button 
                    type="button"
                    phx-click={
                      JS.dispatch("phx:copy", to: "#dashboard-public-url")
                      |> JS.hide(to: "#header-link-icon")
                      |> JS.show(to: "#header-check-icon") 
                      |> JS.hide(to: "#header-check-icon", transition: {"", "", ""}, time: 2000)
                      |> JS.show(to: "#header-link-icon", transition: {"", "", ""}, time: 2000)
                    }
                    class="cursor-pointer hidden sm:inline-flex items-center rounded-md bg-teal-50 dark:bg-teal-900 px-3 py-2 text-xs font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30 hover:bg-teal-100 dark:hover:bg-teal-800"
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
                  <!-- No token: gray badge - hidden on XS screens -->
                  <div 
                    class="hidden sm:inline-flex items-center rounded-md bg-gray-50 dark:bg-gray-900 px-3 py-2 text-xs font-medium text-gray-500 dark:text-gray-400 ring-1 ring-inset ring-gray-600/20 dark:ring-gray-500/30"
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

        <!-- Filter Bar (only show if dashboard has a key) -->
      <%= if dashboard_has_key?(assigns) do %>
        <.live_component
          module={TrifleApp.Components.FilterBar}
          id="dashboard_filter_bar"
          config={@database_config}
          from={@from}
          to={@to}
          granularity={@granularity}
          smart_timeframe_input={@smart_timeframe_input}
          use_fixed_display={@use_fixed_display}
          available_granularities={@available_granularities}
          show_controls={true}
          show_timeframe_dropdown={false}
          show_granularity_dropdown={false}
        />
      <% end %>

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
                <%= if @dashboard_changeset && @dashboard_changeset.errors[:key] do %>
                  <p class="mt-1 text-sm text-red-600 dark:text-red-400">
                    <%= case @dashboard_changeset.errors[:key] do
                      [{message, _}] -> message
                      [{message, _} | _] -> message  
                      message when is_binary(message) -> message
                      _ -> "Invalid key format"
                    end %>
                  </p>
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
                <%= if @dashboard_changeset && @dashboard_changeset.errors[:payload] do %>
                  <p class="mt-1 text-sm text-red-600 dark:text-red-400">
                    <%= case @dashboard_changeset.errors[:payload] do
                      [{message, _}] -> message
                      [{message, _} | _] -> message  
                      message when is_binary(message) -> message
                      _ -> "Invalid payload format"
                    end %>
                  </p>
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
          <%= if @dashboard.payload && map_size(@dashboard.payload) > 0 do %>
            <!-- Dashboard with data -->
            <div 
              id="highcharts-dashboard-container"
              phx-hook="HighchartsDashboard"
              data-payload={Jason.encode!(@dashboard.payload)}
              data-edit-mode={to_string(@live_action == :edit)}
              class="dashboard-content w-full"
            >
              <!-- Highcharts Dashboard will be rendered here -->
            </div>
          <% else %>
            <!-- Empty state in white panel -->
            <div class="bg-white dark:bg-slate-800 rounded-lg shadow relative">
              <div class="p-6">
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
              </div>
            </div>
          <% end %>
        </div>
        
        <!-- Sticky Summary Footer -->
        <%= if summary = get_summary_stats(assigns) do %>
          <div class="sticky bottom-0 border-t border-gray-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-4 py-3 shadow-lg z-30">
            <div class="flex flex-wrap items-center gap-4 text-xs">
              
              <!-- Selected Key -->
              <div class="flex items-center gap-1 text-gray-600 dark:text-slate-300">
                <svg class="h-4 w-4 text-teal-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 3c2.755 0 5.455.232 8.083.678.533.09.917.556.917 1.096v1.044a2.25 2.25 0 0 1-.659 1.591l-5.432 5.432a2.25 2.25 0 0 0-.659 1.591v2.927a2.25 2.25 0 0 1-1.244 2.013L9.75 21v-6.568a2.25 2.25 0 0 0-.659-1.591L3.659 7.409A2.25 2.25 0 0 1 3 5.818V4.774c0-.54.384-1.006.917-1.096A48.32 48.32 0 0 1 12 3Z" />
                </svg>
                <span class="font-medium">Key:</span>
                <span class="truncate max-w-32" title={summary.key}><%= summary.key %></span>
              </div>
              
              <!-- Points -->
              <%= if summary.column_count > 0 do %>
                <div class="flex items-center gap-1 text-gray-600 dark:text-slate-300">
                  <svg class="h-4 w-4 text-teal-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 0 1 3 19.875v-6.75ZM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V8.625ZM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V4.125Z" />
                  </svg>
                  <span class="font-medium">Points:</span>
                  <span><%= summary.column_count %></span>
                </div>
              <% end %>
              
              <!-- Paths -->
              <%= if summary.path_count > 0 do %>
                <div class="flex items-center gap-1 text-gray-600 dark:text-slate-300">
                  <svg class="h-4 w-4 text-teal-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 6.75h12M8.25 12h12m-12 5.25h12M3.75 6.75h.007v.008H3.75V6.75Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0ZM3.75 12h.007v.008H3.75V12Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Zm-.375 5.25h.007v.008H3.75v-.008Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Z" />
                  </svg>
                  <span class="font-medium">Paths:</span>
                  <span><%= summary.path_count %></span>
                </div>
              <% end %>

              <!-- Transponders -->
              <div class="flex items-center gap-1">
                <svg class="h-4 w-4 text-teal-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="m21 7.5-2.25-1.313M21 7.5v2.25m0-2.25-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3 2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75 2.25-1.313M12 21.75V19.5m0 2.25-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25" />
                </svg>
                <span class="font-medium text-gray-700 dark:text-slate-300">Transponders:</span>
                
                <!-- Success count -->
                <div class="flex items-center gap-1">
                  <svg class="h-3 w-3 text-green-600" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
                  </svg>
                  <span class="text-gray-900 dark:text-white"><%= summary.successful_transponders %></span>
                </div>
                
                <!-- Fail count -->
                <div class="flex items-center gap-1">
                  <svg class="h-3 w-3 text-red-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z" />
                  </svg>
                  <%= if summary.failed_transponders > 0 do %>
                    <button 
                      phx-click="show_transponder_errors"
                      class="text-red-600 dark:text-red-400 hover:text-red-800 dark:hover:text-red-300 underline"
                    >
                      <%= summary.failed_transponders %>
                    </button>
                  <% else %>
                    <span class="text-gray-900 dark:text-white">0</span>
                  <% end %>
                </div>
              </div>

              <!-- Load Duration -->
              <%= if @load_duration_microseconds do %>
                <div class="flex items-center gap-1 text-gray-600 dark:text-slate-300">
                  <svg class="h-4 w-4 text-teal-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="m3.75 13.5 10.5-11.25L12 10.5h8.25L9.75 21.75 12 13.5H3.75Z" />
                  </svg>
                  <span class="font-medium">Load:</span>
                  <span><%= format_duration(@load_duration_microseconds) %></span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <!-- Debug Series Data (only show when data is loaded) -->
        <%= if @stats && !@is_public_access do %>
          <div class="mt-4 border-t border-gray-200 dark:border-slate-600 bg-gray-50 dark:bg-slate-900 px-4 py-3">
            <details class="text-sm">
              <summary class="cursor-pointer text-gray-700 dark:text-slate-300 font-medium hover:text-gray-900 dark:hover:text-white">
                Debug: Series Data (<%= if @stats[:paths], do: length(@stats[:paths]), else: 0 %> paths, <%= if @stats[:at], do: length(@stats[:at]), else: 0 %> points)
              </summary>
              <div class="mt-3 bg-white dark:bg-slate-800 rounded-lg p-3 border border-gray-200 dark:border-slate-700">
                <pre class="text-xs text-gray-600 dark:text-slate-400 overflow-x-auto max-h-64 overflow-y-auto"><%= Jason.encode!(@stats, pretty: true) %></pre>
              </div>
            </details>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp key_matches_pattern?(key, pattern) do
    cond do
      String.contains?(pattern, "^") or String.contains?(pattern, "$") ->
        case Regex.compile(pattern) do
          {:ok, regex} -> Regex.match?(regex, key)
          {:error, _} -> false
        end
      true ->
        key == pattern
    end
  end
  
  defp reload_current_timeframe(socket) do
    granularity = socket.assigns.granularity
    
    socket =
      socket
      |> assign(loading: true)
      |> push_patch(
        to: build_dashboard_url(socket, %{
          "granularity" => granularity,
          "from" => TimeframeParsing.format_for_datetime_input(socket.assigns.from),
          "to" => TimeframeParsing.format_for_datetime_input(socket.assigns.to),
          "timeframe" => socket.assigns.smart_timeframe_input || "24h"
        })
      )

    {:noreply, socket}
  end

  defp build_dashboard_url(socket, params) do
    if socket.assigns.is_public_access do
      ~p"/d/#{socket.assigns.dashboard.id}?#{params}&token=#{socket.assigns.public_token}"
    else
      ~p"/app/dbs/#{socket.assigns.database.id}/dashboards/#{socket.assigns.dashboard.id}?#{params}"
    end
  end
end