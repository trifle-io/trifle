defmodule TrifleApp.ProjectLive do
  use TrifleApp, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.Project
  alias TrifleApp.DesignSystem.ChartColors

  require IEx

  def mount(params, _session, socket) do
    project = Organizations.get_project!(params["id"])

    socket =
      socket
      |> assign(page_title: ["Projects", project.name, "Explore"])
      |> assign(project: project)
      |> assign(stats: nil)
      |> assign(timeline: "")
      |> assign(smart_timeframe_input: nil)
      |> assign(show_timeframe_dropdown: false)
      |> assign(show_sensitivity_dropdown: false)

    {:ok, socket}
  end

  def parse_date(date, time_zone) do
    # Parse as naive datetime and assume it's in the project timezone
    # This is correct for HTML datetime-local inputs which are timezone-naive
    case NaiveDateTime.from_iso8601(date) do
      {:ok, naive} -> {:ok, DateTime.from_naive!(naive, time_zone)}
      {:error, _} -> DateTime.now(time_zone, Tzdata.TimeZoneDatabase)
    end
  end

  def format_for_datetime_input(datetime) do
    datetime
    # Remove microseconds
    |> DateTime.truncate(:second)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_iso8601()
  end

  def format_timeframe_display(from, to) do
    from_formatted = from |> DateTime.to_date() |> Date.to_string()
    to_formatted = to |> DateTime.to_date() |> Date.to_string()

    if from_formatted == to_formatted do
      "#{from_formatted} #{DateTime.to_time(from) |> Time.to_string()} - #{DateTime.to_time(to) |> Time.to_string()}"
    else
      "#{from_formatted} - #{to_formatted}"
    end
  end

  def format_smart_timeframe_display(smart_input) when is_nil(smart_input), do: ""

  def format_smart_timeframe_display(smart_input) do
    # Map of short values to full descriptions
    preset_labels = %{
      "5m" => "Last 5 minutes",
      "15m" => "Last 15 minutes",
      "30m" => "Last 30 minutes",
      "1h" => "Last 1 hour",
      "4h" => "Last 4 hours",
      "1d" => "Last 1 day",
      "2d" => "Last 2 days",
      "1w" => "Last 1 week",
      "1mo" => "Last 1 month"
    }

    case preset_labels[smart_input] do
      # Return original input if no preset match
      nil -> smart_input
      # Format as "7d Last 7 days"
      label -> "#{smart_input} #{label}"
    end
  end

  def get_smart_timeframe_description(smart_input) when is_nil(smart_input), do: ""

  def get_smart_timeframe_description(smart_input) do
    # First check if it's a preset
    preset_labels = %{
      "5m" => "Last 5 minutes",
      "15m" => "Last 15 minutes",
      "30m" => "Last 30 minutes",
      "1h" => "Last 1 hour",
      "4h" => "Last 4 hours",
      "1d" => "Last 1 day",
      "2d" => "Last 2 days",
      "1w" => "Last 1 week",
      "1mo" => "Last 1 month"
    }

    case preset_labels[smart_input] do
      nil ->
        # Not a preset, try to generate description dynamically
        generate_description_from_shorthand(smart_input)

      description ->
        description
    end
  end

  def generate_description_from_shorthand(input) do
    cond do
      # Handle months (mo)
      Regex.match?(~r/^(\d+)mo$/i, input) ->
        [_, amount_str] = Regex.run(~r/^(\d+)mo$/i, input)
        amount = String.to_integer(amount_str)
        unit_name = if amount == 1, do: "month", else: "months"
        "Last #{amount} #{unit_name}"

      # Handle years (y)
      Regex.match?(~r/^(\d+)y$/i, input) ->
        [_, amount_str] = Regex.run(~r/^(\d+)y$/i, input)
        amount = String.to_integer(amount_str)
        unit_name = if amount == 1, do: "year", else: "years"
        "Last #{amount} #{unit_name}"

      # Handle other units (m, h, d, w)
      Regex.match?(~r/^(\d+)([mhdw])$/i, input) ->
        [_, amount_str, unit] = Regex.run(~r/^(\d+)([mhdw])$/i, input)
        amount = String.to_integer(amount_str)

        unit_name =
          case String.downcase(unit) do
            "m" -> if amount == 1, do: "minute", else: "minutes"
            "h" -> if amount == 1, do: "hour", else: "hours"
            "d" -> if amount == 1, do: "day", else: "days"
            "w" -> if amount == 1, do: "week", else: "weeks"
          end

        "Last #{amount} #{unit_name}"

      true ->
        # Return as-is if no pattern match
        input
    end
  end

  def find_short_code_from_description(input) do
    # Reverse lookup: find short code from description
    preset_map = %{
      "Last 5 minutes" => "5m",
      "Last 15 minutes" => "15m",
      "Last 30 minutes" => "30m",
      "Last 1 hour" => "1h",
      "Last 4 hours" => "4h",
      "Last 1 day" => "1d",
      "Last 2 days" => "2d",
      "Last 1 week" => "1w",
      "Last 1 month" => "1mo"
    }

    preset_map[input]
  end

  def extract_short_value_from_display(display_text) do
    # Extract short value from formatted display (e.g., "7d Last 7 days" -> "7d", "6mo Last 6 months" -> "6mo")
    case Regex.run(~r/^(\d+(?:mo|[mhdwy]))\s/, display_text) do
      [_, short_value] -> short_value
      # Return as-is if no pattern match (for custom inputs)
      _ -> display_text
    end
  end

  def get_timezone_offset_display(time_zone) do
    # Get current timezone offset for display
    case DateTime.now(time_zone, Tzdata.TimeZoneDatabase) do
      {:ok, tz_time} ->
        # Extract offset directly from the DateTime struct
        offset_seconds = tz_time.utc_offset + tz_time.std_offset
        offset_hours = div(offset_seconds, 3600)
        offset_minutes = div(rem(abs(offset_seconds), 3600), 60)

        # Format as +HH:MM or -HH:MM
        sign = if offset_seconds >= 0, do: "+", else: "-"

        "#{sign}#{String.pad_leading(to_string(abs(offset_hours)), 2, "0")}:#{String.pad_leading(to_string(offset_minutes), 2, "0")}"

      # Fallback to UTC
      {:error, _} ->
        "+00:00"
    end
  end

  def parse_smart_timeframe(input, time_zone) do
    # Parse smart timeframe inputs like "5m", "2h", "1d", "3w", "6mo", "1y"
    cond do
      # Handle months (mo)
      Regex.match?(~r/^(\d+)mo$/i, input) ->
        [_, amount_str] = Regex.run(~r/^(\d+)mo$/i, input)
        amount = String.to_integer(amount_str)
        now = DateTime.utc_now() |> DateTime.shift_zone!(time_zone)
        from = DateTime.shift(now, month: -amount)
        {:ok, from, now}

      # Handle years (y)
      Regex.match?(~r/^(\d+)y$/i, input) ->
        [_, amount_str] = Regex.run(~r/^(\d+)y$/i, input)
        amount = String.to_integer(amount_str)
        now = DateTime.utc_now() |> DateTime.shift_zone!(time_zone)
        from = DateTime.shift(now, year: -amount)
        {:ok, from, now}

      # Handle other units (m, h, d, w)
      Regex.match?(~r/^(\d+)([mhdw])$/i, input) ->
        [_, amount_str, unit] = Regex.run(~r/^(\d+)([mhdw])$/i, input)
        amount = String.to_integer(amount_str)
        now = DateTime.utc_now() |> DateTime.shift_zone!(time_zone)

        from =
          case String.downcase(unit) do
            "m" -> DateTime.shift(now, minute: -amount)
            "h" -> DateTime.shift(now, hour: -amount)
            "d" -> DateTime.shift(now, day: -amount)
            "w" -> DateTime.shift(now, week: -amount)
          end

        {:ok, from, now}

      true ->
        {:error, "Invalid format. Use formats like: 5m, 2h, 1d, 3w, 6mo, 1y"}
    end
  end

  def handle_event("fetch", params, socket) do
    range = params["range"]
    {:ok, from} = parse_date(params["from"], socket.assigns.project.time_zone)
    {:ok, to} = parse_date(params["to"], socket.assigns.project.time_zone)

    socket =
      socket
      |> assign(range: range, from: from, to: to)
      # Clear smart input when using manual form
      |> assign(smart_timeframe_input: nil)
      |> push_patch(
        to:
          ~p"/projects/#{socket.assigns.project.id}?#{[range: range, from: format_for_datetime_input(from), to: format_for_datetime_input(to), key: socket.assigns.key]}"
      )

    {:noreply, socket}
  end

  def handle_event("show_timeframe_dropdown", _, socket) do
    {:noreply, assign(socket, show_timeframe_dropdown: true)}
  end

  def handle_event("hide_timeframe_dropdown", _, socket) do
    {:noreply, assign(socket, show_timeframe_dropdown: false)}
  end

  def handle_event("delayed_hide_timeframe_dropdown", _, socket) do
    # Add a small delay to allow click events to process first
    Process.send_after(self(), :hide_dropdown_after_delay, 150)
    {:noreply, socket}
  end

  def handle_event("select_timeframe_preset", %{"preset" => preset, "label" => _label}, socket) do
    case parse_smart_timeframe(preset, socket.assigns.project.time_zone) do
      {:ok, from, to} ->
        # Keep the current range/sensitivity unchanged
        range = socket.assigns.range

        socket =
          socket
          |> assign(from: from, to: to)
          |> assign(smart_timeframe_input: preset)
          |> assign(show_timeframe_dropdown: false)
          |> push_event("update_smart_timeframe_input", %{
            value: get_smart_timeframe_description(preset)
          })
          |> push_patch(
            to:
              ~p"/projects/#{socket.assigns.project.id}?#{[range: range, from: format_for_datetime_input(from), to: format_for_datetime_input(to), key: socket.assigns[:key] || "", timeframe: preset]}"
          )

        {:noreply, socket}

      {:error, _} ->
        {:noreply, assign(socket, show_timeframe_dropdown: false)}
    end
  end

  def handle_event("smart_timeframe_keydown", %{"key" => "Enter", "value" => input}, socket) do
    # If user typed a description, try to find the matching short code
    # If user typed a short code directly, use that
    short_input =
      case find_short_code_from_description(input) do
        # Use input as-is (might be a short code like "7d")
        nil -> input
        # Found matching short code
        short_code -> short_code
      end

    case parse_smart_timeframe(short_input, socket.assigns.project.time_zone) do
      {:ok, from, to} ->
        # Keep the current range/sensitivity unchanged
        range = socket.assigns.range

        socket =
          socket
          |> assign(from: from, to: to)
          |> assign(smart_timeframe_input: short_input)
          |> assign(show_timeframe_dropdown: false)
          |> push_event("update_smart_timeframe_input", %{
            value: get_smart_timeframe_description(short_input)
          })
          |> push_patch(
            to:
              ~p"/projects/#{socket.assigns.project.id}?#{[range: range, from: format_for_datetime_input(from), to: format_for_datetime_input(to), key: socket.assigns[:key] || "", timeframe: short_input]}"
          )

        {:noreply, socket}

      {:error, _} ->
        # Could add a flash message here for invalid input
        {:noreply, assign(socket, show_timeframe_dropdown: false)}
    end
  end

  def handle_event("smart_timeframe_keydown", _, socket) do
    # Handle other keydown events (ignore)
    {:noreply, socket}
  end

  def handle_event("select_sensitivity", %{"sensitivity" => sensitivity}, socket) do
    socket =
      socket
      |> assign(range: sensitivity)
      |> push_patch(
        to:
          ~p"/projects/#{socket.assigns.project.id}?#{[range: sensitivity, from: format_for_datetime_input(socket.assigns.from), to: format_for_datetime_input(socket.assigns.to), key: socket.assigns[:key] || "", timeframe: socket.assigns[:smart_timeframe_input]]}"
      )

    {:noreply, socket}
  end

  def determine_range_for_timeframe(from, to) do
    duration_seconds = DateTime.diff(to, from, :second)

    cond do
      # <= 1 hour
      duration_seconds <= 3600 -> "1m"
      # <= 1 day
      duration_seconds <= 86400 -> "1h"
      # <= 1 week
      duration_seconds <= 604_800 -> "1d"
      # <= 30 days
      duration_seconds <= 2_592_000 -> "1w"
      # <= 90 days
      duration_seconds <= 7_776_000 -> "1mo"
      # <= 1 year
      duration_seconds <= 31_536_000 -> "1mo"
      true -> "1y"
    end
  end

  @doc """
  Convert UI range values to trifle_stats granularity strings.
  This maintains backward compatibility with the existing UI.
  """
  def ui_range_to_granularity(range) do
    case range do
      # Standard granularities (1-unit intervals)
      "second" -> "1s"
      "minute" -> "1m"
      "hour" -> "1h"
      "day" -> "1d"
      "week" -> "1w"
      "month" -> "1mo"
      "quarter" -> "1q"
      "year" -> "1y"
      # Direct granularity strings (for future use or config)
      granularity when is_binary(granularity) -> granularity
      # Fallback for any other cases
      _ -> "1h"
    end
  end

  @doc """
  Get available granularities from the driver configuration.
  This allows the UI to display the actual supported granularities.
  """
  def get_available_granularities(project) do
    config = Project.stats_config(project)
    config.granularities
  end

  @doc """
  Convert granularity strings to human-readable labels for the UI.
  """
  def granularity_to_label(granularity) do
    case granularity do
      "1s" -> "Second"
      "1m" -> "Minute"
      "1h" -> "Hour"
      "1d" -> "Day"
      "1w" -> "Week"
      "1mo" -> "Month"
      "1q" -> "Quarter"
      "1y" -> "Year"
      # For custom granularities, show the raw value
      granularity -> granularity
    end
  end

  @doc """
  Get granularities with their labels and positions for the UI buttons.
  """
  def get_granularity_buttons(project) do
    granularities = get_available_granularities(project)

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

  @doc """
  Convert granularity string to old UI range format for backward compatibility.
  This is used for determining if a range button should be selected.
  """
  def granularity_to_ui_range(granularity) do
    case granularity do
      "1s" -> "second"
      "1m" -> "minute"
      "1h" -> "hour"
      "1d" -> "day"
      "1w" -> "week"
      "1mo" -> "month"
      "1q" -> "quarter"
      "1y" -> "year"
      # For custom granularities, return as-is
      granularity -> granularity
    end
  end

  def determine_smart_input_for_range(from, to, time_zone) do
    # Calculate if this matches a common timeframe pattern
    now = DateTime.utc_now() |> DateTime.shift_zone!(time_zone)
    duration_seconds = DateTime.diff(to, from, :second)

    # Check if 'to' is approximately now (within 5 minutes)
    time_diff_to_now = abs(DateTime.diff(to, now, :second))

    # Within 5 minutes of now
    if time_diff_to_now <= 300 do
      cond do
        # 5 minutes ±30s
        duration_seconds >= 300 && duration_seconds <= 330 -> "5m"
        # 15 minutes ±30s
        duration_seconds >= 870 && duration_seconds <= 930 -> "15m"
        # 30 minutes ±30s
        duration_seconds >= 1770 && duration_seconds <= 1830 -> "30m"
        # 1 hour ±1min
        duration_seconds >= 3540 && duration_seconds <= 3660 -> "1h"
        # 3 hours ±1min
        duration_seconds >= 10740 && duration_seconds <= 10860 -> "3h"
        # 6 hours ±1min
        duration_seconds >= 21540 && duration_seconds <= 21660 -> "6h"
        # 12 hours ±1min
        duration_seconds >= 43140 && duration_seconds <= 43260 -> "12h"
        # 24 hours ±1min
        duration_seconds >= 86340 && duration_seconds <= 86460 -> "24h"
        # 2 days ±1min
        duration_seconds >= 172_740 && duration_seconds <= 172_860 -> "2d"
        # 7 days ±1min
        duration_seconds >= 604_740 && duration_seconds <= 604_860 -> "7d"
        # 14 days ±1min
        duration_seconds >= 1_209_540 && duration_seconds <= 1_209_660 -> "14d"
        # 30 days ±1hr
        duration_seconds >= 2_592_000 - 3600 && duration_seconds <= 2_592_000 + 3600 -> "30d"
        true -> nil
      end
    else
      # Not a "relative to now" timeframe
      nil
    end
  end

  def handle_params(params, session, socket) do
    range = params["range"] || "hour"

    # Default to last 24 hours if no dates provided
    default_to = DateTime.utc_now() |> DateTime.shift_zone!(socket.assigns.project.time_zone)
    default_from = DateTime.shift(default_to, hour: -24)

    {:ok, from} =
      if params["from"] && params["from"] != "",
        do: parse_date(params["from"], socket.assigns.project.time_zone),
        else: {:ok, default_from}

    {:ok, to} =
      if params["to"] && params["to"] != "",
        do: parse_date(params["to"], socket.assigns.project.time_zone),
        else: {:ok, default_to}

    project_stats = load_project_stats(socket.assigns.project, range, from, to)
    keys_sum = reduce_stats(project_stats[:values])

    # Generate timeline data - either for specific key or all keys
    {timeline_data, chart_type} =
      if params["key"] && params["key"] != "" do
        # Single key selected - show individual key data
        timeline = series_from(project_stats, ["keys", params["key"]])
        {Jason.encode!(timeline["keys.#{params["key"]}"]), "single"}
      else
        # No key selected - show stacked data for all keys
        timeline = series_from_all_keys(project_stats, keys_sum)
        {Jason.encode!(timeline), "stacked"}
      end

    key_stats = load_project_key_stats(socket.assigns.project, params["key"], range, from, to)
    {:ok, key_tabulized, key_seriesized} = process_project_key_stats(key_stats)
    # IEx.pry
    # Use timeframe parameter from URL if available, otherwise try to determine it
    smart_input =
      case params["timeframe"] do
        nil -> determine_smart_input_for_range(from, to, socket.assigns.project.time_zone)
        timeframe when timeframe != "" -> timeframe
        _ -> determine_smart_input_for_range(from, to, socket.assigns.project.time_zone)
      end

    # Get the selected key's color for single charts
    selected_key_color =
      if params["key"] && params["key"] != "" do
        get_key_color(keys_sum, params["key"])
      else
        nil
      end

    socket =
      socket
      |> assign(range: range, from: from, to: to)
      |> assign(key: params["key"])
      |> assign(keys: keys_sum)
      |> assign(timeline: timeline_data)
      |> assign(chart_type: chart_type)
      |> assign(selected_key_color: selected_key_color)
      |> assign(stats: key_tabulized)
      |> assign(form: to_form(%{}))
      |> assign(smart_timeframe_input: smart_input)
      |> assign(show_timeframe_dropdown: false)
      |> assign(show_sensitivity_dropdown: false)

    {:noreply, socket}
  end

  def handle_info(:hide_dropdown_after_delay, socket) do
    {:noreply, assign(socket, show_timeframe_dropdown: false)}
  end

  def load_project_stats(project, range, from, to) do
    granularity = ui_range_to_granularity(range)
    Trifle.Stats.values("__system__key__", from, to, granularity, Project.stats_config(project))
  end

  def reduce_stats(values) when is_list(values) do
    Enum.reduce(values, [], fn data, acc -> [data["keys"] | acc] end)
    |> Enum.reduce(%{}, fn data, acc -> Trifle.Stats.Packer.deep_sum(acc, data) end)
  end

  def reduce_stats(_values) do
    # Fallback for non-list values
    %{}
  end

  def series_from(%{at: at, values: values} = stats, path) when is_list(path) do
    key = Enum.join(path, ".")

    Enum.with_index(at)
    |> Enum.reduce(%{}, fn {a, i}, acc ->
      v = get_in(Enum.at(values, i), path)
      # Convert DateTime to Unix timestamp while preserving timezone context
      # We need to get the "local" time as if it were UTC to avoid double timezone conversion
      unix_ms = DateTime.to_unix(a, :millisecond)
      acc = Map.put(acc, key, [[unix_ms, v || 0] | acc[key] || []])
    end)
  end

  def series_from_all_keys(%{at: at, values: values}, keys_sum)
      when is_list(at) and is_list(values) do
    # Get all available keys from keys_sum (which is working correctly)
    available_keys = Map.keys(keys_sum)

    # If we have no time points, create a fallback
    if length(at) == 0 or length(values) == 0 do
      # Create a single point chart showing the totals from keys_sum
      current_time = DateTime.to_unix(DateTime.utc_now(), :millisecond)

      Enum.map(available_keys, fn key ->
        total_value = keys_sum[key] || 0

        %{
          name: key,
          data: [[current_time, total_value]]
        }
      end)
    else
      # Normal time series processing
      Enum.map(available_keys, fn key ->
        key_data =
          Enum.with_index(at)
          |> Enum.map(fn {a, i} ->
            value_at_index = Enum.at(values, i)
            v = get_in(value_at_index, ["keys", key]) || 0
            unix_ms = DateTime.to_unix(a, :millisecond)
            [unix_ms, v]
          end)
          # Reverse to maintain chronological order
          |> Enum.reverse()

        %{
          name: key,
          data: key_data
        }
      end)
    end
  end

  def series_from_all_keys(_stats, keys_sum) do
    # Fallback - create chart from keys_sum only
    current_time = DateTime.to_unix(DateTime.utc_now(), :millisecond)

    Enum.map(Map.keys(keys_sum), fn key ->
      total_value = keys_sum[key] || 0

      %{
        name: key,
        data: [[current_time, total_value]]
      }
    end)
  end

  def load_project_key_stats(project, key, range, from, to) when is_nil(key), do: nil

  def load_project_key_stats(project, key, range, from, to)
      when is_binary(key) and byte_size(key) == 0,
      do: nil

  def load_project_key_stats(project, key, range, from, to) do
    granularity = ui_range_to_granularity(range)
    Trifle.Stats.values(key, from, to, granularity, Project.stats_config(project))
  end

  def process_project_key_stats(stats) when is_nil(stats), do: {:ok, nil, nil}

  def process_project_key_stats(stats) do
    {
      :ok,
      Trifle.Stats.Tabler.tabulize(stats),
      Trifle.Stats.Tabler.seriesize(stats)
    }
  end

  @doc """
  Returns the color for a specific key based on its position in the keys map.
  This ensures consistent coloring between the keys list and chart visualization.
  """
  def get_key_color(keys, target_key) when is_map(keys) do
    keys
    |> Map.keys()
    # Ensure consistent ordering
    |> Enum.sort()
    |> Enum.with_index()
    |> Enum.find(fn {key, _index} -> key == target_key end)
    |> case do
      {_key, index} -> ChartColors.color_for(index)
      # Fallback to primary color
      nil -> ChartColors.primary()
    end
  end

  @doc """
  Returns a styled HTML representation of a nested path with hierarchical coloring.
  Each nesting level starts from color 0, supporting unlimited depth.

  Examples:
    "count" -> <span style="color: color0">count</span>
    "severity.high" -> <span style="color: color1">severity</span>.<span style="color: color0">high</span>
    "severity.high.duration.standard_deviation" ->
      <span style="color: color1">severity</span>.<span style="color: color0">high</span>.<span style="color: color0">duration</span>.<span style="color: color0">standard_deviation</span>
  """
  def format_nested_path(path, all_paths) when is_binary(path) do
    path
    |> String.split(".")
    |> build_nested_html(all_paths, [])
    |> Enum.join(".")
    |> Phoenix.HTML.raw()
  end

  defp build_nested_html([component], all_paths, path_so_far) do
    # Last component - get its index at current level
    index = get_component_index_at_level(component, all_paths, path_so_far)
    color = ChartColors.color_for(index)
    ["<span style=\"color: #{color} !important\">#{component}</span>"]
  end

  defp build_nested_html([component | rest], all_paths, path_so_far) do
    # Intermediate component - get its index at current level
    index = get_component_index_at_level(component, all_paths, path_so_far)
    color = ChartColors.color_for(index)

    current_html = "<span style=\"color: #{color} !important\">#{component}</span>"
    new_path_so_far = path_so_far ++ [component]

    [current_html | build_nested_html(rest, all_paths, new_path_so_far)]
  end

  def format_table_timestamp(datetime, _range) when is_struct(datetime, DateTime) do
    date = datetime |> DateTime.to_date() |> Date.to_string()
    # HH:MM:SS
    time = datetime |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 8)
    Phoenix.HTML.raw("#{date}<br/>#{time}")
  end

  def format_table_timestamp(datetime, _range) do
    # Fallback for non-DateTime values
    to_string(datetime)
  end

  defp get_component_index_at_level(component, all_paths, path_so_far) do
    # Build the prefix for this level
    prefix =
      case path_so_far do
        [] -> ""
        parts -> Enum.join(parts, ".") <> "."
      end

    # Get all components at this level with the same prefix
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

    # Find the index of this component among its siblings
    Enum.find_index(siblings, &(&1 == component)) || 0
  end

  def render(assigns) do
    ~H"""
    <div class="">
      <div class="sm:p-4">
        <div class="border-b border-gray-200">
          <nav class="-mb-px space-x-8" aria-label="Tabs">
            <.link
              navigate={~p"/projects/#{@project.id}"}
              class="border-teal-500 text-teal-600 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium"
              aria-current="page"
            >
              <svg
                class="text-teal-400 group-hover:text-teal-500 -ml-0.5 mr-2 h-5 w-5"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="w-6 h-6"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M3.375 19.5h17.25m-17.25 0a1.125 1.125 0 01-1.125-1.125M3.375 19.5h7.5c.621 0 1.125-.504 1.125-1.125m-9.75 0V5.625m0 12.75v-1.5c0-.621.504-1.125 1.125-1.125m18.375 2.625V5.625m0 12.75c0 .621-.504 1.125-1.125 1.125m1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125m0 3.75h-7.5A1.125 1.125 0 0112 18.375m9.75-12.75c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125m19.5 0v1.5c0 .621-.504 1.125-1.125 1.125M2.25 5.625v1.5c0 .621.504 1.125 1.125 1.125m0 0h17.25m-17.25 0h7.5c.621 0 1.125.504 1.125 1.125M3.375 8.25c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125m17.25-3.75h-7.5c-.621 0-1.125.504-1.125 1.125m8.625-1.125c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125m-17.25 0h7.5m-7.5 0c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125M12 10.875v-1.5m0 1.5c0 .621-.504 1.125-1.125 1.125M12 10.875c0 .621.504 1.125 1.125 1.125m-2.25 0c.621 0 1.125.504 1.125 1.125M13.125 12h7.5m-7.5 0c-.621 0-1.125.504-1.125 1.125M20.625 12c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125m-17.25 0h7.5M12 14.625v-1.5m0 1.5c0 .621-.504 1.125-1.125 1.125M12 14.625c0 .621.504 1.125 1.125 1.125m-2.25 0c.621 0 1.125.504 1.125 1.125m0 1.5v-1.5m0 0c0-.621.504-1.125 1.125-1.125m0 0h7.5"
                />
              </svg>
              <span class="hidden sm:block">Explore</span>
            </.link>
            <.link
              navigate={~p"/projects/#{@project.id}/transponders"}
              class="border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium"
            >
              <svg
                class="text-gray-400 group-hover:text-gray-500 -ml-0.5 mr-2 h-5 w-5"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="w-6 h-6"
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
              navigate={~p"/projects/#{@project.id}/tokens"}
              class="float-right border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium"
            >
              <svg
                class="text-gray-400 group-hover:text-gray-500 -ml-0.5 mr-2 h-5 w-5"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="w-6 h-6"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M15.75 5.25a3 3 0 013 3m3 0a6 6 0 01-7.029 5.912c-.563-.097-1.159.026-1.563.43L10.5 17.25H8.25v2.25H6v2.25H2.25v-2.818c0-.597.237-1.17.659-1.591l6.499-6.499c.404-.404.527-1 .43-1.563A6 6 0 1121.75 8.25z"
                />
              </svg>
              <span class="hidden sm:block">Tokens</span>
            </.link>
            <.link
              navigate={~p"/projects/#{@project.id}/settings"}
              class="float-right border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium"
            >
              <svg
                class="text-gray-400 group-hover:text-gray-500 -ml-0.5 mr-2 h-5 w-5"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="w-6 h-6"
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
      </div>
    </div>

    <div class="flex flex-col">
      <!-- Timeframe section - now horizontal above Events -->
      <div class="mb-6">
        <div class="bg-white rounded-lg shadow p-4">
          <div class="flex items-center space-x-6">
            <!-- Smart input field with dropdown -->
            <div class="flex-1 max-w-md">
              <div
                class="relative"
                id={"smart_timeframe_container_#{@smart_timeframe_input}"}
                phx-update="replace"
              >
                <label
                  for="smart_timeframe"
                  class="absolute -top-2 left-2 inline-block bg-white px-1 text-xs font-medium text-gray-900"
                >
                  Timeframe UTC{get_timezone_offset_display(@project.time_zone)}
                </label>
                <input
                  type="text"
                  name="smart_timeframe"
                  id="smart_timeframe"
                  value={get_smart_timeframe_description(@smart_timeframe_input)}
                  placeholder="e.g., 5m, 2h, 1d, 3w, 6mo, 1y"
                  phx-keydown="smart_timeframe_keydown"
                  phx-key="Enter"
                  phx-focus="show_timeframe_dropdown"
                  phx-blur="delayed_hide_timeframe_dropdown"
                  phx-hook="SmartTimeframeInput"
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm pr-20"
                />
                <!-- Short code badge on the right -->
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
                <!-- Dropdown menu -->
                <%= if @show_timeframe_dropdown do %>
                  <div class="absolute z-50 mt-1 w-full bg-white shadow-lg max-h-60 rounded-md py-1 text-base ring-1 ring-black ring-opacity-5 overflow-auto focus:outline-none sm:text-sm">
                    <%= for {label, value} <- [
                        {"Last 5 minutes", "5m"},
                        {"Last 15 minutes", "15m"},
                        {"Last 30 minutes", "30m"},
                        {"Last 1 hour", "1h"},
                        {"Last 4 hours", "4h"},
                        {"Last 1 day", "1d"},
                        {"Last 2 days", "2d"},
                        {"Last 1 week", "1w"},
                        {"Last 1 month", "1mo"}
                      ] do %>
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
            
    <!-- Sensitivity controls -->
            <div>
              <label class="block text-xs font-medium text-gray-700 mb-2">Sensitivity</label>
              <div class="inline-flex rounded-md shadow-sm" role="group">
                <%= for {label, granularity, position} <- get_granularity_buttons(@project) do %>
                  <button
                    type="button"
                    phx-click="select_sensitivity"
                    phx-value-sensitivity={granularity_to_ui_range(granularity)}
                    class={
                      base_classes =
                        "relative inline-flex items-center px-2 py-1 text-xs font-medium focus:z-10 focus:outline-none focus:ring-2 focus:ring-teal-500"

                      position_classes =
                        case position do
                          :first -> "rounded-l-md"
                          :middle -> "-ml-px"
                          :last -> "-ml-px rounded-r-md"
                        end

                      state_classes =
                        if @range == granularity_to_ui_range(granularity) do
                          "bg-teal-600 text-white border-teal-600 hover:bg-teal-700"
                        else
                          "bg-white text-gray-700 border-gray-300 hover:bg-gray-50"
                        end

                      border_classes = "border"

                      "#{base_classes} #{position_classes} #{state_classes} #{border_classes}"
                    }
                  >
                    {label}
                  </button>
                <% end %>
              </div>
            </div>
            
    <!-- Current selection display -->
            <div class="flex-shrink-0">
              <div class="text-xs text-gray-500 bg-gray-50 rounded px-3 py-2">
                <span class="font-medium">Current:</span> <br />
                {format_timeframe_display(@from, @to)}
              </div>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Main content area -->
      <div class="flex-1 xl:flex">
        <div class="xl:w-96 xl:shrink-0 flex flex-col">
          <!-- Left column area -->
          <div class="bg-white rounded-lg shadow mr-4 flex flex-col min-h-96">
            <div class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-3 border-b">
              Keys
            </div>
            <ul role="list" class="divide-y divide-gray-100 flex-1">
              <%= for {key, count} <- @keys do %>
                <li class={
                  if @key == key,
                    do: "relative py-5 bg-teal-50",
                    else: "relative py-5 bg-white hover:bg-gray-50"
                }>
                  <div class="px-4 sm:px-6 lg:px-8">
                    <div class="mx-auto flex max-w-4xl justify-between gap-x-6">
                      <div class="flex gap-x-3 items-center">
                        <!-- Selection icon -->
                        <%= if @key == key do %>
                          <!-- Selected state: filled dot (radio button style) -->
                          <.link
                            navigate={
                              ~p"/projects/#{@project.id}?#{[range: @range, from: format_for_datetime_input(@from), to: format_for_datetime_input(@to), timeframe: @smart_timeframe_input]}"
                            }
                            class="flex-shrink-0"
                          >
                            <svg
                              class="h-5 w-5 text-teal-600"
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
                          </.link>
                        <% else %>
                          <!-- Unselected state: empty circle -->
                          <.link
                            navigate={
                              ~p"/projects/#{@project.id}?#{[range: @range, from: format_for_datetime_input(@from), to: format_for_datetime_input(@to), key: key, timeframe: @smart_timeframe_input]}"
                            }
                            class="flex-shrink-0"
                          >
                            <svg
                              class="h-5 w-5 text-gray-400"
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
                          </.link>
                        <% end %>

                        <div class="min-w-0 flex-auto">
                          <p
                            class="text-sm font-semibold font-mono leading-6"
                            style={"color: #{get_key_color(@keys, key)} !important"}
                          >
                            <.link
                              navigate={
                                if @key == key,
                                  do:
                                    ~p"/projects/#{@project.id}?#{[range: @range, from: format_for_datetime_input(@from), to: format_for_datetime_input(@to), timeframe: @smart_timeframe_input]}",
                                  else:
                                    ~p"/projects/#{@project.id}?#{[range: @range, from: format_for_datetime_input(@from), to: format_for_datetime_input(@to), key: key, timeframe: @smart_timeframe_input]}"
                              }
                              style="color: inherit !important"
                            >
                              <span class="absolute inset-x-0 -top-px bottom-0"></span>
                              {key}
                            </.link>
                          </p>
                        </div>
                      </div>
                      <div class="flex items-center gap-x-4">
                        <span
                          class="inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ring-1 ring-inset ring-gray-300 float-right"
                          style={"background-color: #{get_key_color(@keys, key)}15; color: #{get_key_color(@keys, key)} !important"}
                        >
                          {count}
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
                  </div>
                </li>
              <% end %>
            </ul>
          </div>
          &nbsp
        </div>

        <div class="xl:flex-1 overflow-x-auto overflow-hidden">
          <div class="bg-white rounded-lg shadow p-4 mb-5">
            <div
              id="timeline-hook"
              phx-hook="ProjectTimeline"
              data-events={@timeline}
              data-key={@key}
              data-timezone={@project.time_zone}
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

          <%= if @stats do %>
            <div class="text-lg font-semibold leading-6 text-gray-900 mt-5">Data</div>

            <div
              class="overflow-x-auto overflow-hidden bg-white rounded-lg shadow mt-5"
              id="table-hover-container"
              phx-hook="TableHover"
            >
              <table class="min-w-full divide-y divide-gray-300 overflow-auto" id="data-table">
                <thead>
                  <tr>
                    <th
                      scope="col"
                      class="top-0 left-0 sticky bg-white whitespace-nowrap py-2 pl-4 pr-3 text-left text-xs font-semibold text-gray-900 pl-4 h-16 z-20"
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
                        {format_table_timestamp(at, @range)}
                      </th>
                    <% end %>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-200 bg-white">
                  <%= for {path, row_index} <- @stats[:paths] |> Enum.with_index(1) do %>
                    <tr data-row={row_index}>
                      <td
                        class="left-0 sticky bg-white whitespace-nowrap py-1 pl-4 pr-3 text-xs font-mono pl-4 z-10 transition-colors duration-150"
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
          <% else %>
            <div class="text-gray-500 text-center py-8 mt-5">
              <p class="text-lg">← Select a key to view detailed data</p>
              <p class="text-sm mt-2">
                The chart above shows a stacked view of all events of the project.
              </p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
