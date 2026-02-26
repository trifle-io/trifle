defmodule TrifleApp.MonitorLive do
  use TrifleApp, :live_view

  alias Phoenix.LiveView.JS
  alias Ecto.Changeset
  alias Trifle.Monitors
  alias Trifle.Monitors.AlertEvaluator
  alias Trifle.Monitors.AlertAdvisor
  alias Trifle.Monitors.{Alert, Execution, Monitor}
  alias Trifle.Organizations
  alias Trifle.Organizations.DashboardSegments
  alias Trifle.Organizations.OrganizationMembership
  alias Trifle.Stats.Configuration
  alias Trifle.Stats.Nocturnal
  alias Trifle.Stats.Nocturnal.Parser
  alias Trifle.Exports.Series, as: SeriesExport
  alias Trifle.Stats.Source, as: StatsSource
  alias Trifle.Stats.Tabler

  alias TrifleApp.Components.DashboardWidgets.{
    Category,
    Distribution,
    Kpi,
    Table,
    Text,
    Timeseries,
    WidgetData,
    WidgetView
  }

  alias TrifleApp.Components.DataTable

  alias TrifleApp.DesignSystem.ChartColors
  alias TrifleApp.MonitorComponents
  alias TrifleApp.MonitorAlertFormComponent
  alias TrifleApp.MonitorsLive.FormComponent
  alias TrifleApp.TimeframeParsing
  alias TrifleApp.Exports.MonitorLayout
  import TrifleApp.Components.DashboardFooter, only: [dashboard_footer: 1]

  @default_granularities ["15m", "1h", "6h", "1d", "1w", "1mo"]

  @impl true
  def mount(_params, _session, %{assigns: %{current_membership: nil}} = socket) do
    {:ok, redirect(socket, to: ~p"/organization/profile")}
  end

  def mount(
        _params,
        _session,
        %{assigns: %{current_user: user, current_membership: membership}} = socket
      ) do
    {:ok,
     socket
     |> assign(:current_user, user)
     |> assign(:current_membership, membership)
     |> assign(:nav_section, :monitors)
     |> assign(:monitor, nil)
     |> assign(:executions, [])
     |> assign(:dashboards, load_dashboards(user, membership))
     |> assign(:sources, load_sources(membership))
     |> assign(:delivery_options, Monitors.delivery_options_for_membership(membership))
     |> assign(:modal_monitor, nil)
     |> assign(:modal_changeset, nil)
     |> assign(:source, nil)
     |> assign(:stats_config, nil)
     |> assign(:available_granularities, [])
     |> assign(:from, nil)
     |> assign(:to, nil)
     |> assign(:granularity, nil)
     |> assign(:smart_timeframe_input, nil)
     |> assign(:use_fixed_display, false)
     |> assign(:loading, false)
     |> assign(:loading_progress, nil)
     |> assign(:transponding, false)
     |> assign(:load_duration_microseconds, nil)
     |> assign(:stats, nil)
     |> assign(:transponder_results, default_transponder_results())
     |> assign(:selected_source_ref, nil)
     |> assign(:alerts, [])
     |> assign(:alert_modal, nil)
     |> assign(:alert_modal_changeset, nil)
     |> assign(:alert_modal_action, nil)
     |> assign(:insights_dashboard, nil)
     |> assign(:insights_kpi_values, %{})
     |> assign(:insights_kpi_visuals, %{})
     |> assign(:insights_timeseries, %{})
     |> assign(:insights_category, %{})
     |> assign(:insights_table, %{})
     |> assign(:insights_text_widgets, %{})
     |> assign(:insights_list, %{})
     |> assign(:insights_distribution, %{})
     |> assign(:alert_evaluations, %{})
     |> assign(:expanded_widget, nil)
     |> assign(:show_export_dropdown, false)
     |> assign(:show_error_modal, false)
     |> assign(:test_delivery_state, nil)
     |> assign(:selected_execution, nil)
     |> assign(:ai_requests, %{})}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    monitor = load_monitor(socket, id)

    socket =
      socket
      |> assign_monitor(monitor)
      |> assign(:page_title, build_page_title(socket.assigns.live_action, monitor))
      |> assign(:breadcrumb_links, [{"Monitors", ~p"/monitors"}, monitor.name])
      |> assign(:executions, Monitors.list_recent_executions(monitor))
      |> initialize_monitor_context()

    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :show) do
    socket
    |> assign(:modal_monitor, nil)
    |> assign(:modal_changeset, nil)
    |> load_monitor_data()
  end

  defp apply_action(socket, :configure) do
    monitor = socket.assigns.monitor
    changeset = Monitors.change_monitor(monitor, %{})

    if socket.assigns[:can_edit_monitor] do
      socket
      |> assign(:modal_monitor, monitor)
      |> assign(:modal_changeset, changeset)
      |> assign(:page_title, "Configure · #{monitor.name}")
    else
      target =
        case monitor do
          %Monitor{id: id} -> ~p"/monitors/#{id}"
          _ -> ~p"/monitors"
        end

      socket
      |> put_flash(:error, "You do not have permission to configure this monitor")
      |> push_patch(to: target)
    end
  end

  @impl true
  def handle_event("delete_monitor", _params, socket) do
    delete_monitor(socket, socket.assigns.monitor)
  end

  def handle_event("show_transponder_errors", _params, socket) do
    {:noreply, assign(socket, :show_error_modal, true)}
  end

  def handle_event("hide_transponder_errors", _params, socket) do
    {:noreply, assign(socket, :show_error_modal, false)}
  end

  def handle_event("show_execution_details", %{"id" => id}, socket) do
    execution = find_execution(socket.assigns.executions, id)

    case execution do
      %Execution{} = exec ->
        {:noreply, assign(socket, :selected_execution, exec)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("hide_execution_details", _params, socket) do
    {:noreply, assign(socket, :selected_execution, nil)}
  end

  def handle_event(
        "new_alert",
        _params,
        %{assigns: %{monitor: %{type: :alert} = monitor}} = socket
      ) do
    membership = socket.assigns[:current_membership]

    if match?(%OrganizationMembership{}, membership) &&
         Monitors.can_edit_monitor?(monitor, membership) do
      alert = %Alert{monitor_id: monitor.id}
      changeset = Monitors.change_alert(alert, %{})

      {:noreply,
       socket
       |> assign(:alert_modal, alert)
       |> assign(:alert_modal_changeset, changeset)
       |> assign(:alert_modal_action, :new)}
    else
      message =
        if monitor.locked do
          "This monitor is locked. Only the owner or organization admins can add alerts."
        else
          "You do not have permission to add alerts for this monitor."
        end

      {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("new_alert", _params, socket), do: {:noreply, socket}

  def handle_event(
        "edit_alert",
        %{"id" => id},
        %{assigns: %{monitor: %{type: :alert} = monitor}} = socket
      ) do
    membership = socket.assigns[:current_membership]

    if match?(%OrganizationMembership{}, membership) &&
         Monitors.can_edit_monitor?(monitor, membership) do
      case find_alert(monitor, id) do
        nil ->
          {:noreply, socket}

        %Alert{} = alert ->
          {:noreply,
           socket
           |> assign(:alert_modal, alert)
           |> assign(:alert_modal_changeset, Monitors.change_alert(alert, %{}))
           |> assign(:alert_modal_action, :edit)}
      end
    else
      message =
        if monitor.locked do
          "This monitor is locked. Only the owner or organization admins can edit alerts."
        else
          "You do not have permission to edit alerts for this monitor."
        end

      {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("edit_alert", _params, socket), do: {:noreply, socket}

  def handle_event("close_alert_modal", _params, socket) do
    {:noreply, clear_alert_modal(socket)}
  end

  def handle_event("toggle_export_dropdown", _params, socket) do
    current = socket.assigns[:show_export_dropdown] || false

    {:noreply, assign(socket, :show_export_dropdown, !current)}
  end

  def handle_event("hide_export_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_export_dropdown, false)}
  end

  def handle_event("download_monitor_csv", _params, socket) do
    series = SeriesExport.extract_series(socket.assigns[:stats])

    if SeriesExport.has_data?(series) do
      csv = SeriesExport.to_csv(series)
      fname = monitor_export_filename("monitor", socket.assigns.monitor, ".csv")

      {:noreply,
       socket
       |> assign(:show_export_dropdown, false)
       |> push_event("file_download", %{content: csv, filename: fname, type: "text/csv"})}
    else
      {:noreply, put_flash(socket, :error, "No data to export")}
    end
  end

  def handle_event("download_monitor_json", _params, socket) do
    series = SeriesExport.extract_series(socket.assigns[:stats])

    if SeriesExport.has_data?(series) do
      json = SeriesExport.to_json(series)
      fname = monitor_export_filename("monitor", socket.assigns.monitor, ".json")

      {:noreply,
       socket
       |> assign(:show_export_dropdown, false)
       |> push_event("file_download", %{
         content: json,
         filename: fname,
         type: "application/json"
       })}
    else
      {:noreply, put_flash(socket, :error, "No data to export")}
    end
  end

  def handle_event("expand_widget", %{"id" => id}, socket) do
    expanded =
      socket.assigns.insights_dashboard
      |> find_monitor_widget(id)
      |> case do
        nil -> nil
        widget -> build_monitor_expanded_widget(socket, widget)
      end

    {:noreply, assign(socket, :expanded_widget, expanded)}
  end

  def handle_event("close_expanded_widget", _params, socket) do
    {:noreply, assign(socket, :expanded_widget, nil)}
  end

  def handle_event("toggle_status", _params, socket) do
    %{monitor: monitor, current_membership: membership} = socket.assigns
    next_status = if monitor.status == :active, do: :paused, else: :active

    case Monitors.update_monitor_for_membership(monitor, membership, %{status: next_status}) do
      {:ok, updated} ->
        refreshed = load_monitor(socket, updated.id)

        {:noreply,
         socket
         |> put_flash(:info, "Monitor #{status_label(updated.status)}")
         |> assign_monitor(refreshed)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You do not have permission to update this monitor")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error_message(changeset))}
    end
  end

  def handle_event("test_delivery", _params, %{assigns: %{monitor: monitor}} = socket) do
    export_params = build_monitor_export_params(socket.assigns)
    media_types = Monitors.delivery_media_types_from_media(monitor.delivery_media || [])

    socket =
      socket
      |> assign(:test_delivery_state, {:monitor, :running})
      |> start_async({:test_delivery, :monitor}, fn ->
        Monitors.test_deliver_monitor(monitor,
          export_params: export_params,
          media_types: media_types
        )
      end)

    {:noreply, socket}
  end

  def handle_event("test_alert_delivery", %{"id" => id}, socket) do
    monitor = socket.assigns.monitor

    case find_alert(monitor, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Alert not found.")}

      %Alert{} = alert ->
        export_params = build_monitor_export_params(socket.assigns)
        media_types = Monitors.delivery_media_types_from_media(monitor.delivery_media || [])

        socket =
          socket
          |> assign(:test_delivery_state, {:alert, alert.id, :running})
          |> start_async({:test_delivery, {:alert, alert.id}}, fn ->
            Monitors.test_deliver_alert(monitor, alert,
              export_params: export_params,
              media_types: media_types
            )
          end)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({FormComponent, {:saved, monitor}}, socket) do
    refreshed = load_monitor(socket, monitor.id)
    membership = socket.assigns.current_membership

    socket =
      socket
      |> assign_monitor(refreshed)
      |> assign(:executions, Monitors.list_recent_executions(refreshed))
      |> assign(:sources, load_sources(membership))
      |> assign(:delivery_options, Monitors.delivery_options_for_membership(membership))

    socket =
      socket
      |> put_flash(:info, "Monitor updated")
      |> push_patch(to: ~p"/monitors/#{monitor.id}")

    {:noreply, socket}
  end

  def handle_info({FormComponent, {:delete, monitor}}, socket) do
    delete_monitor(socket, monitor)
  end

  def handle_info({FormComponent, {:error, message}}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  def handle_info({MonitorAlertFormComponent, {:ai_recommendation_request, request}}, socket) do
    case prepare_ai_request(socket, request) do
      {:ok, updated_socket} ->
        {:noreply, updated_socket}

      {:error, message} ->
        send_ai_error(request, message)
        {:noreply, socket}
    end
  end

  def handle_info({MonitorAlertFormComponent, {:saved, _alert, action}}, socket) do
    message = if action == :new, do: "Alert created", else: "Alert updated"

    {:noreply,
     socket
     |> refresh_monitor_assigns()
     |> clear_alert_modal()
     |> load_monitor_data()
     |> put_flash(:info, message)}
  end

  def handle_info({MonitorAlertFormComponent, {:deleted, _alert}}, socket) do
    {:noreply,
     socket
     |> refresh_monitor_assigns()
     |> clear_alert_modal()
     |> load_monitor_data()
     |> put_flash(:info, "Alert deleted")}
  end

  def handle_info({MonitorAlertFormComponent, {:error, message}}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  def handle_info({:filter_bar, {:filter_changed, changes}}, socket) do
    {:noreply, handle_filter_change(socket, changes)}
  end

  def handle_info({:loading_progress, progress_map}, socket) do
    {:noreply, assign(socket, :loading_progress, progress_map)}
  end

  def handle_info({:transponding, state}, socket) do
    {:noreply, assign(socket, :transponding, state)}
  end

  def handle_info({:ai_recommendation_tick, component_id, request_id}, socket) do
    ai_requests = socket.assigns[:ai_requests] || %{}

    case Map.get(ai_requests, request_id) do
      %{component_id: ^component_id, started_at: started_at} = entry ->
        now = DateTime.utc_now()

        send_update(MonitorAlertFormComponent,
          id: component_id,
          ai_progress: %{
            request_id: request_id,
            started_at: started_at,
            tick_at: now
          }
        )

        updated_entry = Map.put(entry, :tick_at, now)
        updated_requests = Map.put(ai_requests, request_id, updated_entry)

        Process.send_after(self(), {:ai_recommendation_tick, component_id, request_id}, 1_000)

        {:noreply, assign(socket, :ai_requests, updated_requests)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:monitor_data_task, {:ok, result}, socket) do
    load_duration =
      case socket.assigns[:load_start_time] do
        nil -> nil
        started -> System.monotonic_time(:microsecond) - started
      end

    stats = Map.get(result, :series)

    transponder_results =
      result
      |> Map.get(:transponder_results, %{})
      |> normalize_transponder_results()

    socket =
      socket
      |> assign(:loading, false)
      |> assign(:loading_progress, nil)
      |> assign(:transponding, false)
      |> assign(:stats, stats)
      |> assign(:transponder_results, transponder_results)
      |> assign(:load_duration_microseconds, load_duration)
      |> assign_monitor_widget_datasets(stats)
      |> assign_monitor_alerts()
      |> maybe_refresh_expanded_widget()

    export_params = build_monitor_export_params(socket.assigns)

    {:noreply,
     socket
     |> push_event("monitor_widget_export_params", %{params: export_params})}
  end

  @impl true
  def handle_async(:monitor_data_task, {:error, error}, socket) do
    load_duration =
      case socket.assigns[:load_start_time] do
        nil -> nil
        started -> System.monotonic_time(:microsecond) - started
      end

    socket =
      socket
      |> assign(:loading, false)
      |> assign(:loading_progress, nil)
      |> assign(:transponding, false)
      |> assign(:stats, nil)
      |> assign(:transponder_results, default_transponder_results())
      |> assign(:load_duration_microseconds, load_duration)
      |> reset_monitor_widget_datasets()
      |> assign_monitor_alerts()
      |> put_flash(:error, "Failed to load monitor data: #{inspect(error)}")

    export_params = build_monitor_export_params(socket.assigns)

    {:noreply,
     socket
     |> push_event("monitor_widget_export_params", %{params: export_params})}
  end

  @impl true
  def handle_async(:monitor_data_task, {:exit, reason}, socket) do
    socket =
      socket
      |> assign(:loading, false)
      |> assign(:loading_progress, nil)
      |> assign(:transponding, false)
      |> assign(:stats, nil)
      |> assign(:transponder_results, default_transponder_results())
      |> reset_monitor_widget_datasets()
      |> put_flash(:error, "Monitor data task crashed: #{inspect(reason)}")

    export_params = build_monitor_export_params(socket.assigns)

    {:noreply,
     socket
     |> push_event("monitor_widget_export_params", %{params: export_params})}
  end

  def handle_async({:ai_recommendation, component_id, request_id}, {:ok, {:ok, result}}, socket)
      when is_map(result) do
    {socket, finished_at, entry} = finalize_ai_request(socket, component_id, request_id)

    started_at = entry && Map.get(entry, :started_at)

    result =
      result
      |> Map.put(:finished_at, finished_at)
      |> maybe_put_started(started_at)

    send_update(MonitorAlertFormComponent,
      id: component_id,
      ai_recommendation:
        Map.merge(result, %{
          request_id: request_id
        })
    )

    {:noreply, socket}
  end

  def handle_async(
        {:ai_recommendation, component_id, request_id},
        {:ok, {:error, reason}},
        socket
      ) do
    {socket, finished_at, _entry} = finalize_ai_request(socket, component_id, request_id)

    send_ai_error(
      %{component_id: component_id, request_id: request_id, finished_at: finished_at},
      format_ai_error(reason)
    )

    {:noreply, socket}
  end

  def handle_async({:ai_recommendation, component_id, request_id}, {:ok, result}, socket)
      when is_map(result) do
    {socket, finished_at, entry} = finalize_ai_request(socket, component_id, request_id)

    started_at = entry && Map.get(entry, :started_at)

    result =
      result
      |> Map.put(:finished_at, finished_at)
      |> maybe_put_started(started_at)

    send_update(MonitorAlertFormComponent,
      id: component_id,
      ai_recommendation:
        Map.merge(result, %{
          request_id: request_id
        })
    )

    {:noreply, socket}
  end

  def handle_async({:ai_recommendation, component_id, request_id}, {:error, reason}, socket) do
    {socket, finished_at, _entry} = finalize_ai_request(socket, component_id, request_id)

    send_ai_error(
      %{component_id: component_id, request_id: request_id, finished_at: finished_at},
      format_ai_error(reason)
    )

    {:noreply, socket}
  end

  def handle_async({:ai_recommendation, component_id, request_id}, {:exit, reason}, socket) do
    {socket, finished_at, _entry} = finalize_ai_request(socket, component_id, request_id)

    send_ai_error(
      %{component_id: component_id, request_id: request_id, finished_at: finished_at},
      format_ai_error({:error, reason})
    )

    {:noreply, socket}
  end

  def handle_async({:test_delivery, :monitor}, {:ok, result}, socket) do
    case result do
      {:ok, result_map} when is_map(result_map) ->
        message = format_test_delivery_success(:monitor, socket, result_map)

        {:noreply,
         socket
         |> assign(:test_delivery_state, nil)
         |> put_flash(:info, message)}

      {:error, reason} ->
        handle_async({:test_delivery, :monitor}, {:error, reason}, socket)

      result_map when is_map(result_map) ->
        message = format_test_delivery_success(:monitor, socket, result_map)

        {:noreply,
         socket
         |> assign(:test_delivery_state, nil)
         |> put_flash(:info, message)}

      _other ->
        handle_async({:test_delivery, :monitor}, {:error, result}, socket)
    end
  end

  def handle_async({:test_delivery, :monitor}, {:error, reason}, socket) do
    {:noreply,
     socket
     |> assign(:test_delivery_state, nil)
     |> put_flash(:error, format_test_delivery_error(reason))}
  end

  def handle_async({:test_delivery, {:alert, alert_id}}, {:ok, result}, socket) do
    case result do
      {:ok, result_map} when is_map(result_map) ->
        message = format_test_delivery_success({:alert, alert_id}, socket, result_map)

        {:noreply,
         socket
         |> assign(:test_delivery_state, nil)
         |> put_flash(:info, message)}

      {:error, reason} ->
        handle_async({:test_delivery, {:alert, alert_id}}, {:error, reason}, socket)

      result_map when is_map(result_map) ->
        message = format_test_delivery_success({:alert, alert_id}, socket, result_map)

        {:noreply,
         socket
         |> assign(:test_delivery_state, nil)
         |> put_flash(:info, message)}

      _other ->
        handle_async({:test_delivery, {:alert, alert_id}}, {:error, result}, socket)
    end
  end

  def handle_async({:test_delivery, {:alert, _alert_id}}, {:error, reason}, socket) do
    {:noreply,
     socket
     |> assign(:test_delivery_state, nil)
     |> put_flash(:error, format_test_delivery_error(reason))}
  end

  def handle_async({:test_delivery, _key}, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:test_delivery_state, nil)
     |> put_flash(:error, format_test_delivery_error({:exit, reason}))}
  end

  defp load_monitor(socket, id) do
    membership = socket.assigns.current_membership

    Monitors.get_monitor_for_membership!(membership, id, preload: [:dashboard])
    |> ensure_sorted_alerts()
  end

  defp ensure_sorted_alerts(%Monitor{} = monitor) do
    %{monitor | alerts: Monitors.sort_alerts(monitor.alerts)}
  end

  defp ensure_sorted_alerts(other), do: other

  defp prepare_ai_request(socket, %{component_id: id, request_id: request_id} = request) do
    cond do
      is_nil(id) or is_nil(request_id) ->
        {:error, "Unable to route AI response to the form."}

      is_nil(socket.assigns.monitor) ->
        {:error, "Monitor is not loaded yet."}

      !match?(%Trifle.Stats.Series{}, socket.assigns[:stats]) ->
        {:error, "Load the metric data first, then try again."}

      true ->
        strategy = Map.get(request, :strategy) || Map.get(request, "strategy")
        variant = Map.get(request, :variant) || Map.get(request, "variant")

        socket = register_ai_request(socket, id, request_id)

        monitor = socket.assigns.monitor
        stats = socket.assigns.stats

        socket =
          start_async(
            socket,
            {:ai_recommendation, id, request_id},
            fn ->
              AlertAdvisor.recommend(
                monitor,
                stats,
                strategy: strategy,
                variant: variant
              )
            end
          )

        {:ok, socket}
    end
  end

  defp prepare_ai_request(_socket, _request), do: {:error, "Unable to request recommendation."}

  defp send_ai_error(%{component_id: nil}, _message), do: :ok

  defp send_ai_error(%{component_id: id, request_id: request_id} = attrs, message) do
    finished_at = attrs[:finished_at] || DateTime.utc_now()

    send_update(MonitorAlertFormComponent,
      id: id,
      ai_recommendation_error: %{
        request_id: request_id,
        message: message,
        finished_at: finished_at
      }
    )
  end

  defp send_ai_error(_request, _message), do: :ok

  defp register_ai_request(socket, component_id, request_id) do
    started_at = DateTime.utc_now()

    ai_requests =
      (socket.assigns[:ai_requests] || %{})
      |> Map.put(request_id, %{
        component_id: component_id,
        started_at: started_at,
        status: :running
      })

    send_update(MonitorAlertFormComponent,
      id: component_id,
      ai_progress: %{
        request_id: request_id,
        started_at: started_at,
        tick_at: started_at
      }
    )

    Process.send_after(self(), {:ai_recommendation_tick, component_id, request_id}, 1_000)

    assign(socket, :ai_requests, ai_requests)
  end

  defp finalize_ai_request(socket, _component_id, request_id) do
    finished_at = DateTime.utc_now()
    ai_requests = socket.assigns[:ai_requests] || %{}
    {entry, remaining} = Map.pop(ai_requests, request_id)
    {assign(socket, :ai_requests, remaining || %{}), finished_at, entry}
  end

  defp maybe_put_started(result, nil), do: result

  defp maybe_put_started(result, %DateTime{} = started_at) do
    Map.put_new(result, :started_at, started_at)
  end

  defp format_ai_error(:missing_metric_path),
    do: "Set a metric path for this monitor before requesting recommendations."

  defp format_ai_error(:no_data),
    do: "No recent data available for this metric. Adjust the timeframe and retry."

  defp format_ai_error(:unsupported_strategy),
    do: "This alert type is not supported for AI configuration yet."

  defp format_ai_error(:unsupported_variant),
    do: "Unknown sensitivity option. Try the buttons again."

  defp format_ai_error(:missing_api_key),
    do: "OpenAI API key is not configured. Set OPENAI_API_KEY and restart the app."

  defp format_ai_error({:missing_value, path}),
    do: "AI response was incomplete. Missing #{format_path(path)}."

  defp format_ai_error({:invalid_value, path}) when is_list(path),
    do: "AI returned an invalid value for #{format_path(path)}."

  defp format_ai_error({:invalid_value, value}) when is_binary(value),
    do: "Could not interpret AI response (#{value})."

  defp format_ai_error({:http_error, status, _body}),
    do: "OpenAI request failed with status #{status}."

  defp format_ai_error({:api_error, reason}),
    do: "OpenAI error: #{reason}."

  defp format_ai_error({:error, reason}),
    do: "OpenAI error: #{inspect(reason)}."

  defp format_ai_error(%Jason.DecodeError{} = error),
    do: "Could not decode AI response: #{Exception.message(error)}."

  defp format_ai_error(reason) when is_binary(reason), do: reason
  defp format_ai_error(reason), do: "AI recommendation failed: #{inspect(reason)}."

  defp format_path(path) when is_list(path) do
    path
    |> Enum.map(&to_string/1)
    |> Enum.join(".")
  end

  defp format_path(path), do: path |> to_string()

  defp build_page_title(:configure, monitor), do: "Configure · #{monitor.name}"
  defp build_page_title(_action, monitor), do: "#{monitor.name} · Monitor"

  defp load_dashboards(user, membership) do
    Organizations.list_all_dashboards_for_membership(user, membership)
  end

  defp load_sources(membership) do
    StatsSource.list_for_membership(membership)
  end

  defp initialize_monitor_context(socket) do
    monitor = socket.assigns.monitor
    sources = socket.assigns[:sources] || []
    source = resolve_monitor_source(sources, monitor)
    updated_sources = ensure_source_in_list(sources, source)
    config = source_stats_config(source)
    granularities = available_granularity_options(source)

    {from, to, granularity, timeframe_input, use_fixed_display} =
      monitor_timeframe_defaults(monitor, source, config, granularities)

    {segment_values, monitor_segments} = monitor_segment_state(monitor)

    resolved_key = resolve_monitor_key(monitor, segment_values, monitor_segments)

    socket
    |> assign(:source, source)
    |> assign(:sources, updated_sources)
    |> assign(:stats_config, config)
    |> assign(:available_granularities, granularities)
    |> assign(:granularity, granularity)
    |> assign(:from, from)
    |> assign(:to, to)
    |> assign(:smart_timeframe_input, timeframe_input)
    |> assign(:use_fixed_display, use_fixed_display)
    |> assign(:resolved_key, resolved_key)
    |> assign(:segment_values, segment_values)
    |> assign(:monitor_segments, monitor_segments)
    |> assign(:selected_source_ref, component_source_ref(source))
    |> assign(:alerts, Monitors.sort_alerts(monitor.alerts))
    |> assign(:insights_dashboard, build_monitor_insights_dashboard(monitor))
    |> reset_monitor_widget_datasets()
  end

  defp handle_filter_change(socket, changes) when is_map(changes) do
    socket =
      socket
      |> maybe_assign_change(:smart_timeframe_input, Map.get(changes, :smart_timeframe_input))
      |> maybe_assign_change(:use_fixed_display, Map.get(changes, :use_fixed_display))
      |> maybe_assign_change(:from, Map.get(changes, :from))
      |> maybe_assign_change(:to, Map.get(changes, :to))

    socket =
      case Map.fetch(changes, :granularity) do
        {:ok, granularity} -> assign_granularity(socket, granularity)
        :error -> socket
      end

    socket =
      if should_align_timeframe?(changes, socket) do
        assign_timeframe_from_input(socket, socket.assigns.smart_timeframe_input || "24h")
      else
        socket
      end

    export_params = build_monitor_export_params(socket.assigns)

    socket
    |> push_event("monitor_widget_export_params", %{params: export_params})
    |> load_monitor_data()
  end

  defp maybe_assign_change(socket, _key, nil), do: socket
  defp maybe_assign_change(socket, key, value), do: assign(socket, key, value)

  defp assign_granularity(socket, nil), do: socket

  defp assign_granularity(socket, granularity) do
    available = socket.assigns[:available_granularities] || []

    fallback =
      case socket.assigns[:source] do
        nil -> nil
        source -> StatsSource.default_granularity(source)
      end

    normalized = normalize_granularity(granularity, available, fallback)
    assign(socket, :granularity, normalized)
  end

  defp should_align_timeframe?(changes, socket) do
    explicit_range? = Map.has_key?(changes, :from) || Map.has_key?(changes, :to)

    cond do
      Map.get(changes, :use_fixed_display) == false ->
        true

      Map.has_key?(changes, :smart_timeframe_input) and !explicit_range? ->
        true

      Map.get(changes, :reload) && socket.assigns.use_fixed_display == false ->
        true

      true ->
        false
    end
  end

  defp assign_timeframe_from_input(socket, timeframe_input) do
    monitor = socket.assigns.monitor
    config = socket.assigns[:stats_config] || source_stats_config(nil)

    case monitor do
      %Monitor{type: :report} ->
        source = socket.assigns[:source]

        case compute_report_time_range(monitor, timeframe_input, config, source) do
          {:ok, from, to} ->
            socket
            |> assign(:from, from)
            |> assign(:to, to)

          :error ->
            socket
        end

      %Monitor{type: :alert} ->
        case parse_timeframe_range(timeframe_input, config) do
          {:ok, from, to} ->
            socket
            |> assign(:from, from)
            |> assign(:to, to)

          :error ->
            socket
        end

      _ ->
        case parse_timeframe_range(timeframe_input, config) do
          {:ok, from, to} ->
            socket
            |> assign(:from, from)
            |> assign(:to, to)

          :error ->
            socket
        end
    end
  end

  defp compute_report_time_range(%Monitor{} = monitor, timeframe_input, config, source) do
    settings = monitor.report_settings || %{}
    frequency = Map.get(settings, :frequency)
    now = timezone_now(config)

    effective_input =
      case timeframe_input do
        "c" -> resolve_report_timeframe(settings.timeframe, frequency, source)
        other -> other
      end

    cond do
      frequency == :hourly ->
        from = floor_time(now, 1, :hour, config)
        to = inclusive_period_end(from, 1, :hour, config)
        {:ok, from, to}

      frequency == :daily ->
        from = floor_time(now, 1, :day, config)
        to = inclusive_period_end(from, 1, :day, config)
        {:ok, from, to}

      frequency == :weekly ->
        from = floor_time(now, 1, :week, config)
        to = inclusive_period_end(from, 1, :week, config)
        {:ok, from, to}

      frequency == :monthly ->
        from = floor_time(now, 1, :month, config)
        to = inclusive_period_end(from, 1, :month, config)
        {:ok, from, to}

      true ->
        parser = Parser.new(effective_input || "24h")

        if Parser.valid?(parser) do
          from = floor_time(now, parser.offset, parser.unit, config)

          to =
            from
            |> Nocturnal.new(config)
            |> Nocturnal.add(parser.offset, parser.unit)
            |> inclusive_end(config)

          {:ok, from, to}
        else
          parse_timeframe_range(effective_input, config)
        end
    end
  end

  defp parse_timeframe_range(timeframe_input, config) do
    case TimeframeParsing.parse_smart_timeframe(timeframe_input || "24h", config) do
      {:ok, from, to, _smart, _fixed} ->
        {:ok, from, to}

      {:error, _reason} ->
        case TimeframeParsing.parse_smart_timeframe("24h", config) do
          {:ok, from, to, _smart, _fixed} -> {:ok, from, to}
          _ -> :error
        end
    end
  end

  defp timezone_now(config) do
    DateTime.utc_now()
    |> DateTime.shift_zone!(config.time_zone || "UTC")
  end

  defp floor_time(datetime, offset, unit, config) do
    datetime
    |> Nocturnal.new(config)
    |> Nocturnal.floor(offset, unit)
  end

  defp inclusive_period_end(from, offset, unit, config) do
    from
    |> Nocturnal.new(config)
    |> Nocturnal.add(offset, unit)
    |> inclusive_end(config)
  end

  defp inclusive_end(nil, _config), do: nil

  defp inclusive_end(datetime, config) do
    tz_database = config.time_zone_database || Tzdata.TimeZoneDatabase
    DateTime.add(datetime, -1, :second, tz_database)
  end

  defp monitor_timeframe_defaults(
         %Monitor{type: :report} = monitor,
         source,
         config,
         granularities
       ) do
    report_timeframe_defaults(monitor, source, config, granularities)
  end

  defp monitor_timeframe_defaults(%Monitor{type: :alert} = monitor, source, config, granularities) do
    alert_timeframe_defaults(monitor, source, config, granularities)
  end

  defp monitor_timeframe_defaults(_monitor, _source, config, _granularities) do
    case parse_timeframe_range("24h", config) do
      {:ok, from, to} -> {from, to, "1h", "24h", false}
      :error -> {nil, nil, nil, "24h", false}
    end
  end

  defp report_timeframe_defaults(%Monitor{} = monitor, source, config, granularities) do
    settings = monitor.report_settings || %{}
    frequency = Map.get(settings, :frequency, :weekly)
    timeframe_hint = resolve_report_timeframe(settings.timeframe, frequency, source)

    {from, to} =
      case compute_report_time_range(monitor, timeframe_hint, config, source) do
        {:ok, from, to} ->
          {from, to}

        :error ->
          case parse_timeframe_range(timeframe_hint, config) do
            {:ok, fallback_from, fallback_to} -> {fallback_from, fallback_to}
            :error -> {nil, nil}
          end
      end

    fallback_granularity =
      case source do
        nil -> nil
        src -> StatsSource.default_granularity(src)
      end

    granularity =
      normalize_granularity(settings.granularity, granularities, fallback_granularity)

    use_fixed_display = not is_nil(from) and not is_nil(to)
    smart_input = if use_fixed_display, do: "c", else: timeframe_hint

    {from, to, granularity, smart_input, use_fixed_display}
  end

  defp resolve_report_timeframe(timeframe, frequency, source) do
    cond do
      is_binary(timeframe) and String.trim(timeframe) != "" ->
        timeframe

      frequency == :hourly ->
        "1h"

      frequency == :daily ->
        "1d"

      frequency == :weekly ->
        "7d"

      frequency == :monthly ->
        "1mo"

      source ->
        StatsSource.default_timeframe(source) || "24h"

      true ->
        "24h"
    end
  end

  defp alert_timeframe_defaults(%Monitor{} = monitor, source, config, granularities) do
    evaluation_timeframe =
      monitor.alert_timeframe || StatsSource.default_timeframe(source) || "1h"

    display_timeframe = multiply_timeframe(evaluation_timeframe, 4)

    {from, to} =
      case parse_timeframe_range(display_timeframe, config) do
        {:ok, from, to} ->
          {from, to}

        :error ->
          case parse_timeframe_range("24h", config) do
            {:ok, fallback_from, fallback_to} -> {fallback_from, fallback_to}
            :error -> {nil, nil}
          end
      end

    fallback_granularity =
      monitor.alert_granularity ||
        case source do
          nil -> nil
          src -> StatsSource.default_granularity(src)
        end

    granularity =
      normalize_granularity(monitor.alert_granularity, granularities, fallback_granularity)

    {from, to, granularity, display_timeframe, false}
  end

  defp multiply_timeframe(timeframe, multiplier) when is_binary(timeframe) and multiplier >= 1 do
    parser = Parser.new(timeframe)

    if Parser.valid?(parser) do
      offset = parser.offset * multiplier
      "#{offset}#{timeframe_unit_suffix(parser.unit)}"
    else
      timeframe
    end
  end

  defp multiply_timeframe(_timeframe, _multiplier), do: "24h"

  defp timeframe_unit_suffix(:second), do: "s"
  defp timeframe_unit_suffix(:minute), do: "m"
  defp timeframe_unit_suffix(:hour), do: "h"
  defp timeframe_unit_suffix(:day), do: "d"
  defp timeframe_unit_suffix(:week), do: "w"
  defp timeframe_unit_suffix(:month), do: "mo"
  defp timeframe_unit_suffix(:quarter), do: "q"
  defp timeframe_unit_suffix(:year), do: "y"
  defp timeframe_unit_suffix(_), do: ""

  defp normalize_granularity(value, available, fallback) do
    cond do
      is_binary(value) and value in available ->
        value

      is_binary(fallback) and fallback in available ->
        fallback

      available != [] ->
        hd(available)

      true ->
        value
    end
  end

  defp source_stats_config(nil) do
    Configuration.configure(
      nil,
      time_zone: "UTC",
      time_zone_database: Tzdata.TimeZoneDatabase,
      beginning_of_week: :monday,
      track_granularities: @default_granularities
    )
  end

  defp source_stats_config(source), do: StatsSource.stats_config(source)

  defp available_granularity_options(nil), do: @default_granularities

  defp available_granularity_options(source) do
    case StatsSource.available_granularities(source) do
      list when is_list(list) and list != [] ->
        list

      _ ->
        @default_granularities
    end
  end

  defp monitor_segment_state(%Monitor{type: :report, dashboard: %Ecto.Association.NotLoaded{}}),
    do: {%{}, []}

  defp monitor_segment_state(%Monitor{type: :report, dashboard: nil}), do: {%{}, []}

  defp monitor_segment_state(%Monitor{type: :report, dashboard: dashboard} = monitor) do
    segments =
      dashboard
      |> Map.get(:segments)
      |> case do
        nil -> Map.get(dashboard, "segments")
        value -> value
      end
      |> case do
        list when is_list(list) -> list
        _ -> []
      end

    overrides = monitor.segment_values || %{}
    DashboardSegments.compute_state(segments, overrides, %{})
  end

  defp monitor_segment_state(_), do: {%{}, []}

  defp resolve_monitor_key(
         %Monitor{type: :report, dashboard: %{key: key}},
         segment_values,
         segments
       ) do
    DashboardSegments.resolve_key(key, segments, segment_values)
  end

  defp resolve_monitor_key(%Monitor{type: :alert} = monitor, _segment_values, _segments) do
    monitor.alert_metric_key
  end

  defp resolve_monitor_key(_monitor, _segment_values, _segments), do: nil

  defp resolve_monitor_source(sources, monitor) do
    case monitor_source_tuple(monitor) do
      {:ok, type, id} -> StatsSource.find_in_list(sources, type, id)
      _ -> nil
    end
  end

  defp ensure_source_in_list(sources, source) do
    cond do
      is_nil(source) ->
        sources

      Enum.any?(sources, &source_same?(&1, source)) ->
        sources

      true ->
        (sources ++ [source])
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(fn s ->
          {source_sort_key(StatsSource.type(s)), String.downcase(StatsSource.display_name(s))}
        end)
    end
  end

  defp source_same?(a, b) do
    StatsSource.type(a) == StatsSource.type(b) &&
      to_string(StatsSource.id(a)) == to_string(StatsSource.id(b))
  end

  defp source_sort_key(:database), do: 0
  defp source_sort_key(:project), do: 1
  defp source_sort_key(_other), do: 2

  defp component_source_ref(nil), do: nil

  defp component_source_ref(source) do
    %{type: StatsSource.type(source), id: to_string(StatsSource.id(source))}
  end

  defp default_transponder_results do
    %{successful: [], failed: [], errors: []}
  end

  defp normalize_transponder_results(results) when is_map(results) do
    successful =
      results
      |> Map.get(:successful, Map.get(results, "successful"))
      |> List.wrap()

    failed =
      results
      |> Map.get(:failed, Map.get(results, "failed"))
      |> List.wrap()

    errors =
      results
      |> Map.get(:errors, Map.get(results, "errors"))
      |> List.wrap()

    %{
      successful: successful,
      failed: failed,
      errors: errors
    }
  end

  defp normalize_transponder_results(_), do: default_transponder_results()

  defp load_monitor_data(socket) do
    cond do
      !monitor_has_key?(socket) ->
        socket

      is_nil(socket.assigns[:source]) ->
        socket

      is_nil(socket.assigns[:from]) or is_nil(socket.assigns[:to]) ->
        socket

      is_nil(socket.assigns[:granularity]) ->
        socket

      true ->
        source = socket.assigns.source
        key = socket.assigns.resolved_key || ""
        granularity = socket.assigns.granularity
        from = socket.assigns.from
        to = socket.assigns.to
        liveview_pid = self()

        socket =
          socket
          |> assign(:load_start_time, System.monotonic_time(:microsecond))
          |> assign(:loading, true)
          |> assign(:loading_progress, nil)
          |> assign(:transponding, false)

        start_async(socket, :monitor_data_task, fn ->
          progress_callback = fn
            {:chunk_progress, current, total} ->
              send(liveview_pid, {:loading_progress, %{current: current, total: total}})

            {:transponder_progress, :starting} ->
              send(liveview_pid, {:transponding, true})

            {:transponder_progress, :finished} ->
              send(liveview_pid, {:transponding, false})

            _ ->
              :ok
          end

          case StatsSource.fetch_series(
                 source,
                 key,
                 from,
                 to,
                 granularity,
                 progress_callback: progress_callback
               ) do
            {:ok, result} -> result
            {:error, error} -> {:error, error}
          end
        end)
    end
  end

  defp monitor_has_key?(socket) do
    key = socket.assigns[:resolved_key]
    is_binary(key) && String.trim(key) != ""
  end

  defp status_label(:active), do: "enabled"
  defp status_label(:paused), do: "paused"
  defp status_label(_), do: "updated"

  defp monitor_source_label(%Monitor{} = monitor, sources) do
    with {:ok, type, id} <- monitor_source_tuple(monitor),
         %StatsSource{} = source <- StatsSource.find_in_list(sources, type, id) do
      "#{source_type_label(type)} · #{StatsSource.display_name(source)}"
    else
      {:error, :missing} ->
        "Not set"

      _ ->
        case monitor_source_tuple(monitor) do
          {:ok, type, _} -> source_type_label(type)
          _ -> "Unknown"
        end
    end
  end

  defp monitor_source_tuple(%Monitor{source_type: type, source_id: id})
       when not is_nil(type) and not is_nil(id) do
    {:ok, type, id}
  end

  defp monitor_source_tuple(_), do: {:error, :missing}

  defp source_type_label(:database), do: "Database"
  defp source_type_label(:project), do: "Project"

  defp source_type_label(value) when is_atom(value) do
    value |> Atom.to_string() |> String.capitalize()
  end

  defp source_type_label(value), do: to_string(value)

  defp monitor_icon(assigns) do
    ~H"""
    <span class={[
      "inline-flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-xl text-white shadow-sm ring-1 ring-inset ring-black/10 dark:ring-white/10",
      Monitor.icon_color_class(@monitor)
    ]}>
      <%= if @monitor.type == :report do %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="h-7 w-7"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25M9 16.5v.75m3-3v3M15 12v5.25m-4.5-15H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z"
          />
        </svg>
      <% else %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="h-7 w-7"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"
          />
        </svg>
      <% end %>
    </span>
    """
  end

  def monitor_summary_stats(assigns) do
    key =
      assigns[:resolved_key] ||
        resolve_monitor_key(
          assigns[:monitor],
          assigns[:segment_values] || %{},
          assigns[:monitor_segments] || []
        )

    cond do
      !is_binary(key) || String.trim(key) == "" ->
        nil

      true ->
        {column_count, path_count} = series_counts(assigns[:stats])

        transponder_results =
          assigns[:transponder_results]
          |> normalize_transponder_results()

        successful = length(transponder_results.successful)
        failed = length(transponder_results.failed)

        %{
          key: key,
          column_count: column_count,
          path_count: path_count,
          matching_transponders: successful + failed,
          successful_transponders: successful,
          failed_transponders: failed,
          transponder_errors: transponder_results.errors
        }
    end
  end

  defp series_counts(%Trifle.Stats.Series{series: series_map}) when is_map(series_map) do
    table = Tabler.tabulize(series_map)
    column_count = table[:at] |> List.wrap() |> length()
    path_count = table[:paths] |> List.wrap() |> length()
    {column_count, path_count}
  end

  defp series_counts(_), do: {0, 0}

  defp assign_monitor_widget_datasets(socket, stats) do
    monitor = socket.assigns.monitor

    dashboard =
      case socket.assigns[:insights_dashboard] do
        nil -> build_monitor_insights_dashboard(monitor)
        existing -> existing
      end

    datasets = dataset_maps_for_dashboard(stats, dashboard)
    {datasets, alert_evaluations} = MonitorLayout.inject_alert_overlay(datasets, monitor, stats)

    socket
    |> assign(:insights_dashboard, dashboard)
    |> assign(:insights_kpi_values, datasets.kpi_values)
    |> assign(:insights_kpi_visuals, datasets.kpi_visuals)
    |> assign(:insights_timeseries, datasets.timeseries)
    |> assign(:insights_category, datasets.category)
    |> assign(:insights_table, datasets.table)
    |> assign(:insights_text_widgets, datasets.text)
    |> assign(:insights_list, datasets.list)
    |> assign(:insights_distribution, datasets.distribution)
    |> assign(:alert_evaluations, alert_evaluations)
  end

  defp reset_monitor_widget_datasets(socket) do
    datasets = empty_widget_dataset_maps()

    socket
    |> assign(:insights_kpi_values, datasets.kpi_values)
    |> assign(:insights_kpi_visuals, datasets.kpi_visuals)
    |> assign(:insights_timeseries, datasets.timeseries)
    |> assign(:insights_category, datasets.category)
    |> assign(:insights_table, datasets.table)
    |> assign(:insights_text_widgets, datasets.text)
    |> assign(:insights_list, datasets.list)
    |> assign(:insights_distribution, datasets.distribution)
    |> assign(:alert_evaluations, %{})
  end

  defp empty_widget_dataset_maps do
    %{
      kpi_values: %{},
      kpi_visuals: %{},
      timeseries: %{},
      category: %{},
      table: %{},
      text: %{},
      list: %{},
      distribution: %{}
    }
  end

  defp dataset_maps_for_dashboard(_stats, dashboard) when not is_map(dashboard) do
    empty_widget_dataset_maps()
  end

  defp dataset_maps_for_dashboard(stats, dashboard) do
    stats
    |> WidgetData.datasets_from_dashboard(dashboard)
    |> WidgetData.dataset_maps()
  end

  defp build_monitor_insights_dashboard(%Monitor{type: :report, dashboard: %{} = dashboard}),
    do: dashboard

  defp build_monitor_insights_dashboard(%Monitor{type: :report} = monitor) do
    %{
      id: "#{monitor.id}-report-preview",
      key: nil,
      name: monitor.name,
      payload: %{"grid" => []}
    }
  end

  defp build_monitor_insights_dashboard(%Monitor{type: :alert} = monitor) do
    build_alert_preview_dashboard(monitor)
  end

  defp build_monitor_insights_dashboard(%Monitor{} = monitor) do
    %{
      id: "#{monitor.id}-preview",
      key: nil,
      name: monitor.name,
      payload: %{"grid" => []}
    }
  end

  defp build_alert_preview_dashboard(%Monitor{} = monitor) do
    %{
      id: "#{monitor.id}-alert-preview",
      key: monitor.alert_metric_key,
      name: monitor.name,
      payload: %{"grid" => MonitorLayout.alert_widgets(monitor)}
    }
  end

  defp find_monitor_widget(nil, _id), do: nil

  defp find_monitor_widget(%{payload: payload}, id) when is_map(payload) do
    id = to_string(id)

    payload
    |> Map.get("grid", [])
    |> case do
      [] ->
        payload
        |> Map.get(:grid, [])

      list ->
        list
    end
    |> Enum.find(fn item ->
      widget_id =
        item
        |> Map.get("id") ||
          item
          |> Map.get(:id)

      to_string(widget_id) == id
    end)
  end

  defp find_monitor_widget(_, _id), do: nil

  defp build_monitor_expanded_widget(socket, widget) when is_map(widget) do
    id = widget |> Map.get("id") |> to_string()
    stats = socket.assigns[:stats]
    type = monitor_widget_type(widget)
    title = widget |> Map.get("title", "") |> to_string() |> String.trim()

    base = %{
      widget_id: id,
      title: if(title == "", do: "Untitled Widget", else: title),
      type: type
    }

    cond do
      is_nil(stats) ->
        base

      type == "timeseries" ->
        chart_map =
          case socket.assigns[:insights_timeseries] do
            %{} = timeseries_map -> Map.get(timeseries_map, id)
            _ -> nil
          end
          |> case do
            nil -> Timeseries.dataset(stats, widget)
            existing -> existing
          end

        chart_map
        |> maybe_put_chart(base)

      type == "category" ->
        stats
        |> Category.dataset(widget)
        |> maybe_put_chart(base)

      type == "kpi" ->
        stats
        |> Kpi.dataset(widget)
        |> maybe_put_kpi_data(base)

      type in ["distribution", "heatmap"] ->
        stats
        |> Distribution.datasets([widget])
        |> List.first()
        |> maybe_put_chart(base)

      type == "table" ->
        stats
        |> Table.dataset(widget)
        |> case do
          nil -> base
          table_data -> Map.put(base, :table_data, table_data)
        end

      type == "text" ->
        widget
        |> Text.widget()
        |> case do
          nil -> base
          text_data -> Map.put(base, :text_data, text_data)
        end

      true ->
        base
    end
  end

  defp build_monitor_expanded_widget(_socket, _widget), do: nil

  defp monitor_widget_type(widget) do
    widget
    |> Map.get("type", "kpi")
    |> to_string()
    |> String.downcase()
  end

  defp maybe_put_chart(nil, base), do: base
  defp maybe_put_chart(chart_map, base), do: Map.put(base, :chart_data, chart_map)

  defp maybe_put_kpi_data(nil, base), do: base

  defp maybe_put_kpi_data({value_map, visual_map}, base) do
    base
    |> Map.put(:chart_data, value_map)
    |> Map.put(:visual_data, visual_map)
  end

  defp maybe_refresh_expanded_widget(socket) do
    case socket.assigns[:expanded_widget] do
      %{widget_id: widget_id} ->
        refreshed =
          socket.assigns.insights_dashboard
          |> find_monitor_widget(widget_id)
          |> case do
            nil -> nil
            widget -> build_monitor_expanded_widget(socket, widget)
          end

        assign(socket, :expanded_widget, refreshed)

      _ ->
        socket
    end
  end

  defp assign_monitor_alerts(%{assigns: %{monitor: %Monitor{} = monitor}} = socket) do
    alerts = Monitors.list_alerts(monitor)
    updated_monitor = %{monitor | alerts: alerts}

    socket
    |> assign_monitor(updated_monitor)
    |> assign(:alerts, alerts)
  end

  defp assign_monitor_alerts(socket), do: socket

  defp refresh_monitor_assigns(socket) do
    monitor = load_monitor(socket, socket.assigns.monitor.id)

    socket
    |> assign_monitor(monitor)
    |> initialize_monitor_context()
  end

  defp assign_monitor(socket, %Monitor{} = monitor) do
    membership = socket.assigns[:current_membership]

    {can_manage, can_edit} =
      case membership do
        %OrganizationMembership{} = member ->
          {
            Monitors.can_manage_monitor?(monitor, member),
            Monitors.can_edit_monitor?(monitor, member)
          }

        _ ->
          {false, false}
      end

    socket
    |> assign(:monitor, monitor)
    |> assign(:monitor_owner, monitor.user)
    |> assign(:can_manage_monitor, can_manage)
    |> assign(:can_manage_lock, can_manage)
    |> assign(:can_edit_monitor, can_edit)
  end

  defp assign_monitor(socket, monitor), do: assign(socket, :monitor, monitor)

  defp clear_alert_modal(socket) do
    socket
    |> assign(:alert_modal, nil)
    |> assign(:alert_modal_changeset, nil)
    |> assign(:alert_modal_action, nil)
  end

  defp find_alert(%Monitor{} = monitor, id) do
    id = to_string(id)

    monitor.alerts
    |> List.wrap()
    |> Enum.find(fn
      %Alert{id: alert_id} -> to_string(alert_id) == id
      _ -> false
    end)
  end

  defp find_execution(executions, id) do
    id = to_string(id)

    executions
    |> List.wrap()
    |> Enum.find(fn
      %Execution{id: exec_id} -> to_string(exec_id) == id
      _ -> false
    end)
  end

  defp monitor_owner_label(%{name: name}) when is_binary(name) and name != "" do
    name
  end

  defp monitor_owner_label(%{email: email}) when is_binary(email), do: email
  defp monitor_owner_label(_), do: "Unknown owner"

  defp gravatar_url(email, size) when is_binary(email) do
    trimmed =
      email
      |> String.trim()
      |> String.downcase()

    if trimmed == "" do
      default_gravatar(size)
    else
      hash =
        trimmed
        |> then(fn value -> :crypto.hash(:md5, value) end)
        |> Base.encode16(case: :lower)

      "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=identicon"
    end
  end

  defp gravatar_url(_email, size), do: default_gravatar(size)

  defp default_gravatar(size), do: "https://www.gravatar.com/avatar/?s=#{size}&d=identicon"

  defp monitor_footer_resource(%Monitor{type: :report, dashboard: %{} = dashboard}), do: dashboard
  defp monitor_footer_resource(%Monitor{id: id}), do: %{id: id}
  defp monitor_footer_resource(_), do: %{id: nil}

  defp build_monitor_export_params(assigns) when is_map(assigns) do
    granularity =
      Map.get(assigns, :granularity) ||
        Map.get(assigns, "granularity") || "1h"

    timeframe =
      Map.get(assigns, :smart_timeframe_input) ||
        Map.get(assigns, "smart_timeframe_input") ||
        Map.get(assigns, :timeframe) ||
        Map.get(assigns, "timeframe") || "24h"

    params =
      %{"granularity" => granularity, "timeframe" => timeframe}
      |> maybe_put_formatted("from", Map.get(assigns, :from) || Map.get(assigns, "from"))
      |> maybe_put_formatted("to", Map.get(assigns, :to) || Map.get(assigns, "to"))
      |> maybe_put_segments(Map.get(assigns, :segment_values) || %{})

    case Map.get(assigns, :resolved_key) || Map.get(assigns, "key") do
      key when is_binary(key) and key != "" -> Map.put(params, "key", key)
      _ -> params
    end
  end

  defp maybe_put_formatted(params, _key, nil), do: params

  defp maybe_put_formatted(params, key, %DateTime{} = value) do
    Map.put(params, key, TimeframeParsing.format_for_datetime_input(value))
  end

  defp maybe_put_formatted(params, key, value) do
    Map.put(params, key, value)
  end

  defp maybe_put_segments(params, segments) when is_map(segments) and segments != %{},
    do: Map.put(params, "segments", segments)

  defp maybe_put_segments(params, _), do: params

  defp format_test_delivery_success(:monitor, socket, result) do
    monitor = socket.assigns.monitor
    summary = Map.get(result, :summary, %{})
    successes = summarize_handles(summary[:successes])
    failures = summarize_failures(summary[:failures])
    window = delivery_window_details(socket.assigns)

    base =
      case successes do
        nil -> "Sent preview to configured monitor recipients."
        line -> "Sent #{monitor.name} preview to #{line}."
      end
      |> maybe_append_window(window)

    maybe_append_failures(base, failures)
  end

  defp format_test_delivery_success({:alert, alert_id}, socket, result) do
    monitor = socket.assigns.monitor

    alert_label =
      socket.assigns.alerts
      |> List.wrap()
      |> Enum.find_value(fn
        %Alert{id: id} = alert ->
          if normalize_id(id) == normalize_id(alert_id) do
            MonitorLayout.alert_label(alert) || "Alert"
          else
            nil
          end

        _ ->
          nil
      end) || "Alert"

    summary = Map.get(result, :summary, %{})
    successes = summarize_handles(summary[:successes])
    failures = summarize_failures(summary[:failures])
    window = delivery_window_details(socket.assigns)

    base =
      case successes do
        nil -> "Sent #{monitor.name} · #{alert_label} preview."
        line -> "Sent #{monitor.name} · #{alert_label} preview to #{line}."
      end
      |> maybe_append_window(window)

    maybe_append_failures(base, failures)
  end

  defp format_test_delivery_error({:exit, reason}) do
    "Delivery failed: #{inspect(reason)}"
  end

  defp format_test_delivery_error(reason) when is_binary(reason), do: reason
  defp format_test_delivery_error(reason), do: "Delivery failed: #{inspect(reason)}"

  defp summarize_handles(nil), do: nil
  defp summarize_handles(""), do: nil

  defp summarize_handles(handles) when is_binary(handles) do
    case String.trim(handles) do
      "" -> nil
      value -> value
    end
  end

  defp summarize_handles(handles) when is_list(handles) do
    handles
    |> Enum.reject(&blank?/1)
    |> Enum.join(", ")
    |> summarize_handles()
  end

  defp summarize_handles(_), do: nil

  defp summarize_failures(nil), do: nil
  defp summarize_failures(""), do: nil

  defp summarize_failures(failures) when is_binary(failures) do
    case String.trim(failures) do
      "" -> nil
      value -> value
    end
  end

  defp summarize_failures(failures) when is_list(failures) do
    failures
    |> Enum.reject(&blank?/1)
    |> Enum.join("; ")
    |> summarize_failures()
  end

  defp summarize_failures(_), do: nil

  defp maybe_append_failures(message, nil), do: message
  defp maybe_append_failures(message, failures), do: message <> " Failed for #{failures}."

  defp maybe_append_window(message, nil), do: message
  defp maybe_append_window(message, {:window, value}), do: message <> " (Window: #{value})"
  defp maybe_append_window(message, {:timeframe, value}), do: message <> " (Window: #{value})"

  defp normalize_id(value) when is_binary(value), do: value
  defp normalize_id(value), do: to_string(value)

  defp delivery_window_details(assigns) when is_map(assigns) do
    from = Map.get(assigns, :from)
    to = Map.get(assigns, :to)

    cond do
      match?(%DateTime{}, from) and match?(%DateTime{}, to) ->
        {:window, format_delivery_datetime(from) <> " → " <> format_delivery_datetime(to)}

      is_binary(from) and is_binary(to) and present?(from) and present?(to) ->
        {:window, format_delivery_datetime(from) <> " → " <> format_delivery_datetime(to)}

      timeframe =
          Map.get(assigns, :smart_timeframe_input) ||
            Map.get(assigns, :timeframe) ||
            Map.get(assigns, "timeframe") ->
        if present?(timeframe), do: {:timeframe, timeframe}, else: nil

      true ->
        nil
    end
  end

  defp delivery_window_details(_), do: nil

  defp format_delivery_datetime(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:minute)
    |> Calendar.strftime("%Y-%m-%d %H:%M %Z")
  rescue
    _ -> DateTime.to_iso8601(dt)
  end

  defp format_delivery_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> format_delivery_datetime(dt)
      {:error, _} -> value
    end
  end

  defp format_delivery_datetime(value), do: to_string(value)

  defp monitor_export_filename(prefix, %Monitor{} = monitor, ext) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)

    base =
      [prefix, monitor.name]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&sanitize_filename_component/1)
      |> Enum.join("-")

    if base == "" do
      prefix <> "-" <> ts <> ext
    else
      base <> "-" <> ts <> ext
    end
  end

  defp sanitize_filename_component(value) do
    value
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(value) when is_atom(value), do: blank?(Atom.to_string(value))
  defp blank?(nil), do: true
  defp blank?(_), do: false

  defp present?(value), do: not blank?(value)

  defp value_or_dash(value) do
    cond do
      blank?(value) -> "—"
      is_binary(value) -> String.trim(value)
      true -> to_string(value)
    end
  end

  defp monitor_download_handler(menu_id) when is_binary(menu_id) do
    "(function(el){var m=el.closest('#" <>
      menu_id <>
      "');if(!m)return;var d=m.querySelector('[data-role=download-dropdown]');if(d)d.style.display='none';var b=m.querySelector('[data-role=download-button]');var t=m.querySelector('[data-role=download-text]');if(b){b.disabled=true;b.classList.add('opacity-70','cursor-wait');}if(t){t.textContent='Generating...';}try{var u=new URL(el.href, window.location.origin);if(!u.searchParams.get('download_token')){var token=Date.now()+'-'+Math.random().toString(36).slice(2);window.__downloadToken=token;u.searchParams.set('download_token', token);el.href=u.toString();}}catch(_){} })(this)"
  end

  defp execution_status_class(%Execution{} = execution) do
    status =
      execution.status
      |> case do
        nil -> ""
        value when is_atom(value) -> Atom.to_string(value)
        value when is_binary(value) -> value
        other -> to_string(other)
      end
      |> String.downcase()

    cond do
      status in ["failed", "error", "partial_failure"] ->
        "text-red-600 dark:text-red-300"

      status in ["alerted"] ->
        "text-red-600 dark:text-red-300"

      status in ["suppressed"] ->
        "text-amber-600 dark:text-amber-300"

      status in ["skipped"] ->
        "text-amber-600 dark:text-amber-300"

      status in ["passed", "ok", "success"] ->
        "text-emerald-600 dark:text-emerald-300"

      true ->
        "text-slate-700 dark:text-slate-200"
    end
  end

  defp execution_status_class(_), do: "text-slate-700 dark:text-slate-200"

  defp format_execution_timestamp(%Execution{triggered_at: %DateTime{} = dt}, timezone) do
    target_timezone =
      case timezone do
        value when is_binary(value) ->
          trimmed = String.trim(value)
          if trimmed == "", do: "UTC", else: trimmed

        _ ->
          "UTC"
      end

    with {:ok, shifted} <- DateTime.shift_zone(dt, target_timezone) do
      Calendar.strftime(shifted, "%Y-%m-%d %H:%M:%S %Z")
    else
      _ ->
        dt
        |> DateTime.shift_zone!("UTC")
        |> Calendar.strftime("%Y-%m-%d %H:%M:%S %Z")
    end
  end

  defp format_execution_timestamp(_, _), do: "--"

  defp format_execution_summary(%Execution{} = execution) do
    summary =
      execution.summary
      |> case do
        value when is_binary(value) -> String.trim(value)
        _ -> ""
      end

    cond do
      summary != "" ->
        summary

      is_map(execution.details) ->
        execution.details
        |> Map.get("summary")
        |> case do
          value when is_binary(value) ->
            trimmed = String.trim(value)
            if trimmed == "", do: "No additional summary captured.", else: trimmed

          _ ->
            "No additional summary captured."
        end

      true ->
        "No additional summary captured."
    end
  end

  defp format_execution_summary(_), do: "No additional summary captured."

  defp pretty_execution_details(details) when is_map(details) or is_list(details) do
    details
    |> Jason.encode_to_iodata!(pretty: true)
    |> IO.iodata_to_binary()
  rescue
    _ ->
      inspect(details, pretty: true, limit: :infinity)
  end

  defp pretty_execution_details(details),
    do: inspect(details || %{}, pretty: true, limit: :infinity)

  defp monitor_timezone(config) do
    timezone =
      cond do
        is_map(config) or is_struct(config) ->
          Map.get(config, :time_zone) || Map.get(config, "time_zone")

        true ->
          nil
      end

    case timezone do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: "UTC", else: trimmed

      _ ->
        "UTC"
    end
  end

  defp alert_summary(%Alert{} = alert, evaluation) do
    stored_summary =
      case alert.last_summary do
        summary when is_binary(summary) -> String.trim(summary)
        _ -> nil
      end

    if present?(stored_summary) do
      stored_summary
    else
      evaluation_summary(evaluation)
    end
  end

  defp alert_summary(_alert, evaluation), do: evaluation_summary(evaluation)

  defp evaluation_summary(nil), do: "Awaiting recent data."

  defp evaluation_summary(%AlertEvaluator.Result{summary: summary})
       when is_binary(summary) and summary != "" do
    summary
  end

  defp evaluation_summary(%AlertEvaluator.Result{triggered?: true}) do
    "Triggered in the latest evaluation window."
  end

  defp evaluation_summary(%AlertEvaluator.Result{triggered?: false}) do
    "No recent breaches detected."
  end

  defp evaluation_summary(%{error: reason}) do
    "Alert evaluation failed: #{format_alert_error(reason)}"
  end

  defp evaluation_summary(_), do: "Awaiting recent data."

  defp format_alert_error(%{message: message}) when is_binary(message), do: message
  defp format_alert_error(reason) when is_binary(reason), do: reason
  defp format_alert_error(reason), do: inspect(reason)

  defp changeset_error_message(%Changeset{} = changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _}} -> "#{Phoenix.Naming.humanize(field)} #{message}" end)
    |> Enum.join(", ")
  end

  defp delete_monitor(socket, %Monitor{} = monitor) do
    membership = socket.assigns.current_membership

    case Monitors.delete_monitor_for_membership(monitor, membership) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Monitor deleted")
         |> redirect(to: ~p"/monitors")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You do not have permission to delete this monitor")}

      {:error, :forbidden} ->
        message =
          if monitor.locked do
            "Monitor is locked. Only the owner or organization admins can delete it."
          else
            "You do not have permission to delete this monitor"
          end

        {:noreply, put_flash(socket, :error, message)}

      {:error, %Changeset{} = changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not delete monitor: #{changeset_error_message(changeset)}"
         )}
    end
  end

  defp delete_monitor(socket, _monitor), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div :if={@monitor} id="monitor-page-root" phx-hook="FileDownload" class="space-y-8">
      <iframe
        name="download_iframe"
        style="display:none"
        aria-hidden="true"
        onload="window.__resetDownloadMenus && window.__resetDownloadMenus(); window.dispatchEvent(new CustomEvent('download:complete'))"
      >
      </iframe>
      <script>
        window.__resetDownloadMenus = window.__resetDownloadMenus || function(){
          try {
            var menus = document.querySelectorAll('[data-download-menu],[data-widget-download-menu]');
            menus.forEach(function(menu){
              var button = menu.querySelector('[data-role=download-button]');
              var label = menu.querySelector('[data-role=download-text]');
              var icon = menu.querySelector('[data-role=download-icon]');
              var spinner = menu.querySelector('[data-role=download-spinner]');
              var defaultLabel = (menu.dataset && menu.dataset.defaultLabel) || 'Download';
              if (button) {
                button.disabled = false;
                button.classList.remove('opacity-70','cursor-wait');
                button.removeAttribute('aria-busy');
                button.removeAttribute('data-loading');
              }
              if (icon) icon.classList.remove('hidden');
              if (spinner) spinner.classList.add('hidden');
              if (label && defaultLabel) {
                label.textContent = defaultLabel;
              }
            });
          } catch (_) {}
        };
        window.__downloadPoller = window.__downloadPoller || setInterval(function(){
          try {
            var m = document.cookie.match(/(?:^|; )download_token=([^;]+)/);
            if (m) {
              document.cookie = 'download_token=; Max-Age=0; path=/';
              if (window.__resetDownloadMenus) window.__resetDownloadMenus();
              window.dispatchEvent(new CustomEvent('download:complete'));
            }
          } catch (e) {}
        }, 500);
      </script>
      <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div class="flex items-start gap-4">
          {monitor_icon(%{monitor: @monitor})}
          <div>
            <h1 class="text-2xl font-semibold text-slate-900 dark:text-white">{@monitor.name}</h1>
            <p class="mt-1 text-sm text-slate-600 dark:text-slate-300">
              <%= if @monitor.type == :report do %>
                Report monitor attached to
                <%= if @monitor.dashboard do %>
                  <.link
                    navigate={~p"/dashboards/#{@monitor.dashboard.id}"}
                    class="font-semibold text-teal-600 hover:text-teal-500"
                  >
                    {@monitor.dashboard.name}
                  </.link>
                <% else %>
                  <span class="font-medium text-slate-500 dark:text-slate-400">
                    unavailable dashboard
                  </span>
                <% end %>
              <% else %>
                Alert monitor watching
                <code class="rounded bg-slate-200/70 px-1.5 py-0.5 text-xs font-semibold text-slate-900 dark:bg-slate-700 dark:text-slate-200">
                  {value_or_dash(@monitor.alert_metric_key)}
                </code>
                at
                <code class="rounded bg-slate-200/70 px-1.5 py-0.5 text-xs font-semibold text-slate-900 dark:bg-slate-700 dark:text-slate-200">
                  {value_or_dash(@monitor.alert_metric_path)}
                </code>
              <% end %>
            </p>
            <p class="mt-1 text-xs text-slate-500 dark:text-slate-400">
              <span class="font-semibold text-slate-600 dark:text-slate-300">Source:</span>
              {monitor_source_label(@monitor, @sources)}
            </p>
            <p :if={@monitor.description} class="mt-2 text-sm text-slate-500 dark:text-slate-300">
              {@monitor.description}
            </p>
          </div>
        </div>
        <div class="flex flex-wrap items-center gap-2 justify-end">
          <.link
            :if={@can_edit_monitor}
            patch={~p"/monitors/#{@monitor.id}/configure"}
            class="inline-flex items-center whitespace-nowrap rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-slate-700 dark:text-white dark:ring-slate-600 dark:hover:bg-slate-600"
          >
            <svg
              class="md:-ml-0.5 md:mr-1.5 h-4 w-4"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z"
              />
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
              />
            </svg>
            <span class="hidden md:inline">Configure</span>
          </.link>
          <button
            type="button"
            class={[
              "inline-flex items-center gap-2 whitespace-nowrap rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-slate-700 dark:text-white dark:ring-slate-600 dark:hover:bg-slate-600",
              match?({:monitor, :running}, @test_delivery_state) && "opacity-80 cursor-wait"
            ]}
            phx-click="test_delivery"
            disabled={match?({:monitor, :running}, @test_delivery_state)}
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="h-4 w-4"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M6 12 3.269 3.125A59.769 59.769 0 0 1 21.485 12 59.768 59.768 0 0 1 3.27 20.875L5.999 12Zm0 0h7.5"
              />
            </svg>
            <span class="hidden md:inline">
              {if match?({:monitor, :running}, @test_delivery_state), do: "Sending…", else: "Send"}
            </span>
            <span class="md:hidden">
              {if match?({:monitor, :running}, @test_delivery_state), do: "Send", else: "Send"}
            </span>
          </button>
          <button
            type="button"
            class="inline-flex items-center gap-2 rounded-md border border-slate-300 dark:border-slate-600 px-3 py-1.5 text-xs font-medium text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700/70"
            phx-click="toggle_status"
          >
            {if @monitor.status == :active, do: "Pause", else: "Resume"}
          </button>
          <div
            :if={@monitor.user || @monitor.locked}
            class="mt-2 flex w-full flex-wrap items-center justify-end gap-2 text-xs text-slate-500 dark:text-slate-400"
          >
            <div :if={@monitor.user} class="flex items-center gap-2">
              <span>Owned by</span>
              <img
                src={gravatar_url(@monitor.user.email, 48)}
                alt="Monitor owner avatar"
                class="h-6 w-6 rounded-full border border-slate-200 dark:border-slate-600"
              />
              <span class="font-semibold text-slate-600 dark:text-slate-200">
                {monitor_owner_label(@monitor.user)}
              </span>
            </div>
            <span
              :if={@monitor.locked}
              class="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2.5 py-0.5 text-[0.7rem] font-semibold text-amber-700 ring-1 ring-inset ring-amber-600/20 dark:bg-amber-500/20 dark:text-amber-200 dark:ring-amber-500/30"
              title="Locked monitors can only be edited by the owner or organization admins."
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="h-3.5 w-3.5"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0V10.5m-.75 11.25h10.5a1.5 1.5 0 0 0 1.5-1.5v-6.75a1.5 1.5 0 0 0-1.5-1.5H6.75a1.5 1.5 0 0 0-1.5 1.5V20.25a1.5 1.5 0 0 0 1.5 1.5Z"
                />
              </svg>
              Locked
            </span>
          </div>
        </div>
      </div>

      <% summary = monitor_summary_stats(assigns) %>

      <.live_component
        module={TrifleApp.Components.FilterBar}
        id="monitor_filter_bar"
        config={@stats_config}
        from={@from}
        to={@to}
        granularity={@granularity}
        smart_timeframe_input={@smart_timeframe_input}
        use_fixed_display={@use_fixed_display}
        range_mode={:inclusive_end}
        clamp_to_now={false}
        available_granularities={@available_granularities}
        show_controls={true}
        show_timeframe_dropdown={false}
        show_granularity_dropdown={false}
        force_granularity_dropdown={false}
        sources={@sources || []}
        selected_source={@selected_source_ref}
        source_locked={true}
      />

      <div class="grid gap-6 lg:grid-cols-3">
        <div class="lg:col-span-2 space-y-4">
          <% export_params = build_monitor_export_params(assigns) %>
          <div class="flex items-center gap-3">
            <h3 class="text-base font-semibold text-slate-900 dark:text-white">
              Monitor insights
            </h3>
          </div>

          <% dashboard_for_render =
            @insights_dashboard ||
              %{payload: %{"grid" => []}}

          grid_items = WidgetView.grid_items(dashboard_for_render)
          report_missing_dashboard? = @monitor.type == :report && is_nil(@monitor.dashboard)

          alert_path_missing? =
            @monitor.type == :alert &&
              blank?(@monitor.alert_metric_path) %>

          <div class="relative">
            <% progress = @loading_progress %>
            <% show_overlay? = progress && progress.total && progress.total > 0 %>

            <%= if show_overlay? do %>
              <% percent = min(progress.current / progress.total * 100, 100.0) %>
              <div class="absolute inset-0 z-40 flex items-center justify-center rounded-lg bg-white/80 dark:bg-slate-900/80">
                <div class="flex flex-col items-center space-y-3">
                  <div class="flex items-center space-x-2">
                    <div class="h-6 w-6 animate-spin rounded-full border-2 border-gray-300 border-t-teal-500 dark:border-slate-600">
                    </div>
                    <span class="text-sm text-gray-600 dark:text-white">
                      Scientificating piece {progress.current} of {progress.total}...
                    </span>
                  </div>
                  <div class="h-2 w-64">
                    <div class="h-2 w-full rounded-full bg-gray-200 dark:bg-slate-600">
                      <div
                        class="h-2 rounded-full bg-teal-500 transition-all duration-300"
                        style={"width: #{Float.round(percent, 1)}%"}
                      >
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>

            <%= cond do %>
              <% report_missing_dashboard? -> %>
                <div class="flex min-h-[12rem] items-center justify-center rounded-lg border border-dashed border-slate-300 bg-slate-50 text-center dark:border-slate-600 dark:bg-slate-900/30">
                  <div class="max-w-sm space-y-2">
                    <p class="text-sm font-semibold text-slate-700 dark:text-slate-200">
                      Dashboard not available
                    </p>
                    <p class="text-xs text-slate-500 dark:text-slate-400">
                      Attach a dashboard to this report monitor to preview its widgets here.
                    </p>
                  </div>
                </div>
              <% alert_path_missing? -> %>
                <div class="flex min-h-[12rem] items-center justify-center rounded-lg border border-dashed border-amber-300 bg-amber-50 text-center dark:border-amber-600/60 dark:bg-amber-900/20">
                  <div class="max-w-sm space-y-2">
                    <p class="text-sm font-semibold text-amber-700 dark:text-amber-200">
                      Metric path required
                    </p>
                    <p class="text-xs text-amber-700/80 dark:text-amber-100/80">
                      Configure a metric key and path for this alert to generate a chart preview.
                    </p>
                  </div>
                </div>
              <% grid_items == [] -> %>
                <div class="flex min-h-[12rem] items-center justify-center rounded-lg border border-dashed border-slate-300 bg-slate-50 text-center dark:border-slate-600 dark:bg-slate-900/30">
                  <div class="max-w-sm space-y-2">
                    <p class="text-sm font-semibold text-slate-700 dark:text-slate-200">
                      No widgets detected
                    </p>
                    <p class="text-xs text-slate-500 dark:text-slate-400">
                      Add at least one widget to the dashboard to populate this preview.
                    </p>
                  </div>
                </div>
              <% true -> %>
                <WidgetView.grid
                  dashboard={dashboard_for_render}
                  stats={@stats}
                  current_user={@current_user}
                  can_edit_dashboard={false}
                  is_public_access={true}
                  print_mode={false}
                  kpi_values={@insights_kpi_values}
                  kpi_visuals={@insights_kpi_visuals}
                  timeseries={@insights_timeseries}
                  category={@insights_category}
                  table={@insights_table}
                  text_widgets={@insights_text_widgets}
                  list={@insights_list}
                  distribution={@insights_distribution}
                  transponder_info={%{}}
                  export_params={export_params}
                  widget_export={%{type: :monitor, monitor_id: @monitor.id}}
                />
            <% end %>
          </div>
        </div>
        <div class="space-y-6">
          <%= if @monitor.type == :report do %>
            <MonitorComponents.report_panel
              monitor={@monitor}
              dashboard={@monitor.dashboard}
              source_label={monitor_source_label(@monitor, @sources)}
            />
          <% else %>
            <MonitorComponents.alert_panel
              monitor={@monitor}
              source_label={monitor_source_label(@monitor, @sources)}
            />
            <div class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-6 shadow-sm">
              <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <h3 class="text-sm font-semibold text-slate-900 dark:text-white">Alerts</h3>
                  <p class="text-xs text-slate-500 dark:text-slate-400">
                    Configure one or more alert strategies for this monitor.
                  </p>
                </div>
                <button
                  :if={@can_edit_monitor}
                  type="button"
                  class="inline-flex items-center gap-1 rounded-md bg-teal-600 px-3 py-1.5 text-xs font-semibold text-white shadow-sm hover:bg-teal-500"
                  phx-click="new_alert"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="h-4 w-4"
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                  </svg>
                  Add alert
                </button>
                <span
                  :if={!@can_edit_monitor && @monitor.locked}
                  class="inline-flex items-center gap-1 rounded-md bg-amber-100 px-2.5 py-1 text-xs font-semibold text-amber-700 ring-1 ring-inset ring-amber-600/20 dark:bg-amber-500/20 dark:text-amber-200 dark:ring-amber-500/30"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="h-4 w-4"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0V10.5m-.75 11.25h10.5a1.5 1.5 0 0 0 1.5-1.5v-6.75a1.5 1.5 0 0 0-1.5-1.5H6.75a1.5 1.5 0 0 0-1.5 1.5V20.25a1.5 1.5 0 0 0 1.5 1.5Z"
                    />
                  </svg>
                  Locked
                </span>
              </div>
              <div class="mt-4">
                <%= if Enum.empty?(@alerts || []) do %>
                  <div class="rounded-lg border border-dashed border-slate-300 bg-slate-50 p-6 text-center dark:border-slate-700 dark:bg-slate-800/60">
                    <p class="text-sm font-medium text-slate-600 dark:text-slate-300">
                      No alerts defined yet.
                    </p>
                    <p class="mt-1 text-xs text-slate-500 dark:text-slate-400">
                      Add an alert to start monitoring this metric.
                    </p>
                  </div>
                <% else %>
                  <ul class="mt-2 space-y-2">
                    <%= for alert <- @alerts do %>
                      <% evaluation = Map.get(@alert_evaluations || %{}, alert.id) %>
                      <% status = alert.status || :passed %>
                      <% status_atom =
                        cond do
                          is_atom(status) ->
                            status

                          is_binary(status) ->
                            try do
                              String.to_existing_atom(status)
                            rescue
                              _ -> :passed
                            end

                          true ->
                            :passed
                        end %>
                      <% triggered? = status_atom == :alerted %>
                      <% suppressed? = status_atom == :suppressed %>
                      <% failed? = status_atom == :failed %>
                      <% alert_key = normalize_id(alert.id) %>
                      <% running_alert? = match?({:alert, ^alert_key, :running}, @test_delivery_state) %>
                      <li class={[
                        "flex items-start justify-between gap-2 rounded-lg border border-slate-200 bg-white px-3 py-2.5 dark:border-slate-700 dark:bg-slate-800",
                        triggered? &&
                          "border-red-500 bg-red-50 dark:border-red-500 dark:bg-red-500/10",
                        suppressed? &&
                          "border-amber-400 bg-amber-50 dark:border-amber-500 dark:bg-amber-500/10",
                        !triggered? && !suppressed? && failed? &&
                          "border-amber-400 bg-amber-50 dark:border-amber-500 dark:bg-amber-500/10"
                      ]}>
                        <div class="min-w-0">
                          <p class="text-sm font-semibold text-slate-900 dark:text-white">
                            {MonitorLayout.alert_label(alert)}
                          </p>
                          <p class={[
                            "mt-1 text-xs text-slate-500 dark:text-slate-400",
                            triggered? && "text-red-700 dark:text-red-300",
                            suppressed? && "text-amber-700 dark:text-amber-300",
                            !triggered? && !suppressed? && failed? &&
                              "text-amber-700 dark:text-amber-300"
                          ]}>
                            {alert_summary(alert, evaluation)}
                          </p>
                        </div>
                        <div class="flex flex-col items-end gap-1">
                          <button
                            :if={@can_edit_monitor}
                            type="button"
                            class="inline-flex items-center gap-1 rounded-md border border-slate-300 dark:border-slate-600 px-2 py-1 text-xs font-medium text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700/60"
                            phx-click="edit_alert"
                            phx-value-id={alert.id}
                          >
                            <svg
                              xmlns="http://www.w3.org/2000/svg"
                              fill="none"
                              viewBox="0 0 24 24"
                              stroke-width="1.5"
                              stroke="currentColor"
                              class="h-4 w-4"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z"
                              />
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z"
                              />
                            </svg>
                            Configure
                          </button>
                          <button
                            type="button"
                            class={[
                              "inline-flex items-center gap-1 rounded-md bg-white px-2 py-1 text-xs font-semibold text-slate-700 shadow-sm ring-1 ring-inset ring-gray-200 hover:bg-gray-50 dark:bg-slate-700 dark:text-white dark:ring-slate-500 dark:hover:bg-slate-600",
                              running_alert? && "opacity-80 cursor-wait"
                            ]}
                            phx-click="test_alert_delivery"
                            phx-value-id={alert.id}
                            disabled={running_alert?}
                          >
                            <svg
                              xmlns="http://www.w3.org/2000/svg"
                              fill="none"
                              viewBox="0 0 24 24"
                              stroke-width="1.5"
                              stroke="currentColor"
                              class="h-4 w-4"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                d="M6 12 3.269 3.125A59.769 59.769 0 0 1 21.485 12 59.768 59.768 0 0 1 3.27 20.875L5.999 12Zm0 0h7.5"
                              />
                            </svg>
                            <span>{if running_alert?, do: "Sending…", else: "Send"}</span>
                          </button>
                        </div>
                      </li>
                    <% end %>
                  </ul>
                <% end %>
              </div>
            </div>
          <% end %>
          <MonitorComponents.trigger_history
            monitor={@monitor}
            executions={@executions}
            timezone={monitor_timezone(@stats_config)}
            show_details_event="show_execution_details"
          />
        </div>
      </div>

      <%= if summary do %>
        <.dashboard_footer
          class="mt-8"
          summary={summary}
          load_duration_microseconds={@load_duration_microseconds}
          show_export_dropdown={@show_export_dropdown}
          dashboard={monitor_footer_resource(@monitor)}
          export_params={export_params}
          download_menu_id="monitor-download-menu"
          show_error_modal={@show_error_modal}
        >
          <:export_menu :let={slot_assigns}>
            <% menu_id = slot_assigns[:download_menu_id] || "monitor-download-menu" %>
            <% params = slot_assigns[:export_params] || %{} %>
            <button
              type="button"
              phx-click="download_monitor_csv"
              data-export-trigger="csv"
              class="w-full text-left px-3 py-2 text-xs text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700 flex items-center"
            >
              <svg
                class="h-4 w-4 mr-2 text-teal-600 dark:text-teal-400"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M12 16.5V3m0 13.5L8.25 12M12 16.5l3.75-4.5M3 21h18"
                />
              </svg>
              CSV (table)
            </button>
            <button
              type="button"
              phx-click="download_monitor_json"
              data-export-trigger="json"
              class="w-full text-left px-3 py-2 text-xs text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700 flex items-center"
            >
              <svg
                class="h-4 w-4 mr-2 text-indigo-600 dark:text-indigo-400"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M12 16.5V3m0 13.5L8.25 12M12 16.5l3.75-4.5M3 21h18"
                />
              </svg>
              JSON (raw)
            </button>
            <a
              data-export-link
              onclick={monitor_download_handler(menu_id)}
              href={~p"/export/monitors/#{@monitor.id}/pdf?#{params}"}
              target="download_iframe"
              class="block px-3 py-2 text-xs text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700 flex items-center"
            >
              <svg
                class="h-4 w-4 mr-2 text-rose-600 dark:text-rose-400"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
                />
              </svg>
              PDF (print)
            </a>
            <a
              data-export-link
              onclick={monitor_download_handler(menu_id)}
              href={~p"/export/monitors/#{@monitor.id}/png?#{Map.put(params, "theme", "light")}"}
              target="download_iframe"
              class="block px-3 py-2 text-xs text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700 flex items-center"
            >
              <svg
                class="h-4 w-4 mr-2 text-amber-600 dark:text-amber-400"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
                />
              </svg>
              PNG (light)
            </a>
            <a
              data-export-link
              onclick={monitor_download_handler(menu_id)}
              href={~p"/export/monitors/#{@monitor.id}/png?#{Map.put(params, "theme", "dark")}"}
              target="download_iframe"
              class="block px-3 py-2 text-xs text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700 flex items-center"
            >
              <svg
                class="h-4 w-4 mr-2 text-amber-600 dark:text-amber-400"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
                />
              </svg>
              PNG (dark)
            </a>
          </:export_menu>
        </.dashboard_footer>
        <TrifleApp.Components.DashboardFooter.transponder_errors_modal
          summary={summary}
          show_error_modal={@show_error_modal}
        />
      <% end %>

      <%= if @expanded_widget do %>
        <.app_modal
          id="monitor-widget-expand-modal"
          show={true}
          size="full"
          on_cancel={JS.push("close_expanded_widget")}
        >
          <:title>
            <div class="flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-3">
              <div class="flex items-center gap-3">
                <span>{@expanded_widget.title}</span>
                <span class="inline-flex items-center rounded-full bg-teal-100/70 dark:bg-teal-900/40 px-3 py-0.5 text-xs font-medium text-teal-700 dark:text-teal-200">
                  {String.capitalize(@expanded_widget.type || "widget")}
                </span>
              </div>
            </div>
          </:title>
          <:body>
            <%= if @expanded_widget.type == "table" do %>
              <% table_data = @expanded_widget[:table_data] %>
              <% aggrid_payload = DataTable.to_aggrid_payload(table_data, %{}) %>
              <div class="h-[80vh] flex flex-col gap-6 overflow-y-auto">
                <div class="flex-1 min-h-[500px] rounded-lg border border-gray-200/80 dark:border-slate-700/60 bg-white dark:bg-slate-900/40 p-4">
                  <%= cond do %>
                    <% is_nil(table_data) -> %>
                      <div class="h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 text-center">
                        Configure this widget with a path to display table data.
                      </div>
                    <% aggrid_payload -> %>
                      <div
                        id={"expanded-aggrid-shell-#{@expanded_widget.widget_id}"}
                        class="aggrid-table-shell flex-1 flex flex-col min-h-0"
                        data-role="aggrid-table"
                        data-theme="light"
                        phx-hook="ExpandedAgGridTable"
                        data-table={Jason.encode!(aggrid_payload)}
                      >
                        <div
                          class="flex-1 min-h-0 ag-theme-alpine"
                          data-role="aggrid-table-root"
                          style="width: 100%; min-height: 400px;"
                        >
                          <div class="h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 px-6 text-center">
                            Loading AG Grid table...
                          </div>
                        </div>
                      </div>
                    <% true -> %>
                      <div class="h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 text-center">
                        {Map.get(table_data || %{}, :empty_message, "No data available yet.")}
                      </div>
                  <% end %>
                </div>
              </div>
            <% else %>
              <div
                id={"expanded-widget-#{@expanded_widget.widget_id}"}
                class="h-[80vh] flex flex-col gap-6 overflow-y-auto"
                phx-hook="ExpandedWidgetView"
                data-type={@expanded_widget.type}
                data-title={@expanded_widget.title}
                data-colors={ChartColors.json_palette()}
                data-chart={
                  if @expanded_widget[:chart_data],
                    do: Jason.encode!(@expanded_widget.chart_data)
                }
                data-visual={
                  if @expanded_widget[:visual_data],
                    do: Jason.encode!(@expanded_widget.visual_data)
                }
                data-text={
                  if @expanded_widget[:text_data],
                    do: Jason.encode!(@expanded_widget.text_data)
                }
              >
                <div class="flex-1 min-h-[500px]">
                  <div class="h-full w-full rounded-lg border border-gray-200/80 dark:border-slate-700/60 bg-white dark:bg-slate-900/40 p-4">
                    <div data-role="chart" class="h-full w-full"></div>
                  </div>
                </div>
                <div class="flex-1 min-h-[300px] rounded-lg border border-gray-200/80 dark:border-slate-700/60 bg-white dark:bg-slate-900/60 overflow-auto">
                  <div data-role="table-root" class="h-full w-full overflow-auto"></div>
                </div>
              </div>
            <% end %>
          </:body>
        </.app_modal>
      <% end %>

      <.app_modal
        :if={@selected_execution}
        id="monitor-execution-details-modal"
        show={!!@selected_execution}
        size="lg"
        on_cancel={JS.push("hide_execution_details")}
      >
        <:title>Trigger details</:title>
        <:body>
          <div class="space-y-4">
            <div class="rounded-lg border border-slate-200 bg-slate-50 p-4 text-sm text-slate-700 dark:border-slate-600 dark:bg-slate-800/50 dark:text-slate-200">
              <dl class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <div>
                  <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
                    Status
                  </dt>
                  <dd class={[
                    "mt-1 font-semibold",
                    execution_status_class(@selected_execution)
                  ]}>
                    {String.upcase(@selected_execution.status || "unknown")}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
                    Triggered at
                  </dt>
                  <dd class="mt-1">
                    {format_execution_timestamp(@selected_execution, monitor_timezone(@stats_config))}
                  </dd>
                </div>
                <div class="sm:col-span-2">
                  <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
                    Summary
                  </dt>
                  <dd class="mt-1">
                    {format_execution_summary(@selected_execution)}
                  </dd>
                </div>
              </dl>
            </div>
            <div>
              <h4 class="text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
                Payload
              </h4>
              <div class="mt-2 rounded-lg border border-slate-200 bg-slate-50 p-3 text-xs leading-relaxed text-slate-700 dark:border-slate-700 dark:bg-slate-900/60 dark:text-slate-200">
                <pre class="max-h-[320px] overflow-auto whitespace-pre-wrap">
    {pretty_execution_details(@selected_execution.details)}
                </pre>
              </div>
            </div>
          </div>
        </:body>
        <:footer>
          <button
            type="button"
            class="inline-flex items-center rounded-md border border-slate-300 bg-white px-3 py-1.5 text-sm font-medium text-slate-700 shadow-sm transition hover:bg-slate-100 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
            phx-click="hide_execution_details"
          >
            Close
          </button>
        </:footer>
      </.app_modal>

      <.live_component
        :if={@alert_modal}
        module={MonitorAlertFormComponent}
        id={"monitor-alert-form-#{@monitor.id}"}
        monitor={@monitor}
        alert={@alert_modal}
        action={@alert_modal_action}
        changeset={@alert_modal_changeset}
        current_membership={@current_membership}
      />

      <.live_component
        :if={@live_action == :configure}
        module={FormComponent}
        id="monitor-settings-form"
        monitor={@modal_monitor || @monitor}
        changeset={@modal_changeset}
        dashboards={@dashboards}
        sources={@sources}
        current_user={@current_user}
        current_membership={@current_membership}
        delivery_options={@delivery_options}
        can_manage_lock={@can_manage_lock}
        action={:edit}
        patch={~p"/monitors/#{@monitor.id}"}
        title="Configure monitor"
      />
    </div>
    """
  end
end
