defmodule TrifleApp.MonitorLive do
  use TrifleApp, :live_view

  alias Ecto.Changeset
  alias Trifle.Monitors
  alias Trifle.Monitors.Monitor
  alias Trifle.Organizations
  alias Trifle.Stats.Configuration
  alias Trifle.Stats.Nocturnal
  alias Trifle.Stats.Nocturnal.Parser
  alias Trifle.Stats.Source, as: StatsSource
  alias Trifle.Stats.Tabler
  alias TrifleApp.MonitorComponents
  alias TrifleApp.MonitorsLive.FormComponent
  alias TrifleApp.TimeframeParsing
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
     |> assign(:show_export_dropdown, false)
     |> assign(:show_error_modal, false)}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    monitor = load_monitor(socket, id)

    socket =
      socket
      |> assign(:monitor, monitor)
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

    socket
    |> assign(:modal_monitor, monitor)
    |> assign(:modal_changeset, changeset)
    |> assign(:page_title, "Configure · #{monitor.name}")
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

  def handle_event("toggle_status", _params, socket) do
    %{monitor: monitor, current_membership: membership} = socket.assigns
    next_status = if monitor.status == :active, do: :paused, else: :active

    case Monitors.update_monitor_for_membership(monitor, membership, %{status: next_status}) do
      {:ok, updated} ->
        refreshed = load_monitor(socket, updated.id)

        {:noreply,
         socket
         |> put_flash(:info, "Monitor #{status_label(updated.status)}")
         |> assign(:monitor, refreshed)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You do not have permission to update this monitor")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error_message(changeset))}
    end
  end

  @impl true
  def handle_info({FormComponent, {:saved, monitor}}, socket) do
    refreshed = load_monitor(socket, monitor.id)
    membership = socket.assigns.current_membership

    {:noreply,
     socket
     |> put_flash(:info, "Monitor updated")
     |> assign(:monitor, refreshed)
     |> assign(:executions, Monitors.list_recent_executions(refreshed))
     |> assign(:sources, load_sources(membership))
     |> assign(:delivery_options, Monitors.delivery_options_for_membership(membership))
     |> push_patch(to: ~p"/monitors/#{monitor.id}")}
  end

  def handle_info({FormComponent, {:delete, monitor}}, socket) do
    delete_monitor(socket, monitor)
  end

  def handle_info({FormComponent, {:error, message}}, socket) do
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

    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:loading_progress, nil)
     |> assign(:transponding, false)
     |> assign(:stats, stats)
     |> assign(:transponder_results, transponder_results)
     |> assign(:load_duration_microseconds, load_duration)}
  end

  @impl true
  def handle_async(:monitor_data_task, {:error, error}, socket) do
    load_duration =
      case socket.assigns[:load_start_time] do
        nil -> nil
        started -> System.monotonic_time(:microsecond) - started
      end

    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:loading_progress, nil)
     |> assign(:transponding, false)
     |> assign(:stats, nil)
     |> assign(:transponder_results, default_transponder_results())
     |> assign(:load_duration_microseconds, load_duration)
     |> put_flash(:error, "Failed to load monitor data: #{inspect(error)}")}
  end

  @impl true
  def handle_async(:monitor_data_task, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:loading_progress, nil)
     |> assign(:transponding, false)
     |> assign(:stats, nil)
     |> assign(:transponder_results, default_transponder_results())
     |> put_flash(:error, "Monitor data task crashed: #{inspect(reason)}")}
  end

  defp load_monitor(socket, id) do
    membership = socket.assigns.current_membership
    Monitors.get_monitor_for_membership!(membership, id, preload: [:dashboard])
  end

  defp build_page_title(:configure, monitor), do: "Configure · #{monitor.name}"
  defp build_page_title(_action, monitor), do: "#{monitor.name} · Monitor"

  defp load_dashboards(user, membership) do
    Organizations.list_dashboards_for_membership(user, membership)
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

    resolved_key = resolve_monitor_key(monitor)

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
    |> assign(:selected_source_ref, component_source_ref(source))
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

    socket
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
        case compute_report_time_range(monitor, timeframe_input, config) do
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

  defp compute_report_time_range(%Monitor{} = monitor, timeframe_input, config) do
    settings = monitor.report_settings || %{}
    frequency = Map.get(settings, :frequency)
    now = timezone_now(config)

    cond do
      frequency == :daily ->
        from = floor_time(now, 1, :day, config)
        {:ok, from, now}

      frequency == :weekly ->
        from = floor_time(now, 1, :week, config)
        {:ok, from, now}

      frequency == :monthly ->
        from = floor_time(now, 1, :month, config)
        {:ok, from, now}

      true ->
        parse_timeframe_range(timeframe_input, config)
    end
  end

  defp parse_timeframe_range(timeframe_input, config) do
    case TimeframeParsing.parse_smart_timeframe(timeframe_input || "24h", config) do
      {:ok, from, to, _smart, _fixed} -> {:ok, from, to}
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

  defp monitor_timeframe_defaults(%Monitor{type: :report} = monitor, source, config, granularities) do
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
    timeframe_input = resolve_report_timeframe(settings.timeframe, frequency, source)

    {from, to} =
      case compute_report_time_range(monitor, timeframe_input, config) do
        {:ok, from, to} -> {from, to}
        :error ->
          case parse_timeframe_range("24h", config) do
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

    {from, to, granularity, timeframe_input, false}
  end

  defp resolve_report_timeframe(timeframe, frequency, source) do
    cond do
      is_binary(timeframe) and String.trim(timeframe) != "" ->
        timeframe

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
    settings = monitor.alert_settings || %{}
    evaluation_timeframe = settings.timeframe || StatsSource.default_timeframe(source) || "1h"
    display_timeframe = multiply_timeframe(evaluation_timeframe, 4)

    {from, to} =
      case parse_timeframe_range(display_timeframe, config) do
        {:ok, from, to} -> {from, to}
        :error ->
          case parse_timeframe_range("24h", config) do
            {:ok, fallback_from, fallback_to} -> {fallback_from, fallback_to}
            :error -> {nil, nil}
          end
      end

    fallback_granularity =
      settings.granularity ||
        case source do
          nil -> nil
          src -> StatsSource.default_granularity(src)
        end

    granularity = normalize_granularity(settings.granularity, granularities, fallback_granularity)
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

  defp resolve_monitor_key(%Monitor{type: :report, dashboard: %{key: key}}), do: key

  defp resolve_monitor_key(%Monitor{type: :alert, alert_settings: settings}) do
    settings && settings.metric_key
  end

  defp resolve_monitor_key(_), do: nil

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
      "inline-flex h-12 w-12 items-center justify-center rounded-xl text-white shadow-sm ring-1 ring-inset ring-black/10 dark:ring-white/10",
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
    key = assigns[:resolved_key] || resolve_monitor_key(assigns[:monitor])

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

  defp monitor_footer_resource(%Monitor{type: :report, dashboard: %{} = dashboard}), do: dashboard
  defp monitor_footer_resource(%Monitor{id: id}), do: %{id: id}
  defp monitor_footer_resource(_), do: %{id: nil}

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
    <div :if={@monitor} class="space-y-8">
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
                  {(@monitor.alert_settings && @monitor.alert_settings.metric_key) || "—"}
                </code>
                at
                <code class="rounded bg-slate-200/70 px-1.5 py-0.5 text-xs font-semibold text-slate-900 dark:bg-slate-700 dark:text-slate-200">
                  {(@monitor.alert_settings && @monitor.alert_settings.metric_path) || "—"}
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
        <div class="flex flex-wrap items-center gap-2">
          <.link
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
            class="inline-flex items-center gap-2 rounded-md border border-slate-300 dark:border-slate-600 px-3 py-1.5 text-xs font-medium text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700/70"
            phx-click="toggle_status"
          >
            {if @monitor.status == :active, do: "Pause", else: "Resume"}
          </button>
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
        <div class="lg:col-span-2">
          <div class="flex h-full min-h-[16rem] items-center justify-center rounded-xl border border-dashed border-slate-300 bg-slate-50 text-center dark:border-slate-700 dark:bg-slate-800/40">
            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
                Monitor insights
              </h3>
              <p class="mt-2 text-xs text-slate-500 dark:text-slate-400">
                Additional visualizations and summaries will appear here soon.
              </p>
            </div>
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
          <% end %>
          <MonitorComponents.trigger_history monitor={@monitor} executions={@executions} />
        </div>
      </div>

      <%= if summary do %>
        <.dashboard_footer
          class="mt-8"
          summary={summary}
          load_duration_microseconds={@load_duration_microseconds}
          show_export_dropdown={false}
          dashboard={monitor_footer_resource(@monitor)}
          export_params={%{}}
          export_menu?={false}
        />
      <% end %>

      <%= if @show_error_modal && summary && length(summary.transponder_errors) > 0 do %>
        <div class="fixed inset-0 z-50 overflow-y-auto" phx-click="hide_transponder_errors">
          <div class="flex items-center justify-center min-h-screen px-4 pt-4 pb-20 text-center sm:block sm:p-0">
            <div class="fixed inset-0 transition-opacity bg-gray-500 bg-opacity-75 dark:bg-gray-900 dark:bg-opacity-75"></div>

            <div
              class="inline-block align-bottom bg-white dark:bg-slate-800 rounded-lg px-4 pt-5 pb-4 text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-3xl sm:w-full sm:p-6"
              phx-click-away="hide_transponder_errors"
            >
              <div class="sm:flex sm:items-start">
                <div class="mx-auto flex-shrink-0 flex items-center justify-center h-12 w-12 rounded-full bg-red-100 dark:bg-red-900/30 sm:mx-0 sm:h-10 sm:w-10">
                  <svg
                    class="h-6 w-6 text-red-600 dark:text-red-400"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.664-.833-2.464 0L3.34 16.5c-.77.833.192 2.5 1.732 2.5z"
                    />
                  </svg>
                </div>
                <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left w-full">
                  <h3 class="text-lg leading-6 font-medium text-gray-900 dark:text-white">
                    Transponder Errors
                  </h3>
                  <div class="mt-4">
                    <div class="space-y-4">
                      <%= for error <- summary.transponder_errors do %>
                        <div class="border border-red-200 dark:border-red-800 rounded-lg p-4 bg-red-50 dark:bg-red-900/20">
                          <div class="flex items-center justify-between mb-2">
                            <h4 class="font-medium text-red-800 dark:text-red-300">
                              {(error.transponder && (error.transponder.name || error.transponder.key)) || "Transponder"}
                            </h4>
                            <span class="text-xs text-slate-500 dark:text-slate-400">
                              {error.transponder && error.transponder.key}
                            </span>
                          </div>
                          <p class="text-sm text-red-700 dark:text-red-200">
                            {error.message || "Error executing transponder"}
                          </p>
                          <%= if error.details do %>
                            <pre class="mt-2 rounded bg-slate-900/5 dark:bg-slate-900/60 p-3 text-xs text-slate-700 dark:text-slate-200 overflow-x-auto">
{inspect(error.details, pretty: true)}
                            </pre>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                  <div class="mt-5 sm:mt-6 sm:flex sm:flex-row-reverse">
                    <button
                      type="button"
                      class="inline-flex w-full justify-center rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500 sm:ml-3 sm:w-auto"
                      phx-click="hide_transponder_errors"
                    >
                      Close
                    </button>
                    <button
                      type="button"
                      class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-slate-700 dark:text-slate-200 dark:ring-slate-600 dark:hover:bg-slate-600 sm:mt-0 sm:w-auto"
                      phx-click="hide_transponder_errors"
                    >
                      Dismiss
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      <% end %>

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
        action={:edit}
        patch={~p"/monitors/#{@monitor.id}"}
        title="Configure monitor"
      />
    </div>
    """
  end
end
