defmodule TrifleApp.DatabaseExploreLive do
  use TrifleApp, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  alias TrifleApp.DesignSystem.ChartColors

  def mount(params, _session, socket) do
    database = Organizations.get_database!(params["id"])

    socket =
      socket
      |> assign(page_title: ["Explore", database.display_name])
      |> assign(database: database)
      |> assign(stats: nil)
      |> assign(timeline: "[]")
      |> assign(chart_type: "stacked")
      |> assign(keys: %{})
      |> assign(selected_key_color: nil)
      |> assign(smart_timeframe_input: nil)
      |> assign(key_search_filter: "")
      |> assign(loading: false)
      |> assign(loading_chunks: false)
      |> assign(loading_progress: nil)
      |> assign(show_timeframe_dropdown: false)
      |> assign(show_sensitivity_dropdown: false)

    {:ok, socket}
  end

  def parse_date(date, time_zone) do
    case NaiveDateTime.from_iso8601(date) do
      {:ok, naive} -> {:ok, DateTime.from_naive!(naive, time_zone)}
      {:error, reason} -> {:error, reason}
    end
  end

  def format_for_datetime_input(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_iso8601()
  end

  def format_timeframe_display(from, to) do
    from_date = from |> DateTime.to_date() |> Date.to_string()
    to_date = to |> DateTime.to_date() |> Date.to_string()
    from_time = DateTime.to_time(from) |> Time.truncate(:second) |> Time.to_string()
    to_time = DateTime.to_time(to) |> Time.truncate(:second) |> Time.to_string()

    if from_date == to_date do
      # Same date: show "2025-08-20 09:17:08 - 13:17:08"
      "#{from_date} #{from_time} - #{to_time}"
    else
      # Different dates: show "2025-08-20 09:17:08 - 2025-08-21 13:17:08"
      "#{from_date} #{from_time} - #{to_date} #{to_time}"
    end
  end

  def format_smart_timeframe_display(smart_input, config) when is_nil(smart_input), do: ""

  def format_smart_timeframe_display(smart_input, config, use_fixed_times \\ false, fixed_from \\ nil, fixed_to \\ nil)

  def format_smart_timeframe_display(smart_input, config, true, fixed_from, fixed_to)
      when not is_nil(fixed_from) and not is_nil(fixed_to) do
    # Use the fixed timestamps when explicitly requested (e.g., on page reload)
    format_timeframe_display(fixed_from, fixed_to)
  end

  def format_smart_timeframe_display(smart_input, config, _, _, _) do
    # Show the actual timeframe without the shorthand (badge displays the shorthand separately)
    case parse_smart_timeframe(smart_input, config) do
      {:ok, from, to} ->
        format_timeframe_display(from, to)

      {:error, _reason} ->
        # Fallback for invalid inputs
        smart_input
    end
  end

  def get_smart_timeframe_description(smart_input) when is_nil(smart_input), do: ""

  def get_smart_timeframe_description(smart_input) do
    # This is used for dropdown options - keep as "Last X" format
    generate_description_from_shorthand(smart_input)
  end

  def get_timeframe_dropdown_options do
    # Keep dropdown options as "Last X" labels - these are accurate for dropdown selection
    [
      {"5m", "Last 5 minutes"},
      {"15m", "Last 15 minutes"},
      {"30m", "Last 30 minutes"},
      {"1h", "Last 1 hour"},
      {"4h", "Last 4 hours"},
      {"1d", "Last 1 day"},
      {"2d", "Last 2 days"},
      {"1w", "Last 1 week"},
      {"1mo", "Last 1 month"}
    ]
  end

  def generate_description_from_shorthand(input) do
    # Generate "Last X" description for dropdown options
    case input do
      "5m" -> "Last 5 minutes"
      "15m" -> "Last 15 minutes"
      "30m" -> "Last 30 minutes"
      "1h" -> "Last 1 hour"
      "4h" -> "Last 4 hours"
      # Convert 24h to day for backward compatibility
      "24h" -> "Last 1 day"
      "1d" -> "Last 1 day"
      "2d" -> "Last 2 days"
      "1w" -> "Last 1 week"
      "1mo" -> "Last 1 month"
      # Fallback to raw input
      _ -> input
    end
  end

  def find_short_code_from_description(input) do
    # Build a reverse map from timeframe descriptions to short codes
    dropdown_options = get_timeframe_dropdown_options()

    preset_map =
      Enum.into(dropdown_options, %{}, fn {short_code, description} ->
        {description, short_code}
      end)

    preset_map[input]
  end

  def extract_short_value_from_display(display_text) do
    # Extract short value from the end of the display text (e.g., "2025-08-20 01:42:13 - 02:42:13 1h" -> "1h")
    case Regex.run(~r/(\d+(?:mo|[smhdwy]))\s*$/, display_text) do
      [_, short_value] -> short_value
      _ -> display_text
    end
  end

  def get_timezone_offset_display(time_zone) do
    case DateTime.now(time_zone, Tzdata.TimeZoneDatabase) do
      {:ok, tz_time} ->
        offset_seconds = tz_time.utc_offset + tz_time.std_offset
        offset_hours = div(offset_seconds, 3600)
        offset_minutes = div(rem(abs(offset_seconds), 3600), 60)

        sign = if offset_seconds >= 0, do: "+", else: "-"

        "#{sign}#{String.pad_leading(to_string(abs(offset_hours)), 2, "0")}:#{String.pad_leading(to_string(offset_minutes), 2, "0")}"

      {:error, _} ->
        "+00:00"
    end
  end

  def parse_smart_timeframe(input, config) do
    # Use Trifle.Stats.Nocturnal.Parser for consistent parsing
    try do
      parser = Trifle.Stats.Nocturnal.Parser.new(input)

      if Trifle.Stats.Nocturnal.Parser.valid?(parser) do
        # Get current time in the database's timezone
        to = DateTime.utc_now() |> DateTime.shift_zone!(config.time_zone)

        # Create nocturnal instance and subtract the offset to get "from" time
        nocturnal = Trifle.Stats.Nocturnal.new(to, config)

        # Calculate from time by subtracting the offset
        from =
          case Trifle.Stats.Nocturnal.add(nocturnal, -parser.offset, parser.unit) do
            from_datetime when is_struct(from_datetime, DateTime) -> from_datetime
            _ -> raise "Failed to calculate from time"
          end

        {:ok, from, to}
      else
        {:error, "Invalid format. Use formats like: 1s, 5m, 2h, 1d, 3w, 6mo, 1q, 1y"}
      end
    rescue
      _ -> {:error, "Invalid format. Use formats like: 1s, 5m, 2h, 1d, 3w, 6mo, 1q, 1y"}
    end
  end

  def handle_event("fetch", params, socket) do
    granularity = params["granularity"]

    case {parse_date(params["from"], "UTC"), parse_date(params["to"], "UTC")} do
      {{:ok, from}, {:ok, to}} ->
        socket =
          socket
          |> assign(granularity: granularity, from: from, to: to)
          |> assign(smart_timeframe_input: nil)
          |> push_patch(
            to:
              ~p"/app/explore/#{socket.assigns.database.id}?#{[granularity: granularity, from: format_for_datetime_input(from), to: format_for_datetime_input(to), key: socket.assigns.key]}"
          )

        {:noreply, socket}

      _ ->
        # If parsing fails, don't update
        {:noreply, socket}
    end
  end

  def handle_event("show_timeframe_dropdown", _, socket) do
    {:noreply, assign(socket, show_timeframe_dropdown: true)}
  end

  def handle_event("hide_timeframe_dropdown", _, socket) do
    {:noreply, assign(socket, show_timeframe_dropdown: false)}
  end

  def handle_event("delayed_hide_timeframe_dropdown", _, socket) do
    Process.send_after(self(), :hide_dropdown_after_delay, 150)
    {:noreply, socket}
  end

  def handle_event("select_timeframe_preset", %{"preset" => preset, "label" => _label}, socket) do
    config = Database.stats_config(socket.assigns.database)
    case parse_smart_timeframe(preset, config) do
      {:ok, from, to} ->
        granularity = socket.assigns.granularity

        socket =
          socket
          |> assign(from: from, to: to)
          |> assign(smart_timeframe_input: preset)
          |> assign(use_fixed_display: false)
          |> assign(loading: true)
          |> assign(show_timeframe_dropdown: false)
          |> push_event("update_smart_timeframe_input", %{
            value: format_smart_timeframe_display(preset, config)
          })
          |> push_patch(
            to:
              ~p"/app/explore/#{socket.assigns.database.id}?#{[granularity: granularity, from: format_for_datetime_input(from), to: format_for_datetime_input(to), key: socket.assigns[:key] || "", timeframe: preset]}"
          )

        {:noreply, socket}

      {:error, _} ->
        {:noreply, assign(socket, show_timeframe_dropdown: false)}
    end
  end

  def handle_event("smart_timeframe_keydown", %{"key" => "Enter", "value" => input}, socket) do
    short_input =
      case find_short_code_from_description(input) do
        nil -> input
        short_code -> short_code
      end

    config = Database.stats_config(socket.assigns.database)
    case parse_smart_timeframe(short_input, config) do
      {:ok, from, to} ->
        granularity = socket.assigns.granularity

        socket =
          socket
          |> assign(from: from, to: to)
          |> assign(smart_timeframe_input: short_input)
          |> assign(use_fixed_display: false)
          |> assign(loading: true)
          |> assign(show_timeframe_dropdown: false)
          |> push_event("update_smart_timeframe_input", %{
            value: format_smart_timeframe_display(short_input, config)
          })
          |> push_patch(
            to:
              ~p"/app/explore/#{socket.assigns.database.id}?#{[granularity: granularity, from: format_for_datetime_input(from), to: format_for_datetime_input(to), key: socket.assigns[:key] || "", timeframe: short_input]}"
          )

        {:noreply, socket}

      {:error, _} ->
        {:noreply, assign(socket, show_timeframe_dropdown: false)}
    end
  end

  def handle_event("smart_timeframe_keydown", _, socket) do
    {:noreply, socket}
  end

  def handle_event("filter_keys", %{"value" => filter}, socket) do
    {:noreply, assign(socket, key_search_filter: filter)}
  end

  def handle_event("select_granularity", %{"granularity" => granularity}, socket) do
    socket =
      socket
      |> assign(granularity: granularity)
      |> assign(loading: true)
      |> push_patch(
        to:
          ~p"/app/explore/#{socket.assigns.database.id}?#{[granularity: granularity, from: format_for_datetime_input(socket.assigns.from), to: format_for_datetime_input(socket.assigns.to), key: socket.assigns[:key] || "", timeframe: socket.assigns[:smart_timeframe_input]]}"
      )

    {:noreply, socket}
  end

  def handle_event("select_key", %{"key" => key}, socket) do
    socket =
      socket
      |> assign(loading: true)
      |> push_patch(
        to:
          ~p"/app/explore/#{socket.assigns.database.id}?#{[granularity: socket.assigns.granularity, from: format_for_datetime_input(socket.assigns.from), to: format_for_datetime_input(socket.assigns.to), key: key, timeframe: socket.assigns[:smart_timeframe_input]]}"
      )

    {:noreply, socket}
  end

  def handle_event("deselect_key", _, socket) do
    socket =
      socket
      |> assign(loading: true)
      |> push_patch(
        to:
          ~p"/app/explore/#{socket.assigns.database.id}?#{[granularity: socket.assigns.granularity, from: format_for_datetime_input(socket.assigns.from), to: format_for_datetime_input(socket.assigns.to), timeframe: socket.assigns[:smart_timeframe_input]]}"
      )

    {:noreply, socket}
  end

  def determine_granularity_for_timeframe(from, to) do
    duration_seconds = DateTime.diff(to, from, :second)

    cond do
      duration_seconds <= 3600 -> "1m"
      duration_seconds <= 86400 -> "1h"
      duration_seconds <= 604_800 -> "1d"
      duration_seconds <= 2_592_000 -> "1w"
      duration_seconds <= 7_776_000 -> "1mo"
      duration_seconds <= 31_536_000 -> "1mo"
      true -> "1y"
    end
  end

  @doc """
  Get available granularities from the driver configuration.
  This allows the UI to display the actual supported granularities.
  """
  def get_available_granularities(database) do
    config = Database.stats_config(database)
    config.track_granularities
  end

  @doc """
  Convert granularity strings to labels for the UI.
  Show raw granularities like "1s", "10s" to make it clear what the actual values are.
  """
  def granularity_to_label(granularity) do
    # Always show the raw granularity value so users see exactly what's configured
    granularity
  end

  @doc """
  Get granularities with their labels and positions for the UI buttons.
  """
  def get_granularity_buttons(database) do
    granularities = get_available_granularities(database)

    granularities
    |> Enum.with_index()
    |> Enum.map(fn {granularity, index} ->
      label = granularity_to_label(granularity)

      position =
        cond do
          index == 0 -> :first
          index == length(granularities) - 1 -> :last
          true -> :middle
        end

      {label, granularity, position}
    end)
  end

  def determine_smart_input_for_range(from, to, time_zone) do
    now = DateTime.utc_now() |> DateTime.shift_zone!(time_zone)
    duration_seconds = DateTime.diff(to, from, :second)

    time_diff_to_now = abs(DateTime.diff(to, now, :second))

    if time_diff_to_now <= 300 do
      cond do
        duration_seconds >= 300 && duration_seconds <= 330 -> "5m"
        duration_seconds >= 870 && duration_seconds <= 930 -> "15m"
        duration_seconds >= 1770 && duration_seconds <= 1830 -> "30m"
        duration_seconds >= 3540 && duration_seconds <= 3660 -> "1h"
        duration_seconds >= 10740 && duration_seconds <= 10860 -> "3h"
        duration_seconds >= 21540 && duration_seconds <= 21660 -> "6h"
        duration_seconds >= 43140 && duration_seconds <= 43260 -> "12h"
        duration_seconds >= 86340 && duration_seconds <= 86460 -> "24h"
        duration_seconds >= 172_740 && duration_seconds <= 172_860 -> "2d"
        duration_seconds >= 604_740 && duration_seconds <= 604_860 -> "7d"
        duration_seconds >= 1_209_540 && duration_seconds <= 1_209_660 -> "14d"
        duration_seconds >= 2_592_000 - 3600 && duration_seconds <= 2_592_000 + 3600 -> "30d"
        true -> nil
      end
    else
      nil
    end
  end

  def handle_params(params, _session, socket) do
    require Logger
    Logger.info("DatabaseExploreLive.handle_params starting for database: #{socket.assigns.database.id}")
    
    granularity = params["granularity"] || "1h"
    Logger.info("Getting stats config for database...")
    config = Database.stats_config(socket.assigns.database)
    Logger.info("Stats config retrieved successfully")

    # Determine from and to times based on URL parameters
    {from, to, smart_input, use_fixed_display} =
      cond do
        # If we have explicit from/to parameters, use them (they take precedence)
        params["from"] && params["from"] != "" && params["to"] && params["to"] != "" ->
          case {parse_date(params["from"], config.time_zone), parse_date(params["to"], config.time_zone)} do
            {{:ok, from}, {:ok, to}} ->
              # When explicit from/to are provided, prioritize the timeframe parameter from URL
              # Only fall back to determining smart input if no timeframe parameter exists
              smart_input = if params["timeframe"] && params["timeframe"] != "" do
                params["timeframe"]
              else
                determine_smart_input_for_range(from, to, config.time_zone)
              end
              # Use fixed display when we have both explicit from/to AND timeframe (indicates page reload)
              use_fixed_display = params["timeframe"] && params["timeframe"] != ""
              {from, to, smart_input, use_fixed_display}

            _ ->
              # If parsing fails, fall back to timeframe or defaults
              cond do
                params["timeframe"] && params["timeframe"] != "" ->
                  case parse_smart_timeframe(params["timeframe"], config) do
                    {:ok, from, to} -> {from, to, params["timeframe"], false}
                    {:error, _} ->
                      default_to = DateTime.utc_now()
                      default_from = DateTime.shift(default_to, hour: -24)
                      {default_from, default_to, "24h", false}
                  end

                true ->
                  default_to = DateTime.utc_now()
                  default_from = DateTime.shift(default_to, hour: -24)
                  {default_from, default_to, "24h", false}
              end
          end

        # If we have a timeframe parameter but no explicit from/to, calculate from timeframe
        params["timeframe"] && params["timeframe"] != "" ->
          case parse_smart_timeframe(params["timeframe"], config) do
            {:ok, from, to} -> {from, to, params["timeframe"], false}
            {:error, _} ->
              # Fallback to defaults if timeframe parsing fails
              default_to = DateTime.utc_now()
              default_from = DateTime.shift(default_to, hour: -24)
              {default_from, default_to, "24h", false}
          end

        # Default case: use 24-hour range from now
        true ->
          default_to = DateTime.utc_now()
          default_from = DateTime.shift(default_to, hour: -24)
          {default_from, default_to, "24h", false}
      end

    # Preserve the current key search filter if it exists, otherwise use empty string
    current_key_filter = socket.assigns[:key_search_filter] || ""

    socket =
      socket
      |> assign(granularity: granularity, from: from, to: to)
      |> assign(key: params["key"])
      |> assign(form: to_form(%{}))
      |> assign(smart_timeframe_input: smart_input)
      |> assign(use_fixed_display: use_fixed_display)
      |> assign(key_search_filter: current_key_filter)
      |> assign(show_timeframe_dropdown: false)
      |> assign(show_sensitivity_dropdown: false)

    # Check if this is a fresh page load without timeframe parameters
    # If so, update URL to include default parameters for consistency
    should_update_url = is_nil(params["timeframe"]) and is_nil(params["from"]) and is_nil(params["to"])

    if should_update_url do
      # Push default parameters to URL to maintain consistency between URL and UI state
      url_params = %{
        timeframe: smart_input,
        granularity: granularity
      }
      # Only add key parameter if it exists
      url_params = if params["key"], do: Map.put(url_params, :key, params["key"]), else: url_params
      
      socket = push_patch(socket, to: ~p"/app/explore/#{socket.assigns.database.id}?#{url_params}")
      {:noreply, socket}
    else
      # Check if we need to keep the current loading state (when coming from event handlers)
      # or load data immediately (when first loading the page or refreshing)
      if socket.assigns[:loading] do
        # Loading state already set by event handler, trigger async data load
        send(self(), :load_data)
        {:noreply, socket}
      else
        # First page load or refresh - load data immediately without loading indicator
        load_data_and_update_socket(socket)
      end
    end
  end

  def handle_info(:hide_dropdown_after_delay, socket) do
    {:noreply, assign(socket, show_timeframe_dropdown: false)}
  end

  def handle_info(:load_data, socket) do
    # Load data asynchronously to show loading indicator
    load_data_and_update_socket(socket)
  end
  
  def handle_info(:heartbeat, socket) do
    # Heartbeat to keep the process alive during long operations
    # Only continue heartbeat if we're still loading
    if socket.assigns.loading_chunks do
      :timer.send_after(5000, self(), :heartbeat)
    end
    {:noreply, socket}
  end
  
  def handle_async(:chunk_task, {:ok, {chunk_index, chunk_result}}, socket) do
    # Accumulate the chunk data (prepend since we're loading newest first)
    current_stats = socket.assigns.accumulated_stats
    new_stats = %{
      at: chunk_result[:at] ++ current_stats.at,
      values: chunk_result[:values] ++ current_stats.values
    }
    
    # Update progress 
    progress = socket.assigns.loading_progress
    new_progress = %{progress | current: chunk_index + 1}
    
    # Generate chart data from accumulated stats
    keys_sum = reduce_stats(new_stats[:values])
    
    {timeline_data, chart_type} =
      if socket.assigns.key && socket.assigns.key != "" do
        timeline = series_from(new_stats, ["keys", socket.assigns.key])
        {Jason.encode!(timeline["keys.#{socket.assigns.key}"]), "single"}
      else
        timeline = series_from_all_keys(new_stats, keys_sum)
        {Jason.encode!(timeline), "stacked"}
      end

    selected_key_color =
      if socket.assigns.key && socket.assigns.key != "" do
        get_key_color(keys_sum, socket.assigns.key)
      else
        nil
      end
    
    socket = socket
      |> assign(accumulated_stats: new_stats)
      |> assign(loading_progress: new_progress)
      |> assign(keys: keys_sum)
      |> assign(timeline: timeline_data)
      |> assign(chart_type: chart_type)
      |> assign(selected_key_color: selected_key_color)
    
    # Continue loading next chunk or finish
    if new_progress.current >= new_progress.total do
      # All chunks loaded - load final table data
      config = Database.stats_config(socket.assigns.database)
      load_final_table_data(socket, config)
    else
      # Load next chunk
      config = Database.stats_config(socket.assigns.database)
      timeline_chunks = socket.assigns.timeline_chunks
      load_chunk_async(socket, timeline_chunks, chunk_index + 1, config)
    end
  end
  
  def handle_async(:chunk_task, {:exit, reason}, socket) do
    # Handle chunk loading failure
    socket = socket
      |> assign(loading: false)
      |> assign(loading_chunks: false)
      |> assign(loading_progress: nil)
      |> put_flash(:error, "Failed to load data chunk: #{inspect(reason)}")
    
    {:noreply, socket}
  end
  
  def handle_async(:single_chunk_task, {:ok, {keys_sum, timeline_data, chart_type, selected_key_color, key_tabulized}}, socket) do
    # Handle single chunk (synchronous loading) completion
    socket = socket
      |> assign(keys: keys_sum)
      |> assign(timeline: timeline_data)
      |> assign(chart_type: chart_type)
      |> assign(selected_key_color: selected_key_color)
      |> assign(stats: key_tabulized)
      |> assign(loading: false)
      |> assign(loading_chunks: false)
      |> assign(loading_progress: nil)
    
    {:noreply, socket}
  end
  
  def handle_async(:single_chunk_task, {:exit, reason}, socket) do
    # Handle single chunk loading failure
    socket = socket
      |> assign(loading: false)
      |> assign(loading_chunks: false)
      |> assign(loading_progress: nil)
      |> put_flash(:error, "Failed to load data: #{inspect(reason)}")
    
    {:noreply, socket}
  end
  


  defp load_data_and_update_socket(socket) do
    config = Database.stats_config(socket.assigns.database)
    
    # Check if we need progressive loading
    if should_slice_timeline?(socket.assigns.from, socket.assigns.to, socket.assigns.granularity, config) do
      start_progressive_loading(socket)
    else
      # Load normally for small timelines
      load_data_synchronously(socket)
    end
  end
  
  defp load_data_synchronously(socket) do
    # Show unified loading indicator even for single chunk
    socket = socket
      |> assign(loading: true)
      |> assign(loading_chunks: true)
      |> assign(loading_progress: %{current: 0, total: 1})
    
    # Start async task to prevent blocking
    socket = start_async(socket, :single_chunk_task, fn ->
      database_stats = load_database_stats(socket.assigns.database, socket.assigns.granularity, socket.assigns.from, socket.assigns.to)
      keys_sum = reduce_stats(database_stats[:values])

      {timeline_data, chart_type} =
        if socket.assigns.key && socket.assigns.key != "" do
          timeline = series_from(database_stats, ["keys", socket.assigns.key])
          {Jason.encode!(timeline["keys.#{socket.assigns.key}"]), "single"}
        else
          timeline = series_from_all_keys(database_stats, keys_sum)
          {Jason.encode!(timeline), "stacked"}
        end

      key_stats =
        load_database_key_stats(socket.assigns.database, socket.assigns.key, socket.assigns.granularity, socket.assigns.from, socket.assigns.to)

      {:ok, key_tabulized, _key_seriesized} = process_database_key_stats(key_stats)

      selected_key_color =
        if socket.assigns.key && socket.assigns.key != "" do
          get_key_color(keys_sum, socket.assigns.key)
        else
          nil
        end

      {keys_sum, timeline_data, chart_type, selected_key_color, key_tabulized}
    end, timeout: 300_000)

    {:noreply, socket}
  end
  
  defp start_progressive_loading(socket) do
    config = Database.stats_config(socket.assigns.database)
    
    # Generate full timeline and split into chunks
    parser = Trifle.Stats.Nocturnal.Parser.new(socket.assigns.granularity)
    from_normalized = DateTime.shift_zone!(socket.assigns.from, "Etc/UTC")
    to_normalized = DateTime.shift_zone!(socket.assigns.to, "Etc/UTC")
    
    full_timeline = Trifle.Stats.Nocturnal.timeline(
      from: from_normalized,
      to: to_normalized,
      offset: parser.offset,
      unit: parser.unit,
      config: config
    )
    
    # Split timeline into chunks of 720 and reverse to load newest first
    timeline_chunks = full_timeline
      |> Enum.chunk_every(720)
      |> Enum.reverse()
    total_chunks = length(timeline_chunks)
    
    # Initialize progressive loading state
    socket = socket
      |> assign(loading_chunks: true)
      |> assign(loading_progress: %{current: 0, total: total_chunks})
      |> assign(accumulated_stats: %{at: [], values: []})
      |> assign(timeline_chunks: timeline_chunks)
      |> assign(keys: %{}) # Start with empty keys
      |> assign(timeline: "[]") # Start with empty chart
      |> assign(chart_type: "stacked") # Default chart type
      |> assign(selected_key_color: nil)
      |> assign(stats: nil) # Keep table loading
    
    # Start heartbeat to keep the process alive during long operations
    :timer.send_after(5000, self(), :heartbeat)
    
    # Start loading first chunk
    load_chunk_async(socket, timeline_chunks, 0, config)
  end
  
  defp load_chunk_async(socket, chunks, chunk_index, config) do
    if chunk_index < length(chunks) do
      chunk = Enum.at(chunks, chunk_index)
      chunk_from = List.first(chunk)
      chunk_to = List.last(chunk)
      
      # Start async task for this chunk using LiveView's async mechanism
      # Use longer timeout for potentially slow database queries
      socket = start_async(socket, :chunk_task, fn ->
        chunk_result = Trifle.Stats.values(
          "__system__keys__",
          chunk_from,
          chunk_to,
          socket.assigns.granularity,
          config
        )
        {chunk_index, chunk_result}
      end, timeout: 300_000)
      
      {:noreply, socket}
    else
      # All chunks loaded - now load the table data
      load_final_table_data(socket, config)
    end
  end
  
  defp load_final_table_data(socket, config) do
    # Load key stats for the table (only once at the end)
    key_stats = if socket.assigns.key && socket.assigns.key != "" do
      if should_slice_timeline?(socket.assigns.from, socket.assigns.to, socket.assigns.granularity, config) do
        load_key_stats_sliced(socket.assigns.key, socket.assigns.granularity, socket.assigns.from, socket.assigns.to, config)
      else
        Trifle.Stats.values(socket.assigns.key, socket.assigns.from, socket.assigns.to, socket.assigns.granularity, config)
      end
    else
      nil
    end

    {:ok, key_tabulized, _key_seriesized} = process_database_key_stats(key_stats)
    
    # Preserve all existing chart data when finishing loading
    socket = socket
      |> assign(stats: key_tabulized)
      |> assign(loading: false)
      |> assign(loading_chunks: false)
      |> assign(loading_progress: nil)
    
    {:noreply, socket}
  end

  def load_database_stats(database, granularity, from, to) do
    config = Database.stats_config(database)
    
    # Check if timeline would be too large and needs slicing
    if should_slice_timeline?(from, to, granularity, config) do
      load_database_stats_sliced(database, granularity, from, to, config)
    else
      Trifle.Stats.values(
        "__system__keys__",
        from,
        to,
        granularity,
        config
      )
    end
  end
  
  def should_slice_timeline?(from, to, granularity, config) do
    parser = Trifle.Stats.Nocturnal.Parser.new(granularity)
    from_normalized = DateTime.shift_zone!(from, "Etc/UTC")
    to_normalized = DateTime.shift_zone!(to, "Etc/UTC")
    
    # Generate timeline to check point count
    timeline = Trifle.Stats.Nocturnal.timeline(
      from: from_normalized,
      to: to_normalized,
      offset: parser.offset,
      unit: parser.unit,
      config: config
    )
    
    # Slice if more than 720 points
    length(timeline) > 720
  end
  
  defp load_database_stats_sliced(database, granularity, from, to, config) do
    parser = Trifle.Stats.Nocturnal.Parser.new(granularity)
    from_normalized = DateTime.shift_zone!(from, "Etc/UTC")
    to_normalized = DateTime.shift_zone!(to, "Etc/UTC")
    
    # Generate full timeline
    full_timeline = Trifle.Stats.Nocturnal.timeline(
      from: from_normalized,
      to: to_normalized,
      offset: parser.offset,
      unit: parser.unit,
      config: config
    )
    
    # Split timeline into chunks of 720
    # Split timeline into chunks of 720 and reverse to load newest first
    timeline_chunks = full_timeline
      |> Enum.chunk_every(720)
      |> Enum.reverse()
    
    # Load each chunk and combine results
    {combined_at, combined_values} = 
      timeline_chunks
      |> Enum.reduce({[], []}, fn chunk, {acc_at, acc_values} ->
        chunk_from = List.first(chunk)
        chunk_to = List.last(chunk)
        
        chunk_result = Trifle.Stats.values(
          "__system__keys__",
          chunk_from,
          chunk_to,
          granularity,
          config
        )
        
        {acc_at ++ chunk_result[:at], acc_values ++ chunk_result[:values]}
      end)
    
    %{at: combined_at, values: combined_values}
  end

  def reduce_stats(values) when is_list(values) do
    Enum.reduce(values, [], fn data, acc -> [data["keys"] | acc] end)
    |> Enum.reduce(%{}, fn data, acc -> Trifle.Stats.Packer.deep_sum(acc, data) end)
  end

  def reduce_stats(_values) do
    %{}
  end

  def series_from(%{at: at, values: values}, path) when is_list(path) do
    key = Enum.join(path, ".")

    Enum.with_index(at)
    |> Enum.reduce(%{}, fn {a, i}, acc ->
      v = get_in(Enum.at(values, i), path)
      unix_ms = DateTime.to_unix(a, :millisecond)
      Map.put(acc, key, [[unix_ms, v || 0] | acc[key] || []])
    end)
  end

  def series_from_all_keys(%{at: at, values: values}, keys_sum)
      when is_list(at) and is_list(values) do
    available_keys = Map.keys(keys_sum)

    if length(at) == 0 or length(values) == 0 do
      current_time = DateTime.to_unix(DateTime.utc_now(), :millisecond)

      Enum.map(available_keys, fn key ->
        total_value = keys_sum[key] || 0

        %{
          name: key,
          data: [[current_time, total_value]]
        }
      end)
    else
      Enum.map(available_keys, fn key ->
        key_data =
          Enum.with_index(at)
          |> Enum.map(fn {a, i} ->
            value_at_index = Enum.at(values, i)
            v = get_in(value_at_index, ["keys", key]) || 0
            unix_ms = DateTime.to_unix(a, :millisecond)
            [unix_ms, v]
          end)
          |> Enum.reverse()

        %{
          name: key,
          data: key_data
        }
      end)
    end
  end

  def series_from_all_keys(_stats, keys_sum) do
    current_time = DateTime.to_unix(DateTime.utc_now(), :millisecond)

    Enum.map(Map.keys(keys_sum), fn key ->
      total_value = keys_sum[key] || 0

      %{
        name: key,
        data: [[current_time, total_value]]
      }
    end)
  end

  def load_database_key_stats(_database, key, _granularity, _from, _to) when is_nil(key), do: nil

  def load_database_key_stats(_database, key, _granularity, _from, _to)
      when is_binary(key) and byte_size(key) == 0,
      do: nil

  def load_database_key_stats(database, key, granularity, from, to) do
    config = Database.stats_config(database)
    
    # Check if timeline would be too large and needs slicing
    if should_slice_timeline?(from, to, granularity, config) do
      load_key_stats_sliced(key, granularity, from, to, config)
    else
      Trifle.Stats.values(key, from, to, granularity, config)
    end
  end
  
  defp load_key_stats_sliced(key, granularity, from, to, config) do
    parser = Trifle.Stats.Nocturnal.Parser.new(granularity)
    from_normalized = DateTime.shift_zone!(from, "Etc/UTC")
    to_normalized = DateTime.shift_zone!(to, "Etc/UTC")
    
    # Generate full timeline
    full_timeline = Trifle.Stats.Nocturnal.timeline(
      from: from_normalized,
      to: to_normalized,
      offset: parser.offset,
      unit: parser.unit,
      config: config
    )
    
    # Split timeline into chunks of 720
    # Split timeline into chunks of 720 and reverse to load newest first
    timeline_chunks = full_timeline
      |> Enum.chunk_every(720)
      |> Enum.reverse()
    
    # Load each chunk and combine results
    {combined_at, combined_values} = 
      timeline_chunks
      |> Enum.reduce({[], []}, fn chunk, {acc_at, acc_values} ->
        chunk_from = List.first(chunk)
        chunk_to = List.last(chunk)
        
        chunk_result = Trifle.Stats.values(
          key,
          chunk_from,
          chunk_to,
          granularity,
          config
        )
        
        {acc_at ++ chunk_result[:at], acc_values ++ chunk_result[:values]}
      end)
    
    %{at: combined_at, values: combined_values}
  end

  def process_database_key_stats(stats) when is_nil(stats), do: {:ok, nil, nil}

  def process_database_key_stats(stats) do
    {
      :ok,
      Trifle.Stats.Tabler.tabulize(stats),
      Trifle.Stats.Tabler.seriesize(stats)
    }
  end

  def filter_keys(keys, filter) when filter == "" or is_nil(filter) do
    keys
  end

  def filter_keys(keys, filter) when is_binary(filter) do
    filter_lower = String.downcase(filter)
    Enum.filter(keys, fn {key, _count} ->
      String.contains?(String.downcase(key), filter_lower)
    end)
  end

  def get_key_color(keys, target_key) when is_map(keys) do
    keys
    |> Map.keys()
    |> Enum.sort()
    |> Enum.with_index()
    |> Enum.find(fn {key, _index} -> key == target_key end)
    |> case do
      {_key, index} -> ChartColors.color_for(index)
      nil -> ChartColors.primary()
    end
  end

  def format_nested_path(path, all_paths) when is_binary(path) do
    path
    |> String.split(".")
    |> build_nested_html(all_paths, [])
    |> Enum.join(".")
    |> Phoenix.HTML.raw()
  end

  defp build_nested_html([component], all_paths, path_so_far) do
    index = get_component_index_at_level(component, all_paths, path_so_far)
    color = ChartColors.color_for(index)
    ["<span style=\"color: #{color} !important\">#{component}</span>"]
  end

  defp build_nested_html([component | rest], all_paths, path_so_far) do
    index = get_component_index_at_level(component, all_paths, path_so_far)
    color = ChartColors.color_for(index)

    current_html = "<span style=\"color: #{color} !important\">#{component}</span>"
    new_path_so_far = path_so_far ++ [component]

    [current_html | build_nested_html(rest, all_paths, new_path_so_far)]
  end

  def format_table_timestamp(datetime, _granularity) when is_struct(datetime, DateTime) do
    date = datetime |> DateTime.to_date() |> Date.to_string()
    # Format time with hours, minutes, and seconds (HH:MM:SS)
    time = datetime |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 8)
    Phoenix.HTML.raw("#{date}<br/>#{time}")
  end

  def format_table_timestamp(datetime, _granularity) do
    to_string(datetime)
  end

  def format_number(number) when is_integer(number) or is_float(number) do
    cond do
      number >= 1_000_000_000 ->
        format_with_suffix(number / 1_000_000_000, "b")

      number >= 1_000_000 ->
        format_with_suffix(number / 1_000_000, "m")

      number >= 1_000 ->
        format_with_suffix(number / 1_000, "k")

      true ->
        to_string(number)
    end
  end

  def format_number(number), do: to_string(number)

  defp format_with_suffix(value, suffix) when is_float(value) do
    formatted =
      cond do
        value >= 100 ->
          # For values >= 100, show no decimals (e.g., "123k")
          :erlang.float_to_binary(value, decimals: 0)

        value >= 10 ->
          # For values >= 10, show 1 decimal (e.g., "12.3k")
          :erlang.float_to_binary(value, decimals: 1)

        true ->
          # For values < 10, show 2 decimals (e.g., "1.23k")
          :erlang.float_to_binary(value, decimals: 2)
      end

    # Remove trailing zeros and decimal point if not needed
    formatted = String.replace(formatted, ~r/\.?0+$/, "")
    "#{formatted}#{suffix}"
  end

  defp get_component_index_at_level(component, all_paths, path_so_far) do
    prefix =
      case path_so_far do
        [] -> ""
        parts -> Enum.join(parts, ".") <> "."
      end

    siblings =
      all_paths
      |> Enum.filter(fn path ->
        String.starts_with?(path, prefix) &&
          length(String.split(path, ".")) > length(path_so_far)
      end)
      |> Enum.map(fn path ->
        String.split(path, ".")
        |> Enum.drop(length(path_so_far))
        |> hd()
      end)
      |> Enum.uniq()
      |> Enum.sort()

    Enum.find_index(siblings, &(&1 == component)) || 0
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col">
    <!-- Row 1: Timeframe Selection -->
    <div class="sticky top-0 z-50 mb-6">
      <div class="bg-white rounded-lg shadow p-4">
        <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
          <!-- Smart input field with dropdown -->
          <div class="w-full md:w-[26rem]">
            <div
              class="relative"
              id={"smart_timeframe_container_#{@smart_timeframe_input}"}
              phx-update="replace"
            >
              <label
                for="smart_timeframe"
                class="absolute -top-2 left-2 inline-block bg-white px-1 text-xs font-medium text-gray-900"
              >
                Timeframe UTC{get_timezone_offset_display("UTC")}
              </label>
              <input
                type="text"
                name="smart_timeframe"
                id="smart_timeframe"
                value={format_smart_timeframe_display(@smart_timeframe_input, Database.stats_config(@database), @use_fixed_display, @from, @to)}
                placeholder="e.g., 5m, 2h, 1d, 3w, 6mo, 1y"
                phx-keydown="smart_timeframe_keydown"
                phx-key="Enter"
                phx-focus="show_timeframe_dropdown"
                phx-blur="delayed_hide_timeframe_dropdown"
                phx-hook="SmartTimeframeInput"
                class="block w-full rounded-md border-gray-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm pr-20"
              />
              <%= if @smart_timeframe_input && @smart_timeframe_input != "" do %>
                <div class="absolute inset-y-0 right-8 flex items-center">
                  <span class="inline-flex items-center rounded-md bg-teal-100 px-2 py-1 text-xs font-medium text-teal-600 ring-1 ring-inset ring-gray-500/10">
                    {@smart_timeframe_input}
                  </span>
                </div>
              <% end %>

              <div class="absolute inset-y-0 right-0 flex items-center pr-3">
                <svg
                  class="h-5 w-5 text-gray-400"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M19 9l-7 7-7-7"
                  />
                </svg>
              </div>

              <%= if @show_timeframe_dropdown do %>
                <div class="absolute z-10 mt-1 w-full bg-white shadow-lg max-h-60 rounded-md py-1 text-base ring-1 ring-black ring-opacity-5 overflow-auto focus:outline-none sm:text-sm">
                  <%= for {value, label} <- get_timeframe_dropdown_options() do %>
                    <div
                      phx-click="select_timeframe_preset"
                      phx-value-preset={value}
                      phx-value-label={label}
                      onmousedown="event.preventDefault()"
                      class="cursor-pointer select-none relative py-2 pl-3 pr-9 hover:bg-gray-50"
                    >
                      <div class="flex items-center justify-between">
                        <span class="text-sm text-gray-900">{label}</span>
                        <span class="inline-flex items-center rounded-md bg-teal-100 px-2 py-1 text-xs font-medium text-teal-600 ring-1 ring-inset ring-gray-500/10">
                          {value}
                        </span>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Granularity controls -->
          <div class="relative">
            <label class="absolute -top-2 left-2 inline-block bg-white px-1 text-xs font-medium text-gray-900 z-10">
              Granularity
            </label>
            <div class="inline-flex rounded-md shadow-sm border border-gray-300 focus-within:border-teal-500 focus-within:ring-1 focus-within:ring-teal-500" role="group">
              <%= for {label, granularity, position} <- get_granularity_buttons(@database) do %>
                <button
                  type="button"
                  phx-click="select_granularity"
                  phx-value-granularity={granularity}
                  class={
                    base_classes =
                      "relative inline-flex items-center px-3 py-2 text-sm font-medium focus:z-10 focus:outline-none h-9"

                    position_classes =
                      case position do
                        :first -> "rounded-l-md"
                        :middle -> ""
                        :last -> "rounded-r-md"
                      end

                    state_classes =
                      if @granularity == granularity do
                        "bg-white text-teal-500 border-b-2 border-b-teal-500 font-semibold hover:shadow-[inset_0_-8px_16px_-8px_rgba(20,184,166,0.2)]"
                      else
                        "bg-white text-gray-700 border-b-2 border-b-transparent hover:border-b-gray-300 hover:shadow-[inset_0_-8px_16px_-8px_rgba(107,114,128,0.15)]"
                      end

                    separator_classes =
                      case position do
                        :first -> ""
                        _ -> "border-l border-gray-300"
                      end

                    "#{base_classes} #{position_classes} #{state_classes} #{separator_classes}"
                  }
                >
                  {label}
                </button>
              <% end %>
            </div>
          </div>

        </div>
      </div>
    </div>

    <!-- Row 2: Activity/Events Chart -->
    <div class="sticky top-16 z-40 mb-6">
      <div class="bg-white rounded-lg shadow py-1 px-3 relative">
        <%= if @loading_chunks && @loading_progress do %>
          <div class="absolute inset-0 bg-white bg-opacity-75 flex items-center justify-center z-10 rounded-lg" style="top: -16px;">
            <div class="flex flex-col items-center space-y-3">
              <div class="flex items-center space-x-2">
                <div class="animate-spin rounded-full h-6 w-6 border-2 border-gray-300 border-t-teal-500"></div>
                <span class="text-sm text-gray-600">
                  Scientificating piece <%= @loading_progress.current + 1 %> of <%= @loading_progress.total %>...
                </span>
              </div>
              <div class="w-64 bg-gray-200 rounded-full h-2">
                <div 
                  class="bg-teal-500 h-2 rounded-full transition-all duration-300"
                  style={"width: #{((@loading_progress.current + 1) / @loading_progress.total * 100)}%"}
                ></div>
              </div>
              <%= if @loading_progress.total > 1 do %>
                <div class="flex items-center justify-center">
                  <span class="text-xs text-gray-500">
                    Chart updates continuously • Table loads when complete
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
        <div
          id="timeline-hook"
          phx-hook="ProjectTimeline"
          data-events={@timeline}
          data-key={@key}
          data-timezone="UTC"
          data-chart-type={@chart_type}
          data-colors={ChartColors.json_palette()}
          data-selected-key-color={@selected_key_color}
          class=""
        >
        </div>
        <div id="timeline-chart-wrapper" phx-update="ignore" class="mt-5">
          <div id="timeline-chart"></div>
        </div>
      </div>
    </div>

    <!-- Row 3: Key Selection -->
    <div class="mb-6">
      <div class="bg-white rounded-lg shadow">
        <div class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-3 border-b flex items-center justify-between">
          <span>Keys</span>
          <div class="relative">
            <input
              type="text"
              placeholder="Search keys..."
              value={@key_search_filter}
              phx-keyup="filter_keys"
              class="block w-48 rounded-md border-gray-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-xs pl-8"
            />
            <div class="absolute inset-y-0 left-0 flex items-center pl-2">
              <svg class="h-4 w-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
              </svg>
            </div>
          </div>
        </div>
        <div class="h-48 overflow-y-auto"> <!-- Fixed height for ~3 items with scrolling -->
          <ul role="list" class="divide-y divide-gray-100">
            <%= for {key, count} <- filter_keys(@keys, @key_search_filter) do %>
              <li class={
                  if @key == key,
                    do: "relative bg-teal-50",
                    else: "relative bg-white hover:bg-gray-50"
                }>
                <button
                  type="button"
                  phx-click={if @key == key, do: "deselect_key", else: "select_key"}
                  phx-value-key={key}
                  class="w-full py-4 px-4 sm:px-6 lg:px-8 text-left"
                >
                  <div class="flex justify-between gap-x-6">
                    <div class="flex gap-x-3 items-center">
                      <%= if @key == key do %>
                        <svg
                          class="h-5 w-5 text-teal-600 flex-shrink-0"
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke-width="1.5"
                          stroke="currentColor"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                          />
                          <circle cx="12" cy="12" r="4" fill="currentColor" />
                        </svg>
                      <% else %>
                        <svg
                          class="h-5 w-5 text-gray-400 flex-shrink-0"
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke-width="1.5"
                          stroke="currentColor"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                          />
                        </svg>
                      <% end %>

                      <div class="min-w-0 flex-auto">
                        <p
                          class="text-sm font-semibold font-mono leading-6"
                          style={"color: #{get_key_color(@keys, key)} !important"}
                        >
                          {key}
                        </p>
                      </div>
                    </div>
                    <div class="flex items-center gap-x-4">
                      <span
                        class="inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ring-1 ring-inset ring-gray-300 float-right"
                        style={"background-color: #{get_key_color(@keys, key)}15; color: #{get_key_color(@keys, key)} !important"}
                      >
                        {format_number(count)}
                      </span>
                      <svg
                        class="h-5 w-5 flex-none text-gray-400"
                        viewBox="0 0 20 20"
                        fill="currentColor"
                        aria-hidden="true"
                      >
                        <path
                          fill-rule="evenodd"
                          d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z"
                          clip-rule="evenodd"
                        />
                      </svg>
                    </div>
                  </div>
                </button>
              </li>
            <% end %>
            <%= if Enum.empty?(filter_keys(@keys, @key_search_filter)) do %>
              <div class="flex items-center justify-center h-full text-gray-500 text-sm">
                <%= if @loading_chunks do %>
                  <div class="flex items-center space-x-2">
                    <div class="animate-spin rounded-full h-4 w-4 border-2 border-gray-300 border-t-gray-500"></div>
                    <span>Loading keys...</span>
                  </div>
                <% else %>
                  <span>No keys found</span>
                <% end %>
              </div>
            <% end %>
          </ul>
        </div>
      </div>
    </div>

    <!-- Row 4: Data for Selected Key -->
    <div class="mb-6">
      <%= if @stats do %>
        <div class="bg-white rounded-lg shadow">
          <div
            class="overflow-x-auto overflow-hidden"
            id="table-hover-container"
            phx-hook="TableHover"
          >
            <table class="min-w-full divide-y divide-gray-300 overflow-auto" id="data-table">
              <thead>
                <tr>
                  <th
                    scope="col"
                    class="top-0 lg:left-0 lg:sticky bg-white whitespace-nowrap py-2 pl-4 pr-3 text-left text-xs font-semibold text-gray-900 pl-4 h-16 z-20 border-r border-gray-300 lg:border-r-0"
                    style="box-shadow: 1px 0 0 0 #d1d5db;"
                  >
                    Path
                  </th>
                  <%= for {at, col_index} <- Enum.reverse(@stats[:at]) |> Enum.with_index(1) do %>
                    <th
                      scope="col"
                      class="top-0 sticky whitespace-nowrap px-2 py-2 text-left text-xs font-mono font-semibold text-teal-700 h-16 align-top z-10 transition-colors duration-150"
                      data-col={col_index}
                    >
                      {format_table_timestamp(at, @granularity)}
                    </th>
                  <% end %>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200 bg-white">
                <%= for {path, row_index} <- @stats[:paths] |> Enum.with_index(1) do %>
                  <tr data-row={row_index}>
                    <td
                      class="lg:left-0 lg:sticky bg-white whitespace-nowrap py-1 pl-4 pr-3 text-xs font-mono pl-4 z-10 transition-colors duration-150 border-r border-gray-300 lg:border-r-0"
                      style="box-shadow: 1px 0 0 0 #d1d5db;"
                      data-row={row_index}
                    >
                      {format_nested_path(path, @stats[:paths])}
                    </td>
                    <%= for {at, col_index} <- Enum.reverse(@stats[:at]) |> Enum.with_index(1) do %>
                      <% value = @stats[:values][{path, at}] %>
                      <%= if value do %>
                        <td
                          class="whitespace-nowrap px-2 py-1 text-xs font-medium text-gray-900 transition-colors duration-150 cursor-pointer"
                          data-row={row_index}
                          data-col={col_index}
                        >
                          {value}
                        </td>
                      <% else %>
                        <td
                          class="whitespace-nowrap px-2 py-1 text-xs font-medium text-gray-300 transition-colors duration-150 cursor-pointer"
                          data-row={row_index}
                          data-col={col_index}
                        >
                          0
                        </td>
                      <% end %>
                    <% end %>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      <% else %>
        <div class="bg-white rounded-lg shadow p-8">
          <%= if @loading_chunks do %>
            <div class="text-gray-500 text-center">
              <div class="flex items-center justify-center space-x-2">
                <div class="animate-spin rounded-full h-5 w-5 border-2 border-gray-300 border-t-teal-500"></div>
                <p class="text-lg">Loading table data...</p>
              </div>
              <p class="text-sm mt-2">
                Chart is updating above • Table will appear when loading completes
              </p>
            </div>
          <% else %>
            <div class="text-gray-500 text-center">
              <p class="text-lg">↑ Select a key to view detailed data</p>
              <p class="text-sm mt-2">
                The chart above shows a stacked view of all events in this database.
              </p>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    </div>
    """
  end

end
