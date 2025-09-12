defmodule TrifleApp.DatabaseExploreLive do
  use TrifleApp, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  alias Trifle.Stats.SeriesFetcher
  alias TrifleApp.DesignSystem.ChartColors
  alias TrifleApp.TimeframeParsing

  def mount(params, _session, socket) do
    database = Organizations.get_database!(params["id"])

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

    # Cache config to avoid recalculation on every render
    database_config = Database.stats_config(database)
    available_granularities = get_available_granularities(database)

    socket =
      socket
      |> assign(page_title: ["Database", database.display_name, "Explore"])
      |> assign(database: database)
      |> assign(database_config: database_config)
      |> assign(available_granularities: available_granularities)
      |> assign(transponder_response_paths: transponder_response_paths)
      |> assign(transponder_info: transponder_info)
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
      |> assign(transponding: false)
      |> assign(show_timeframe_dropdown: false)
      |> assign(show_sensitivity_dropdown: false)
      |> assign(show_granularity_dropdown: false)
      |> assign(transponder_errors: [])
      |> assign(show_error_modal: false)
      |> assign(transponder_results: [])
      |> assign(key_transponder_results: %{successful: [], failed: [], errors: []})
      |> assign(load_start_time: nil)
      |> assign(load_duration_microseconds: nil)

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

  def parse_direct_timeframe(input, config) do
    # Parse direct timeframe format: "YYYY-MM-DD HH:MM:SS - YYYY-MM-DD HH:MM:SS"
    case String.split(input, " - ") do
      [from_str, to_str] when length([from_str, to_str]) == 2 ->
        with {:ok, from} <- parse_date(from_str, config.time_zone),
             {:ok, to} <- parse_date(to_str, config.time_zone) do
          # Try to detect if this matches a shorthand
          detected_shorthand = detect_shorthand_from_range(from, to, config)
          {:ok, from, to, detected_shorthand}
        else
          _ -> {:error, "Invalid datetime format"}
        end
      _ ->
        {:error, "Invalid timeframe format"}
    end
  end

  defp detect_shorthand_from_range(from, to, config) do
    # Calculate the difference between from and to
    diff_seconds = DateTime.diff(to, from, :second)
    
    # Get current time in database timezone
    now = DateTime.utc_now() |> DateTime.shift_zone!(config.time_zone)
    
    # Check if 'to' is approximately now (within 60 seconds)
    to_diff_from_now = abs(DateTime.diff(to, now, :second))
    
    if to_diff_from_now <= 60 do
      # This looks like a "last X" timeframe, try to match common patterns
      case diff_seconds do
        300 -> "5m"      # 5 minutes
        600 -> "10m"     # 10 minutes  
        900 -> "15m"     # 15 minutes
        1800 -> "30m"    # 30 minutes
        3600 -> "1h"     # 1 hour
        7200 -> "2h"     # 2 hours
        10800 -> "3h"    # 3 hours
        21600 -> "6h"    # 6 hours
        43200 -> "12h"   # 12 hours
        86400 -> "1d"    # 1 day
        172800 -> "2d"   # 2 days
        259200 -> "3d"   # 3 days
        604800 -> "1w"   # 1 week
        1209600 -> "2w"  # 2 weeks
        2629746 -> "1mo" # ~1 month (30.44 days)
        5259492 -> "2mo" # ~2 months
        7889238 -> "3mo" # ~3 months
        15778476 -> "6mo" # ~6 months
        31556952 -> "1y" # ~1 year
        _ -> "c" # Custom timeframe
      end
    else
      "c" # Custom timeframe (not relative to now)
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
              ~p"/app/dbs/#{socket.assigns.database.id}?#{[granularity: granularity, from: format_for_datetime_input(from), to: format_for_datetime_input(to), key: socket.assigns.key]}"
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

  def handle_event("show_granularity_dropdown", _, socket) do
    {:noreply, assign(socket, show_granularity_dropdown: true)}
  end

  def handle_event("hide_granularity_dropdown", _, socket) do
    {:noreply, assign(socket, show_granularity_dropdown: false)}
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
              ~p"/app/dbs/#{socket.assigns.database.id}?#{[granularity: granularity, from: format_for_datetime_input(from), to: format_for_datetime_input(to), key: socket.assigns[:key] || "", timeframe: preset]}"
          )

        {:noreply, socket}

      {:error, _} ->
        {:noreply, assign(socket, show_timeframe_dropdown: false)}
    end
  end

  def handle_event("smart_timeframe_keydown", %{"key" => "Enter", "value" => input}, socket) do
    config = Database.stats_config(socket.assigns.database)
    
    # First try to parse as a direct timeframe range (YYYY-MM-DD HH:MM:SS - YYYY-MM-DD HH:MM:SS)
    case parse_direct_timeframe(input, config) do
      {:ok, from, to, detected_shorthand} ->
        # Direct timeframe parsing succeeded
        granularity = socket.assigns.granularity
        
        socket =
          socket
          |> assign(from: from, to: to)
          |> assign(smart_timeframe_input: detected_shorthand)
          |> assign(use_fixed_display: false)
          |> assign(loading: true)
          |> assign(show_timeframe_dropdown: false)
          |> push_event("update_smart_timeframe_input", %{
            value: format_timeframe_display(from, to)
          })
          |> push_patch(
            to:
              ~p"/app/dbs/#{socket.assigns.database.id}?#{[granularity: granularity, from: format_for_datetime_input(from), to: format_for_datetime_input(to), key: socket.assigns[:key] || "", timeframe: detected_shorthand]}"
          )

        {:noreply, socket}
        
      {:error, _} ->
        # Fall back to smart timeframe parsing
        short_input =
          case find_short_code_from_description(input) do
            nil -> input
            short_code -> short_code
          end

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
                  ~p"/app/dbs/#{socket.assigns.database.id}?#{[granularity: granularity, from: format_for_datetime_input(from), to: format_for_datetime_input(to), key: socket.assigns[:key] || "", timeframe: short_input]}"
              )

            {:noreply, socket}

          {:error, _} ->
            {:noreply, assign(socket, show_timeframe_dropdown: false)}
        end
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
      |> assign(show_granularity_dropdown: false)
      |> push_patch(
        to:
          ~p"/app/dbs/#{socket.assigns.database.id}?#{[granularity: granularity, from: format_for_datetime_input(socket.assigns.from), to: format_for_datetime_input(socket.assigns.to), key: socket.assigns[:key] || "", timeframe: socket.assigns[:smart_timeframe_input]]}"
      )

    {:noreply, socket}
  end

  def handle_event("select_key", %{"key" => key}, socket) do
    socket =
      socket
      |> assign(loading: true)
      |> push_patch(
        to:
          ~p"/app/dbs/#{socket.assigns.database.id}?#{[granularity: socket.assigns.granularity, from: format_for_datetime_input(socket.assigns.from), to: format_for_datetime_input(socket.assigns.to), key: key, timeframe: socket.assigns[:smart_timeframe_input]]}"
      )

    {:noreply, socket}
  end

  def handle_event("deselect_key", _, socket) do
    socket =
      socket
      |> assign(loading: true)
      |> push_patch(
        to:
          ~p"/app/dbs/#{socket.assigns.database.id}?#{[granularity: socket.assigns.granularity, from: format_for_datetime_input(socket.assigns.from), to: format_for_datetime_input(socket.assigns.to), timeframe: socket.assigns[:smart_timeframe_input]]}"
      )

    {:noreply, socket}
  end

  def handle_event("show_transponder_errors", _, socket) do
    {:noreply, assign(socket, show_error_modal: true)}
  end

  def handle_event("hide_transponder_errors", _, socket) do
    {:noreply, assign(socket, show_error_modal: false)}
  end

  def handle_event("navigate_timeframe_backward", _, socket) do
    navigate_timeframe(socket, :backward)
  end

  def handle_event("navigate_timeframe_forward", _, socket) do
    navigate_timeframe(socket, :forward)
  end

  def handle_event("reload_data", _, socket) do
    reload_current_timeframe(socket)
  end

  defp navigate_timeframe(socket, direction) do
    from = socket.assigns.from
    to = socket.assigns.to
    
    # Calculate the duration between from and to
    duration_seconds = DateTime.diff(to, from, :second)
    
    # Calculate new timeframe based on direction
    {new_from, new_to} = case direction do
      :backward ->
        # Move backwards: TO becomes FROM, FROM = FROM - duration
        new_from = DateTime.add(from, -duration_seconds, :second)
        {new_from, from}
        
      :forward ->
        # Move forwards: FROM becomes TO, TO = TO + duration (clamped to 'now')
        proposed_to = DateTime.add(to, duration_seconds, :second)
        config = socket.assigns.database_config
        now = DateTime.utc_now() |> DateTime.shift_zone!(config.time_zone || "UTC")
        if DateTime.compare(proposed_to, now) == :gt do
          clamped_to = now
          clamped_from = DateTime.add(clamped_to, -duration_seconds, :second)
          {clamped_from, clamped_to}
        else
          {to, proposed_to}
        end
    end
    
    # Update socket with new timeframe and trigger reload
    granularity = socket.assigns.granularity
    
    socket =
      socket
      |> assign(from: new_from, to: new_to)
      |> assign(loading: true)
      |> assign(use_fixed_display: false)
      |> assign(smart_timeframe_input: "c")  # Mark as custom since it's a calculated range
      |> push_event("update_smart_timeframe_input", %{
        value: format_timeframe_display(new_from, new_to)
      })
      |> push_patch(
        to:
          ~p"/app/dbs/#{socket.assigns.database.id}?#{[granularity: granularity, from: format_for_datetime_input(new_from), to: format_for_datetime_input(new_to), key: socket.assigns[:key] || "", timeframe: "c"]}"
      )

    {:noreply, socket}
  end

  defp reload_current_timeframe(socket) do
    granularity = socket.assigns.granularity
    
    params =
      if socket.assigns.use_fixed_display do
        [
          granularity: granularity,
          from: format_for_datetime_input(socket.assigns.from),
          to: format_for_datetime_input(socket.assigns.to),
          key: socket.assigns[:key] || "",
          timeframe: socket.assigns[:smart_timeframe_input]
        ]
      else
        [
          granularity: granularity,
          key: socket.assigns[:key] || "",
          timeframe: socket.assigns[:smart_timeframe_input]
        ]
      end

    {:noreply,
     socket
     |> assign(loading: true)
     |> push_patch(to: ~p"/app/dbs/#{socket.assigns.database.id}?#{params}")}
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
  Format granularity to human readable text like "1 minute" or "15 minutes" 
  """
  def granularity_to_readable(granularity) do
    case granularity do
      "1s" -> "1 second"
      "1m" -> "1 minute"
      "1h" -> "1 hour"
      "1d" -> "1 day"
      "1w" -> "1 week"
      "1mo" -> "1 month"
      "1q" -> "1 quarter"
      "1y" -> "1 year"
      _ ->
        # For custom granularities like "5m", "15m", etc., try to parse with Nocturnal.Parser
        try do
          parser = Trifle.Stats.Nocturnal.Parser.new(granularity)
          if Trifle.Stats.Nocturnal.Parser.valid?(parser) do
            unit_name = case parser.unit do
              :second -> if parser.offset == 1, do: "second", else: "seconds"
              :minute -> if parser.offset == 1, do: "minute", else: "minutes"
              :hour -> if parser.offset == 1, do: "hour", else: "hours"
              :day -> if parser.offset == 1, do: "day", else: "days"
              :week -> if parser.offset == 1, do: "week", else: "weeks"
              :month -> if parser.offset == 1, do: "month", else: "months"
              :quarter -> if parser.offset == 1, do: "quarter", else: "quarters"
              :year -> if parser.offset == 1, do: "year", else: "years"
              _ -> "units"
            end
            "#{parser.offset} #{unit_name}"
          else
            granularity
          end
        rescue
          _ -> granularity
        end
    end
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
    Logger.info("DatabaseExploreLive.handle_params called with: #{inspect(params)}")
    
    db_default_gran = socket.assigns.database.default_granularity
    granularity = params["granularity"] || db_default_gran || "1h"
    config = Database.stats_config(socket.assigns.database)

    # Determine from and to times based on URL parameters
    {from, to, smart_input, use_fixed_display} =
      cond do
        # If we have explicit from/to parameters, use them (they take precedence)
        params["from"] && params["from"] != "" && params["to"] && params["to"] != "" ->
          case {TimeframeParsing.parse_date(params["from"], config.time_zone), TimeframeParsing.parse_date(params["to"], config.time_zone)} do
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
                  case TimeframeParsing.parse_smart_timeframe(params["timeframe"], config) do
                    {:ok, from, to, smart_input, use_fixed} -> {from, to, smart_input, use_fixed}
                    {:error, _} ->
                      tf = socket.assigns.database.default_timeframe || "24h"
                      case TimeframeParsing.parse_smart_timeframe(tf, config) do
                        {:ok, f, t, si, uf} -> {f, t, si, uf}
                        {:error, _} ->
                          default_to = DateTime.utc_now()
                          default_from = DateTime.shift(default_to, hour: -24)
                          {default_from, default_to, "24h", false}
                      end
                  end

                true ->
                  tf = socket.assigns.database.default_timeframe || "24h"
                  case TimeframeParsing.parse_smart_timeframe(tf, config) do
                    {:ok, f, t, si, uf} -> {f, t, si, uf}
                    {:error, _} ->
                      default_to = DateTime.utc_now()
                      default_from = DateTime.shift(default_to, hour: -24)
                      {default_from, default_to, "24h", false}
                  end
              end
          end

        # If we have a timeframe parameter but no explicit from/to, calculate from timeframe
        params["timeframe"] && params["timeframe"] != "" ->
          case TimeframeParsing.parse_smart_timeframe(params["timeframe"], config) do
            {:ok, from, to, smart_input, use_fixed} -> {from, to, smart_input, use_fixed}
            {:error, _} ->
              # Fallback to defaults if timeframe parsing fails
              default_to = DateTime.utc_now()
              default_from = DateTime.shift(default_to, hour: -24)
              {default_from, default_to, "24h", false}
          end

        # Default case: use 24-hour range from now
        true ->
          tf = socket.assigns.database.default_timeframe || "24h"
          case TimeframeParsing.parse_smart_timeframe(tf, config) do
            {:ok, from, to, smart_input, use_fixed} -> {from, to, smart_input, use_fixed}
            {:error, _} ->
              default_to = DateTime.utc_now()
              default_from = DateTime.shift(default_to, hour: -24)
              {default_from, default_to, "24h", false}
          end
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
      |> assign(show_granularity_dropdown: false)

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

      socket = push_patch(socket, to: ~p"/app/dbs/#{socket.assigns.database.id}?#{url_params}")
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
  
  def handle_info({:hide_timeframe_dropdown, _component_id}, socket) do
    # Handle timeframe dropdown hide from FilterBar component
    {:noreply, socket}
  end
  
  def handle_info({:filter_bar, {:filter_changed, changes}}, socket) do
    require Logger
    Logger.info("DatabaseExploreLive.handle_info filter_bar: changes=#{inspect(changes)}")
    
    # Handle filter changes from the FilterBar component
    updated_socket = Enum.reduce(changes, socket, fn {key, value}, acc ->
      assign(acc, key, value)
    end)
    
    # Update URL with new parameters if needed
    if Map.has_key?(changes, :from) or Map.has_key?(changes, :to) or Map.has_key?(changes, :granularity) or Map.has_key?(changes, :use_fixed_display) do
      base_params = %{
        timeframe: updated_socket.assigns.smart_timeframe_input,
        granularity: updated_socket.assigns.granularity
      }
      url_params =
        if updated_socket.assigns.use_fixed_display do
          Map.merge(base_params, %{
            from: if(updated_socket.assigns.from, do: DateTime.to_iso8601(updated_socket.assigns.from), else: nil),
            to: if(updated_socket.assigns.to, do: DateTime.to_iso8601(updated_socket.assigns.to), else: nil)
          })
        else
          base_params
        end
      
      # Add key parameter if it exists
      url_params = if updated_socket.assigns.key, 
        do: Map.put(url_params, :key, updated_socket.assigns.key), 
        else: url_params
      
      # Just update URL - let handle_params handle the data loading to avoid double loading
      {:noreply, push_patch(updated_socket, to: ~p"/app/dbs/#{updated_socket.assigns.database.id}?#{url_params}")}
    else
      {:noreply, updated_socket}
    end
  end

  # Toggle Play/Pause in Explore (defensive handler in parent LiveView)
  def handle_event("toggle_play_pause", _params, socket) do
    socket =
      if socket.assigns.use_fixed_display do
        tf = socket.assigns.smart_timeframe_input || (socket.assigns.database.default_timeframe || "24h")
        config = socket.assigns.database_config
        case TimeframeParsing.parse_smart_timeframe(tf, config) do
          {:ok, from, to, smart, _} -> assign(socket, from: from, to: to, smart_timeframe_input: smart, use_fixed_display: false)
          {:error, _} -> assign(socket, use_fixed_display: false)
        end
      else
        assign(socket, use_fixed_display: true)
      end

    reload_current_timeframe(socket)
  end

  # Progress message handling
  def handle_info({:loading_progress, progress_map}, socket) do
    {:noreply, assign(socket, :loading_progress, progress_map)}
  end

  def handle_info({:transponding, state}, socket) do
    {:noreply, assign(socket, :transponding, state)}
  end

  def handle_async(:data_task, {:ok, data}, socket) do
    # Handle both single system stats and dual system+key stats
    load_duration = System.monotonic_time(:microsecond) - socket.assigns.load_start_time
    
    case data do
      %{system: system_stats, key: key_stats, key_transponder_results: key_transponder_results} ->
        # When specific key is selected:
        # - Use system stats for keys summary AND chart (events count)
        # - Use key stats only for table data
        keys_sum = reduce_stats(system_stats.series[:values] || [])
        # Chart always shows events from system data, for the specific key
        timeline = series_from(system_stats.series, ["keys", socket.assigns.key])
        timeline_data = Jason.encode!(timeline["keys.#{socket.assigns.key}"])
        selected_key_color = get_key_color(keys_sum, socket.assigns.key)
        table_stats = Trifle.Stats.Tabler.tabulize(key_stats.series)
        
        {:noreply,
         socket
         |> assign(loading: false)
         |> assign(loading_chunks: false)
         |> assign(loading_progress: nil)
         |> assign(transponding: false)
         |> assign(stats: table_stats)
         |> assign(keys: keys_sum)
         |> assign(timeline: timeline_data)
         |> assign(chart_type: "single")
         |> assign(selected_key_color: selected_key_color)
         |> assign(key_transponder_results: key_transponder_results)
         |> assign(load_duration_microseconds: load_duration)}
         
      %{system: system_stats} ->
        # When no specific key is selected, use system stats for everything
        keys_sum = reduce_stats(system_stats.series[:values] || [])
        timeline = series_from_all_keys(system_stats.series, keys_sum)
        timeline_data = Jason.encode!(timeline)
        table_stats = Trifle.Stats.Tabler.tabulize(system_stats.series)
        
        {:noreply,
         socket
         |> assign(loading: false)
         |> assign(loading_chunks: false)
         |> assign(loading_progress: nil)
         |> assign(transponding: false)
         |> assign(stats: table_stats)
         |> assign(keys: keys_sum)
         |> assign(timeline: timeline_data)
         |> assign(chart_type: "stacked")
         |> assign(selected_key_color: nil)
         |> assign(load_duration_microseconds: load_duration)}
         
      raw_stats ->
        # Fallback: handle raw stats directly (legacy format)
        keys_sum = reduce_stats(raw_stats[:values] || [])
        
        {timeline_data, chart_type} =
          if socket.assigns.key && socket.assigns.key != "" do
            timeline = series_from(raw_stats, ["keys", socket.assigns.key])
            {Jason.encode!(timeline["keys.#{socket.assigns.key}"]), "single"}
          else
            timeline = series_from_all_keys(raw_stats, keys_sum)
            {Jason.encode!(timeline), "stacked"}
          end

        selected_key_color =
          if socket.assigns.key && socket.assigns.key != "" do
            get_key_color(keys_sum, socket.assigns.key)
          else
            nil
          end

        table_stats = Trifle.Stats.Tabler.tabulize(raw_stats)

        {:noreply,
         socket
         |> assign(loading: false)
         |> assign(loading_chunks: false)
         |> assign(loading_progress: nil)
         |> assign(transponding: false)
         |> assign(stats: table_stats)
         |> assign(keys: keys_sum)
         |> assign(timeline: timeline_data)
         |> assign(chart_type: chart_type)
         |> assign(selected_key_color: selected_key_color)
         |> assign(load_duration_microseconds: load_duration)}
    end
  end

  def handle_async(:data_task, {:error, error}, socket) do
    load_duration = System.monotonic_time(:microsecond) - socket.assigns.load_start_time
    
    {:noreply,
     socket
     |> assign(loading: false)
     |> assign(loading_chunks: false)
     |> assign(loading_progress: nil)
     |> assign(transponding: false)
     |> assign(load_duration_microseconds: load_duration)
     |> put_flash(:error, "Failed to load data: #{inspect(error)}")}
  end

  def handle_async(:data_task, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(loading: false)
     |> assign(loading_chunks: false)
     |> assign(loading_progress: nil)
     |> assign(transponding: false)
     |> put_flash(:error, "Data loading failed: #{inspect(reason)}")}
  end






  defp load_data_and_update_socket(socket) do
    # Start timing the data loading process
    socket = assign(socket, 
      load_start_time: System.monotonic_time(:microsecond),
      loading: true,
      loading_chunks: true,
      loading_progress: nil,
      transponding: false
    )

    # Extract values to avoid async socket warnings
    database = socket.assigns.database
    key = socket.assigns.key
    granularity = socket.assigns.granularity
    from = socket.assigns.from
    to = socket.assigns.to
    liveview_pid = self() # Capture LiveView PID before async task

    # Create progress callback to send updates back to LiveView
    progress_callback = fn progress_info ->
      case progress_info do
        {:chunk_progress, current, total} ->
          send(liveview_pid, {:loading_progress, %{current: current, total: total}})
        {:transponder_progress, :starting} ->
          send(liveview_pid, {:transponding, true})
      end
    end

    # Use SeriesFetcher for all data loading to ensure consistent transponder application
    {:noreply, start_async(socket, :data_task, fn ->
      if key && key != "" do
        # Get transponders that match the specific key
        matching_transponders = Organizations.list_transponders_for_database(database)
        |> Enum.filter(&(&1.enabled))
        |> Enum.filter(fn transponder -> key_matches_pattern?(key, transponder.key) end)
        |> Enum.sort_by(& &1.order)

        # Load both system key (no transponders) and specific key (with transponders)
        case {SeriesFetcher.fetch_series(database, "__system__key__", from, to, granularity, [], progress_callback: progress_callback),
              SeriesFetcher.fetch_series(database, key, from, to, granularity, matching_transponders, progress_callback: progress_callback)} do
          {{:ok, system_result}, {:ok, key_result}} ->
            %{system: system_result.series, key: key_result.series, key_transponder_results: key_result.transponder_results}
          {{:error, error}, _} ->
            {:error, {:system_key_failed, error}}
          {_, {:error, error}} ->
            {:error, {:specific_key_failed, error}}
        end
      else
        # Only load system key when no specific key is selected (no transponders)
        case SeriesFetcher.fetch_series(database, "__system__key__", from, to, granularity, [], progress_callback: progress_callback) do
          {:ok, result} -> %{system: result.series}
          {:error, error} -> {:error, error}
        end
      end
    end, timeout: 300_000)}
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
      # Convert to naive datetime to preserve the local time representation
      naive = DateTime.to_naive(a)
      # Create UTC datetime with the same time values to display correctly in charts
      utc_dt = DateTime.from_naive!(naive, "Etc/UTC")
      unix_ms = DateTime.to_unix(utc_dt, :millisecond)
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
            # Convert to naive datetime to preserve the local time representation
            naive = DateTime.to_naive(a)
            # Create UTC datetime with the same time values to display correctly in charts
            utc_dt = DateTime.from_naive!(naive, "Etc/UTC")
            unix_ms = DateTime.to_unix(utc_dt, :millisecond)
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




  def filter_keys(keys, filter) when filter == "" or is_nil(filter) do
    keys |> Enum.sort_by(fn {key, _count} -> key end)
  end

  def filter_keys(keys, filter) when is_binary(filter) do
    filter_lower = String.downcase(filter)
    keys
    |> Enum.filter(fn {key, _count} ->
      String.contains?(String.downcase(key), filter_lower)
    end)
    |> Enum.sort_by(fn {key, _count} -> key end)
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

  def get_summary_stats(assigns) do
    case assigns do
      %{key: key, stats: stats, transponder_info: transponder_info, key_transponder_results: key_transponder_results} when not is_nil(key) and key != "" and not is_nil(stats) ->
        # Count columns (timeline points)
        column_count = if stats[:at], do: length(stats[:at]), else: 0
        
        # Count paths (rows)
        path_count = if stats[:paths], do: length(stats[:paths]), else: 0
        
        # Use actual transponder results from SeriesFetcher
        successful_transponders = length(key_transponder_results.successful)
        failed_transponders = length(key_transponder_results.failed)
        transponder_errors = key_transponder_results.errors

        %{
          key: key,
          column_count: column_count,
          path_count: path_count,
          matching_transponders: successful_transponders + failed_transponders,
          successful_transponders: successful_transponders,
          failed_transponders: failed_transponders,
          transponder_errors: transponder_errors
        }
        
      %{key: key, stats: stats} when (is_nil(key) or key == "") and not is_nil(stats) ->
        # When no key is selected, show system overview stats (no transponders)
        # Count columns (timeline points)
        column_count = if stats[:at], do: length(stats[:at]), else: 0
        
        # Count paths (rows)
        path_count = if stats[:paths], do: length(stats[:paths]), else: 0
        
        %{
          key: nil,
          column_count: column_count,
          path_count: path_count,
          matching_transponders: 0,
          successful_transponders: 0,
          failed_transponders: 0,
          transponder_errors: []
        }
        
      _ ->
        nil
    end
  end

  def format_nested_path(path, all_paths, transponder_info \\ %{}) when is_binary(path) do
    transponder_name = Map.get(transponder_info, path)

    formatted_path = path
    |> String.split(".")
    |> build_nested_html(all_paths, [])
    |> Enum.join(".")

    if transponder_name do
      # Escape the transponder name for safe HTML attribute usage
      escaped_name = Phoenix.HTML.html_escape(transponder_name) |> Phoenix.HTML.safe_to_string()
      tooltip_text = "Generated by transponder: #{escaped_name}"

      # Add SVG icon aligned to the right with grayer color and fast JavaScript tooltip
      ~s(<span style="display: flex; justify-content: space-between; align-items: center;">#{formatted_path}<span style="margin-left: auto; padding-left: 4px;" data-tooltip="#{tooltip_text}"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" style="width: 12px; height: 12px; color: #9CA3AF;"><path fill-rule="evenodd" d="M9.638 1.093a.75.75 0 0 1 .724 0l2 1.104a.75.75 0 1 1-.724 1.313L10 2.607l-1.638.903a.75.75 0 1 1-.724-1.313l2-1.104ZM5.403 4.287a.75.75 0 0 1-.295 1.019l-.805.444.805.444a.75.75 0 0 1-.724 1.314L3.5 7.02v.73a.75.75 0 0 1-1.5 0v-2a.75.75 0 0 1 .388-.657l1.996-1.1a.75.75 0 0 1 1.019.294Zm9.194 0a.75.75 0 0 1 1.02-.295l1.995 1.101A.75.75 0 0 1 18 5.75v2a.75.75 0 0 1-1.5 0v-.73l-.884.488a.75.75 0 1 1-.724-1.314l.806-.444-.806-.444a.75.75 0 0 1-.295-1.02ZM7.343 8.284a.75.75 0 0 1 1.02-.294L10 8.893l1.638-.903a.75.75 0 1 1 .724 1.313l-1.612.89v1.557a.75.75 0 0 1-1.5 0v-1.557l-1.612-.89a.75.75 0 0 1-.295-1.019ZM2.75 11.5a.75.75 0 0 1 .75.75v1.557l1.608.887a.75.75 0 0 1-.724 1.314l-1.996-1.101A.75.75 0 0 1 2 14.25v-2a.75.75 0 0 1 .75-.75Zm14.5 0a.75.75 0 0 1 .75.75v2a.75.75 0 0 1-.388.657l-1.996 1.1a.75.75 0 1 1-.724-1.313l1.608-.887V12.25a.75.75 0 0 1 .75-.75Zm-7.25 4a.75.75 0 0 1 .75.75v.73l.888-.49a.75.75 0 0 1 .724 1.313l-2 1.104a.75.75 0 0 1-.724 0l-2-1.104a.75.75 0 1 1 .724-1.313l.888.49v-.73a.75.75 0 0 1 .75-.75Z" clip-rule="evenodd" /></svg></span></span>)
    else
      formatted_path
    end
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
    <div class="flex flex-col dark:bg-slate-900 min-h-screen relative">
    <!-- Loading Overlay (covers entire page content; message at 1/3 height) -->
    <%= if (@loading_chunks && @loading_progress) || @transponding do %>
      <div class="absolute inset-0 bg-white bg-opacity-75 dark:bg-slate-900 dark:bg-opacity-90 z-50">
        <div class="absolute left-1/2 -translate-x-1/2" style="top: 33%;">
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
      </div>
    <% end %>
    <!-- Tab Navigation -->
    <div class="mb-6 border-b border-gray-200 dark:border-slate-700">
      <nav class="-mb-px space-x-8" aria-label="Tabs">
        <.link
          navigate={~p"/app/dbs/#{@database.id}"}
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


    <!-- Filter Bar Component -->
    <.live_component 
      module={TrifleApp.Components.FilterBar}
      id="explore-filter-bar"
      config={@database_config}
      granularity={@granularity}
      available_granularities={@available_granularities}
      from={@from}
      to={@to}
      smart_timeframe_input={@smart_timeframe_input}
      use_fixed_display={@use_fixed_display}
      show_timeframe_dropdown={@show_timeframe_dropdown}
      show_granularity_dropdown={@show_granularity_dropdown}
      show_controls={true}
    />

    <!-- Row 2: Activity/Events Chart -->
    <div class="sticky top-16 z-40 mb-6">
      <div class="bg-white dark:bg-slate-800 rounded-lg shadow py-1 px-3" style="height: 160px;">
        <%= if map_size(@keys) == 0 && !(@loading_chunks || @transponding) do %>
          <!-- Empty State: No Data Tracked -->
          <div class="flex flex-col items-center justify-center h-full text-center">
            <div class="space-y-2">
              <div class="flex items-center justify-center gap-2">
                <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
                  Nothing to see here... yet
                </h3>
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6 text-gray-500 dark:text-slate-400">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M15.362 5.214A8.252 8.252 0 0 1 12 21 8.25 8.25 0 0 1 6.038 7.047 8.287 8.287 0 0 0 9 9.601a8.983 8.983 0 0 1 3.361-6.867 8.21 8.21 0 0 0 3 2.48Z" />
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 18a3.75 3.75 0 0 0 .495-7.468 5.99 5.99 0 0 0-1.925 3.547 5.975 5.975 0 0 1-2.133-1.001A3.75 3.75 0 0 0 12 18Z" />
                </svg>
              </div>
              <p class="text-sm text-gray-500 dark:text-slate-400 max-w-md">
                Your dashboard is having trust issues with empty data. Feed it some metrics and it'll start showing off!
              </p>
              <div class="mt-4">
                <.link
                  navigate={~p"/app/dbs/#{@database.id}/transponders"}
                  class="inline-flex items-center gap-2 text-sm font-medium text-teal-600 hover:text-teal-700 dark:text-teal-400 dark:hover:text-teal-300"
                >
                  <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="m21 7.5-2.25-1.313M21 7.5v2.25m0-2.25l-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3l2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75l2.25-1.313M12 21.75V19.5m0 2.25l2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25" />
                  </svg>
                  Set up Transponders →
                </.link>
              </div>
            </div>
          </div>
        <% else %>
          <!-- Chart (when data exists) -->
          <div
            id="timeline-hook"
            phx-hook="DatabaseExploreChart"
            data-events={@timeline}
            data-key={@key}
            data-timezone={@database.time_zone || "UTC"}
            data-chart-type={@chart_type}
            data-colors={ChartColors.json_palette()}
            data-selected-key-color={@selected_key_color}
            class=""
          >
          </div>
          <div id="timeline-chart-wrapper" phx-update="ignore" class="mt-5 h-full">
            <div id="timeline-chart"></div>
          </div>
        <% end %>
      </div>
    </div>

    <!-- Row 3: Key Selection -->
    <div class="mb-6">
      <.data_table>
        <:header>
          <.table_header 
            title="Keys" 
            count={length(filter_keys(@keys, @key_search_filter))}
          >
            <:search>
              <div class="relative">
                <input
                  type="text"
                  placeholder="Search keys..."
                  value={@key_search_filter}
                  phx-keyup="filter_keys"
                  class="block w-64 rounded-md border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-xs !pl-9"
                />
                <div class="absolute inset-y-0 left-2 flex items-center">
                  <svg class="h-4 w-4 text-gray-400 dark:text-slate-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                  </svg>
                </div>
              </div>
            </:search>
          </.table_header>
        </:header>
        
        <:body>
          <div class="h-48 overflow-auto rounded-b-lg"> <!-- Fixed height for ~3 items with scrolling -->
            <ul role="list" class="divide-y divide-gray-100 dark:divide-slate-700 rounded-b-lg overflow-hidden">
              <%= for {key, count} <- filter_keys(@keys, @key_search_filter) do %>
                <li class={
                    if @key == key,
                      do: "relative bg-teal-50 dark:bg-teal-900/30",
                      else: "relative bg-white dark:bg-transparent hover:bg-gray-50 dark:hover:bg-slate-700"
                  }>
                  <button
                    type="button"
                    phx-click={if @key == key, do: "deselect_key", else: "select_key"}
                    phx-value-key={key}
                    class="w-full py-2 px-4 sm:px-6 lg:px-8 text-left min-w-max"
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
                            class="h-5 w-5 text-gray-400 dark:text-slate-400 flex-shrink-0"
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
                            class="text-sm font-semibold font-mono leading-6 whitespace-nowrap"
                            style={"color: #{get_key_color(@keys, key)} !important"}
                          >
                            {key}
                          </p>
                        </div>
                      </div>
                      <div class="flex items-center gap-x-4">
                        <span
                          class="inline-flex items-center rounded-md px-2 py-1 text-xs font-medium border float-right"
                          style={"background-color: #{get_key_color(@keys, key)}15; color: #{get_key_color(@keys, key)} !important; border-color: #{get_key_color(@keys, key)}40 !important"}
                        >
                          {format_number(count)}
                        </span>
                        <svg
                          class="h-5 w-5 flex-none text-gray-400 dark:text-slate-400"
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
                <div class="flex items-center justify-center h-48 text-gray-500 dark:text-slate-400 text-sm">
                  <span>No keys found</span>
                </div>
              <% end %>
            </ul>
          </div>
        </:body>
      </.data_table>
    </div>

    <!-- Row 4: Data for Selected Key -->
    <div class="flex-1 flex flex-col min-h-0">
      <%= if @stats do %>
        <div id="phantom-rows-container" class="flex-1 bg-white dark:bg-slate-800 flex flex-col min-h-0" phx-hook="PhantomRows">
          <div
            class="flex-1 overflow-x-auto overflow-y-auto relative"
            id="table-hover-container"
            phx-hook="TableHover"
          >
            <table class="min-w-full divide-y divide-gray-300 dark:divide-slate-600 overflow-auto" id="data-table" phx-hook="FastTooltip" style="table-layout: fixed;">
              <thead>
                <tr>
                  <th
                    scope="col"
                    class="top-0 lg:left-0 lg:sticky bg-white dark:bg-slate-800 whitespace-nowrap py-2 pl-4 pr-3 text-left text-xs font-semibold text-gray-900 dark:text-white pl-4 h-16 z-20 border-r border-gray-300 dark:border-slate-600 lg:border-r-0 lg:shadow-[1px_0_2px_-1px_rgba(209,213,219,0.8)] dark:lg:shadow-[1px_0_2px_-1px_rgba(71,85,105,0.8)]"
                    style="width: 200px;"
                  >
                    Path
                  </th>
                  <%= for {at, col_index} <- Enum.reverse(@stats[:at]) |> Enum.with_index(1) do %>
                    <th
                      scope="col"
                      class="top-0 sticky whitespace-nowrap px-2 py-2 text-left text-xs font-mono font-semibold text-teal-700 dark:text-teal-400 bg-white dark:bg-slate-800 h-16 align-top z-10 transition-colors duration-150"
                      data-col={col_index}
                      style="width: 120px;"
                    >
                      {format_table_timestamp(at, @granularity)}
                    </th>
                  <% end %>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200 dark:divide-slate-700 bg-white dark:bg-slate-800">
                <%= for {path, row_index} <- @stats[:paths] |> Enum.with_index(1) do %>
                  <tr data-row={row_index}>
                    <td
                      class="lg:left-0 lg:sticky bg-white dark:bg-slate-800 whitespace-nowrap py-1 pl-4 pr-3 text-xs font-mono text-gray-900 dark:text-white pl-4 z-10 transition-colors duration-150 border-r border-gray-300 dark:border-slate-600 lg:border-r-0 lg:shadow-[1px_0_2px_-1px_rgba(209,213,219,0.8)] dark:lg:shadow-[1px_0_2px_-1px_rgba(71,85,105,0.8)]"
                        data-row={row_index}
                    >
                      {format_nested_path(path, @stats[:paths], @transponder_info)}
                    </td>
                    <%= for {at, col_index} <- Enum.reverse(@stats[:at]) |> Enum.with_index(1) do %>
                      <% value = @stats[:values][{path, at}] %>
                      <%= if value do %>
                        <td
                          class="whitespace-nowrap px-2 py-1 text-xs font-medium text-gray-900 dark:text-white transition-colors duration-150 cursor-pointer"
                          data-row={row_index}
                          data-col={col_index}
                        >
                          {value}
                        </td>
                      <% else %>
                        <td
                          class="whitespace-nowrap px-2 py-1 text-xs font-medium text-gray-300 dark:text-slate-500 transition-colors duration-150 cursor-pointer"
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
            
            <!-- Border after last row -->
            <div class="border-t border-gray-200 dark:border-slate-700"></div>
          </div>
          
        </div>
        
        <!-- Sticky Summary Footer -->
        <%= if summary = get_summary_stats(assigns) do %>
          <div class="sticky bottom-0 border-t border-gray-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-4 py-3 shadow-lg z-30">
              <div class="flex flex-wrap items-center gap-4 text-xs">
                <!-- Selected Key (only show if key is selected) -->
                <%= if summary.key do %>
                  <div class="flex items-center gap-1">
                    <svg class="h-4 w-4 text-teal-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M12 3c2.755 0 5.455.232 8.083.678.533.09.917.556.917 1.096v1.044a2.25 2.25 0 0 1-.659 1.591l-5.432 5.432a2.25 2.25 0 0 0-.659 1.591v2.927a2.25 2.25 0 0 1-1.244 2.013L9.75 21v-6.568a2.25 2.25 0 0 0-.659-1.591L3.659 7.409A2.25 2.25 0 0 1 3 5.818V4.774c0-.54.384-1.006.917-1.096A48.32 48.32 0 0 1 12 3Z" />
                    </svg>
                    <span class="font-medium text-gray-700 dark:text-slate-300">Key:</span>
                    <span class="font-mono text-gray-900 dark:text-white max-w-xs truncate" title={summary.key}>{summary.key}</span>
                  </div>
                <% end %>

                <!-- Columns -->
                <div class="flex items-center gap-1">
                  <svg class="h-4 w-4 text-teal-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M9 4.5v15m6-15v15m-10.875 0h15.75c.621 0 1.125-.504 1.125-1.125V5.625c0-.621-.504-1.125-1.125-1.125H4.125C3.504 4.5 3 5.004 3 5.625v12.75c0 .621.504 1.125 1.125 1.125Z" />
                  </svg>
                  <span class="font-medium text-gray-700 dark:text-slate-300">Columns:</span>
                  <span class="text-gray-900 dark:text-white">{summary.column_count}</span>
                </div>

                <!-- Paths -->
                <div class="flex items-center gap-1">
                  <svg class="h-4 w-4 text-teal-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5" />
                  </svg>
                  <span class="font-medium text-gray-700 dark:text-slate-300">Paths:</span>
                  <span class="text-gray-900 dark:text-white">{summary.path_count}</span>
                </div>

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
                    <span class="text-gray-900 dark:text-white">{summary.successful_transponders}</span>
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
                        {summary.failed_transponders}
                      </button>
                    <% else %>
                      <span class="text-gray-900 dark:text-white">0</span>
                    <% end %>
                  </div>
                </div>
                
                <!-- Load Speed -->
                <%= if @load_duration_microseconds do %>
                  <div class="flex items-center gap-1">
                    <svg class="h-4 w-4 text-teal-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" d="m3.75 13.5 10.5-11.25L12 10.5h8.25L9.75 21.75 12 13.5H3.75Z" />
                    </svg>
                    <span class="text-gray-900 dark:text-white">{format_duration(@load_duration_microseconds)}</span>
                  </div>
                <% end %>
              </div>
          </div>
        <% end %>
      <% else %>
        <div class="bg-white dark:bg-slate-800 p-8">
          <div class="text-gray-500 dark:text-slate-300 text-center">
            <p class="text-lg">↑ Select a key to view detailed data</p>
            <p class="text-sm mt-2">
              The chart above shows a stacked view of all events in this database.
            </p>
          </div>
        </div>
      <% end %>
    </div>
    
    <!-- Transponder Error Modal -->
    <%= if @show_error_modal do %>
      <% modal_summary = get_summary_stats(assigns) %>
      <%= if modal_summary && length(modal_summary.transponder_errors) > 0 do %>
        <div class="fixed inset-0 z-50 overflow-y-auto" phx-click="hide_transponder_errors">
          <div class="flex items-center justify-center min-h-screen px-4 pt-4 pb-20 text-center sm:block sm:p-0">
            <div class="fixed inset-0 transition-opacity bg-gray-500 bg-opacity-75 dark:bg-gray-900 dark:bg-opacity-75"></div>
            
            <div class="inline-block align-bottom bg-white dark:bg-slate-800 rounded-lg px-4 pt-5 pb-4 text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-3xl sm:w-full sm:p-6" phx-click-away="hide_transponder_errors">
              <div class="sm:flex sm:items-start">
                <div class="mx-auto flex-shrink-0 flex items-center justify-center h-12 w-12 rounded-full bg-red-100 dark:bg-red-900/30 sm:mx-0 sm:h-10 sm:w-10">
                  <svg class="h-6 w-6 text-red-600 dark:text-red-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.664-.833-2.464 0L3.34 16.5c-.77.833.192 2.5 1.732 2.5z" />
                  </svg>
                </div>
                <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left w-full">
                  <h3 class="text-lg leading-6 font-medium text-gray-900 dark:text-white">
                    Transponder Errors
                  </h3>
                  <div class="mt-4">
                    <div class="space-y-4">
                      <%= for error <- modal_summary.transponder_errors do %>
                        <div class="border border-red-200 dark:border-red-800 rounded-lg p-4 bg-red-50 dark:bg-red-900/20">
                          <div class="flex items-center justify-between mb-2">
                            <h4 class="font-medium text-red-800 dark:text-red-300">
                              {error.transponder.name || error.transponder.key}
                            </h4>
                            <span class="text-xs text-red-600 dark:text-red-400 bg-red-100 dark:bg-red-900/50 px-2 py-1 rounded">
                              {error.transponder.type}
                            </span>
                          </div>
                          <p class="text-sm text-red-700 dark:text-red-300 font-mono">
                            {error.error.message}
                          </p>
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
              <div class="mt-5 sm:mt-4 sm:flex sm:flex-row-reverse">
                <button
                  type="button"
                  phx-click="hide_transponder_errors"
                  class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-gray-600 text-base font-medium text-white hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500 sm:ml-3 sm:w-auto sm:text-sm"
                >
                  Close
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    <% end %>
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

end
