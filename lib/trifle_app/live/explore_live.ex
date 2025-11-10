defmodule TrifleApp.ExploreLive do
  use TrifleApp, :live_view

  alias Decimal
  alias Trifle.Organizations
  alias Trifle.Stats.Source
  alias Trifle.Exports.Series, as: SeriesExport
  alias TrifleApp.Components.DataTable
  alias TrifleApp.DesignSystem.ChartColors
  alias TrifleApp.TimeframeParsing

  def mount(_params, _session, %{assigns: %{current_membership: nil}} = socket) do
    {:ok, redirect(socket, to: ~p"/organization/profile")}
  end

  def mount(params, _session, %{assigns: %{current_membership: membership}} = socket) do
    sources = Source.list_for_membership(membership)

    socket =
      socket
      |> assign(:sources, sources)

    case select_source_from_params(params, sources) do
      nil ->
        {:ok, assign_no_source(socket)}

      source ->
        {:ok, assign_source_state(socket, source)}
    end
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

  def format_smart_timeframe_display(
        smart_input,
        config,
        use_fixed_times \\ false,
        fixed_from \\ nil,
        fixed_to \\ nil
      )

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
        # 5 minutes
        300 -> "5m"
        # 10 minutes
        600 -> "10m"
        # 15 minutes
        900 -> "15m"
        # 30 minutes
        1800 -> "30m"
        # 1 hour
        3600 -> "1h"
        # 2 hours
        7200 -> "2h"
        # 3 hours
        10800 -> "3h"
        # 6 hours
        21600 -> "6h"
        # 12 hours
        43200 -> "12h"
        # 1 day
        86400 -> "1d"
        # 2 days
        172_800 -> "2d"
        # 3 days
        259_200 -> "3d"
        # 1 week
        604_800 -> "1w"
        # 2 weeks
        1_209_600 -> "2w"
        # ~1 month (30.44 days)
        2_629_746 -> "1mo"
        # ~2 months
        5_259_492 -> "2mo"
        # ~3 months
        7_889_238 -> "3mo"
        # ~6 months
        15_778_476 -> "6mo"
        # ~1 year
        31_556_952 -> "1y"
        # Custom timeframe
        _ -> "c"
      end
    else
      # Custom timeframe (not relative to now)
      "c"
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
          |> push_source_patch(%{
            granularity: granularity,
            from: format_for_datetime_input(from),
            to: format_for_datetime_input(to),
            key: socket.assigns.key
          })

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
    config = Source.stats_config(socket.assigns.source)

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
          |> push_source_patch(%{
            granularity: granularity,
            from: format_for_datetime_input(from),
            to: format_for_datetime_input(to),
            key: socket.assigns[:key] || "",
            timeframe: preset
          })

        {:noreply, socket}

      {:error, _} ->
        {:noreply, assign(socket, show_timeframe_dropdown: false)}
    end
  end

  def handle_event("smart_timeframe_keydown", %{"key" => "Enter", "value" => input}, socket) do
    config = Source.stats_config(socket.assigns.source)

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
          |> push_source_patch(%{
            granularity: granularity,
            from: format_for_datetime_input(from),
            to: format_for_datetime_input(to),
            key: socket.assigns[:key] || "",
            timeframe: detected_shorthand
          })

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
              |> push_source_patch(%{
                granularity: granularity,
                from: format_for_datetime_input(from),
                to: format_for_datetime_input(to),
                key: socket.assigns[:key] || "",
                timeframe: short_input
              })

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
      |> push_source_patch(%{
        granularity: granularity,
        from: format_for_datetime_input(socket.assigns.from),
        to: format_for_datetime_input(socket.assigns.to),
        key: socket.assigns[:key] || "",
        timeframe: socket.assigns[:smart_timeframe_input]
      })

    {:noreply, socket}
  end

  def handle_event("select_key", %{"key" => key}, socket) do
    socket =
      socket
      |> assign(loading: true)
      |> push_source_patch(%{
        granularity: socket.assigns.granularity,
        from: format_for_datetime_input(socket.assigns.from),
        to: format_for_datetime_input(socket.assigns.to),
        key: key,
        timeframe: socket.assigns[:smart_timeframe_input]
      })

    {:noreply, socket}
  end

  def handle_event("deselect_key", _, socket) do
    socket =
      socket
      |> assign(loading: true)
      |> push_source_patch(%{
        granularity: socket.assigns.granularity,
        from: format_for_datetime_input(socket.assigns.from),
        to: format_for_datetime_input(socket.assigns.to),
        timeframe: socket.assigns[:smart_timeframe_input]
      })

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
    {new_from, new_to} =
      case direction do
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
      # Mark as custom since it's a calculated range
      |> assign(smart_timeframe_input: "c")
      |> push_event("update_smart_timeframe_input", %{
        value: format_timeframe_display(new_from, new_to)
      })
      |> push_source_patch(%{
        granularity: granularity,
        from: format_for_datetime_input(new_from),
        to: format_for_datetime_input(new_to),
        key: socket.assigns[:key] || "",
        timeframe: "c"
      })

    {:noreply, socket}
  end

  defp reload_current_timeframe(socket) do
    granularity = socket.assigns.granularity

    params =
      if socket.assigns.use_fixed_display do
        %{
          granularity: granularity,
          from: format_for_datetime_input(socket.assigns.from),
          to: format_for_datetime_input(socket.assigns.to),
          key: socket.assigns[:key] || "",
          timeframe: socket.assigns[:smart_timeframe_input]
        }
      else
        %{
          granularity: granularity,
          key: socket.assigns[:key] || "",
          timeframe: socket.assigns[:smart_timeframe_input]
        }
      end

    {:noreply,
     socket
     |> assign(loading: true)
     |> push_source_patch(params)}
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
  def get_available_granularities(source) do
    Source.available_granularities(source)
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
      "1s" ->
        "1 second"

      "1m" ->
        "1 minute"

      "1h" ->
        "1 hour"

      "1d" ->
        "1 day"

      "1w" ->
        "1 week"

      "1mo" ->
        "1 month"

      "1q" ->
        "1 quarter"

      "1y" ->
        "1 year"

      _ ->
        # For custom granularities like "5m", "15m", etc., try to parse with Nocturnal.Parser
        try do
          parser = Trifle.Stats.Nocturnal.Parser.new(granularity)

          if Trifle.Stats.Nocturnal.Parser.valid?(parser) do
            unit_name =
              case parser.unit do
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
  def get_granularity_buttons(source) do
    granularities = get_available_granularities(source)

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
    cond do
      is_nil(socket.assigns[:source]) ->
        {:noreply, socket}

      true ->
        socket =
          case source_from_params(params, socket.assigns.sources) do
            nil ->
              socket

            new_source ->
              if sources_equal?(new_source, socket.assigns.source) do
                socket
              else
                apply_source_change(socket, new_source)
              end
          end

        source = socket.assigns.source

        if is_nil(source) do
          {:noreply, socket}
        else
          config = Source.stats_config(source)
          source_default_tf = Source.default_timeframe(source) || "24h"
          default_granularity = Source.default_granularity(source) || "1h"
          available_granularities = Source.available_granularities(source) || []

          granularity =
            ensure_granularity(
              params["granularity"] || default_granularity || "1h",
              available_granularities
            )

          {from, to, smart_input, use_fixed_display} =
            cond do
              params["from"] && params["from"] != "" && params["to"] && params["to"] != "" ->
                case {TimeframeParsing.parse_date(params["from"], config.time_zone),
                      TimeframeParsing.parse_date(params["to"], config.time_zone)} do
                  {{:ok, from}, {:ok, to}} ->
                    smart_input =
                      if params["timeframe"] && params["timeframe"] != "" do
                        params["timeframe"]
                      else
                        determine_smart_input_for_range(from, to, config.time_zone)
                      end

                    use_fixed_display = params["timeframe"] && params["timeframe"] != ""
                    {from, to, smart_input, !!use_fixed_display}

                  _ ->
                    cond do
                      params["timeframe"] && params["timeframe"] != "" ->
                        case TimeframeParsing.parse_smart_timeframe(params["timeframe"], config) do
                          {:ok, f, t, si, uf} -> {f, t, si, uf}
                          {:error, _} -> fallback_timeframe(config, source_default_tf)
                        end

                      true ->
                        fallback_timeframe(config, source_default_tf)
                    end
                end

              params["timeframe"] && params["timeframe"] != "" ->
                case TimeframeParsing.parse_smart_timeframe(params["timeframe"], config) do
                  {:ok, f, t, si, uf} -> {f, t, si, uf}
                  {:error, _} -> fallback_timeframe(config, source_default_tf)
                end

              true ->
                fallback_timeframe(config, source_default_tf)
            end

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

          should_update_url =
            is_nil(params["timeframe"]) && is_nil(params["from"]) && is_nil(params["to"])

          if should_update_url do
            url_params = %{timeframe: smart_input, granularity: granularity}

            url_params =
              if params["key"], do: Map.put(url_params, :key, params["key"]), else: url_params

            socket = push_source_patch(socket, url_params)
            {:noreply, socket}
          else
            if socket.assigns[:loading] do
              send(self(), :load_data)
              {:noreply, socket}
            else
              load_data_and_update_socket(socket)
            end
          end
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
    Logger.info("ExploreLive.handle_info filter_bar: changes=#{inspect(changes)}")

    updated_socket =
      Enum.reduce(changes, socket, fn
        {:source, _value}, acc -> acc
        {:database_id, _value}, acc -> acc
        {key, value}, acc -> assign(acc, key, value)
      end)

    updated_socket =
      case determine_new_source(changes, socket.assigns.sources) do
        nil ->
          updated_socket

        new_source ->
          updated_socket
          |> apply_source_change(new_source)
          |> recalculate_timeframe_for_source(new_source)
      end

    if is_nil(updated_socket.assigns[:source]) do
      {:noreply, updated_socket}
    else
      needs_url_update? =
        Map.has_key?(changes, :from) or Map.has_key?(changes, :to) or
          Map.has_key?(changes, :granularity) or Map.has_key?(changes, :use_fixed_display) or
          Map.has_key?(changes, :source) or Map.has_key?(changes, :database_id)

      if needs_url_update? do
        base_params = %{
          timeframe: updated_socket.assigns.smart_timeframe_input,
          granularity: updated_socket.assigns.granularity
        }

        url_params =
          if updated_socket.assigns.use_fixed_display do
            Map.merge(base_params, %{
              from:
                if(updated_socket.assigns.from,
                  do: DateTime.to_iso8601(updated_socket.assigns.from),
                  else: nil
                ),
              to:
                if(updated_socket.assigns.to,
                  do: DateTime.to_iso8601(updated_socket.assigns.to),
                  else: nil
                )
            })
          else
            base_params
          end

        url_params =
          if updated_socket.assigns.key do
            Map.put(url_params, :key, updated_socket.assigns.key)
          else
            url_params
          end

        {:noreply, push_source_patch(updated_socket, url_params)}
      else
        if Map.has_key?(changes, :reload) do
          load_data_and_update_socket(updated_socket)
        else
          {:noreply, updated_socket}
        end
      end
    end
  end

  # Toggle Play/Pause in Explore (defensive handler in parent LiveView)
  def handle_event("toggle_play_pause", _params, socket) do
    socket =
      if socket.assigns.use_fixed_display do
        tf =
          socket.assigns.smart_timeframe_input ||
            (Source.default_timeframe(socket.assigns.source) || "24h")

        config = socket.assigns.database_config

        case TimeframeParsing.parse_smart_timeframe(tf, config) do
          {:ok, from, to, smart, _} ->
            assign(socket,
              from: from,
              to: to,
              smart_timeframe_input: smart,
              use_fixed_display: false
            )

          {:error, _} ->
            assign(socket, use_fixed_display: false)
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
        timeline_map = series_from(system_stats.series, ["keys", socket.assigns.key])
        path = "keys.#{socket.assigns.key}"

        timeline_points =
          timeline_map
          |> Map.get(path)
          |> case do
            nil -> fallback_points_for_key(keys_sum, socket.assigns.key)
            [] -> fallback_points_for_key(keys_sum, socket.assigns.key)
            list -> list
          end

        timeline_data = Jason.encode!(timeline_points)
        selected_key_color = get_key_color(keys_sum, socket.assigns.key)
        table_stats = Trifle.Stats.Tabler.tabulize(key_stats.series)

        {:noreply,
         socket
         |> assign(loading: false)
         |> assign(loading_chunks: false)
         |> assign(loading_progress: nil)
         |> assign(transponding: false)
         |> assign(stats: table_stats)
         |> assign(series_raw: key_stats.series)
         |> assign(keys: keys_sum)
         |> assign(timeline: timeline_data)
         |> assign(chart_type: "single")
         |> assign(selected_key_color: selected_key_color)
         |> assign(key_transponder_results: key_transponder_results)
         |> assign(load_duration_microseconds: load_duration)}

      %{system: system_stats} ->
        # When no specific key is selected, use system stats for everything
        keys_sum = reduce_stats(system_stats.series[:values] || [])
        timeline_series = series_from_all_keys(system_stats.series, keys_sum)
        timeline_data = Jason.encode!(timeline_series)
        table_stats = Trifle.Stats.Tabler.tabulize(system_stats.series)

        {:noreply,
         socket
         |> assign(loading: false)
         |> assign(loading_chunks: false)
         |> assign(loading_progress: nil)
         |> assign(transponding: false)
         |> assign(stats: table_stats)
         |> assign(series_raw: system_stats.series)
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
            timeline_map = series_from(raw_stats, ["keys", socket.assigns.key])
            path = "keys.#{socket.assigns.key}"

            points =
              timeline_map
              |> Map.get(path)
              |> case do
                nil -> fallback_points_for_key(keys_sum, socket.assigns.key)
                [] -> fallback_points_for_key(keys_sum, socket.assigns.key)
                list -> list
              end

            {Jason.encode!(points), "single"}
          else
            timeline_series = series_from_all_keys(raw_stats, keys_sum)
            {Jason.encode!(timeline_series), "stacked"}
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
         |> assign(series_raw: raw_stats)
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
    socket =
      assign(socket,
        load_start_time: System.monotonic_time(:microsecond),
        loading: true,
        loading_chunks: true,
        loading_progress: nil,
        transponding: false
      )

    # Extract values to avoid async socket warnings
    source = socket.assigns.source
    database = Source.record(source)
    key = socket.assigns.key
    granularity = socket.assigns.granularity
    from = socket.assigns.from
    to = socket.assigns.to
    # Capture LiveView PID before async task
    liveview_pid = self()

    # Create progress callback to send updates back to LiveView
    progress_callback = fn progress_info ->
      case progress_info do
        {:chunk_progress, current, total} ->
          send(liveview_pid, {:loading_progress, %{current: current, total: total}})

        {:transponder_progress, :starting} ->
          send(liveview_pid, {:transponding, true})

        {:transponder_progress, :finished} ->
          send(liveview_pid, {:transponding, false})
      end
    end

    # Use Source.fetch_series for all data loading to ensure consistent transponder application, including transponders
    {:noreply,
     start_async(
       socket,
       :data_task,
       fn ->
         if key && key != "" do
           # Load both system key (no transponders) and specific key (with transponders)
           case {Source.fetch_series(
                   source,
                   "__system__key__",
                   from,
                   to,
                   granularity,
                   progress_callback: progress_callback,
                   transponders: :none
                 ),
                 Source.fetch_series(
                   source,
                   key,
                   from,
                   to,
                   granularity,
                   progress_callback: progress_callback
                 )} do
             {{:ok, system_result}, {:ok, key_result}} ->
               %{
                 system: system_result.series,
                 key: key_result.series,
                 key_transponder_results: key_result.transponder_results
               }

             {{:error, error}, _} ->
               {:error, {:system_key_failed, error}}

             {_, {:error, error}} ->
               {:error, {:specific_key_failed, error}}
           end
         else
           # Only load system key when no specific key is selected (no transponders)
           case Source.fetch_series(
                  source,
                  "__system__key__",
                  from,
                  to,
                  granularity,
                  progress_callback: progress_callback,
                  transponders: :none
                ) do
             {:ok, result} -> %{system: result.series}
             {:error, error} -> {:error, error}
           end
         end
       end,
       timeout: 300_000
     )}
  end

  def reduce_stats(values) when is_list(values) do
    Enum.reduce(values, [], fn data, acc -> [data["keys"] | acc] end)
    |> Enum.reduce(%{}, fn data, acc -> Trifle.Stats.Packer.deep_sum(acc, data) end)
  end

  def reduce_stats(_values) do
    %{}
  end

  defp select_source_from_params(params, sources) do
    cond do
      sources == [] -> nil
      source = source_from_explicit_params(params, sources) -> source
      true -> hd(sources)
    end
  end

  defp source_from_params(params, sources) do
    source_from_explicit_params(params, sources)
  end

  defp source_from_explicit_params(params, sources) do
    with type when not is_nil(type) <- parse_source_type(Map.get(params, "source_type")),
         id when not is_nil(id) <- Map.get(params, "source_id"),
         source when not is_nil(source) <- Source.find_in_list(sources, type, id) do
      source
    else
      _ ->
        case Map.get(params, "database_id") do
          nil -> nil
          db_id -> Source.find_in_list(sources, :database, db_id)
        end
    end
  end

  defp apply_source_change(socket, nil), do: assign_no_source(socket)

  defp apply_source_change(socket, source) do
    {transponder_info, response_paths} = build_transponder_info(Source.transponders(source))
    config = Source.stats_config(source)
    available_granularities = Source.available_granularities(source) || []

    socket
    |> assign(:no_source, false)
    |> assign(:source, source)
    |> assign(:selected_source_ref, component_source_ref(source))
    |> assign(:sources, ensure_source_in_list(socket.assigns[:sources] || [], source))
    |> assign(:database, database_from_source(source))
    |> assign(:database_config, config)
    |> assign(:available_granularities, available_granularities)
    |> assign(:transponder_info, transponder_info)
    |> assign(:transponder_response_paths, response_paths)
    |> assign(:page_title, "Explore · #{Source.display_name(source)}")
    |> assign(:breadcrumb_links, [{"Explore", ~p"/explore?#{source_params(source)}"}])
  end

  defp assign_source_state(socket, nil), do: assign_no_source(socket)

  defp assign_source_state(socket, source) do
    socket
    |> apply_source_change(source)
    |> assign(:stats, nil)
    |> assign(:timeline, "[]")
    |> assign(:chart_type, "stacked")
    |> assign(:keys, %{})
    |> assign(:selected_key_color, nil)
    |> assign(:smart_timeframe_input, nil)
    |> assign(:key_search_filter, "")
    |> assign(:loading, false)
    |> assign(:loading_chunks, false)
    |> assign(:loading_progress, nil)
    |> assign(:transponding, false)
    |> assign(:show_timeframe_dropdown, false)
    |> assign(:show_sensitivity_dropdown, false)
    |> assign(:show_granularity_dropdown, false)
    |> assign(:transponder_errors, [])
    |> assign(:show_error_modal, false)
    |> assign(:transponder_results, [])
    |> assign(:key_transponder_results, %{successful: [], failed: [], errors: []})
    |> assign(:load_start_time, nil)
    |> assign(:load_duration_microseconds, nil)
    |> assign(:show_export_dropdown, false)
  end

  defp assign_no_source(socket) do
    socket
    |> assign(:page_title, "Explore")
    |> assign(:no_source, true)
    |> assign(:source, nil)
    |> assign(:selected_source_ref, nil)
    |> assign(:database, nil)
    |> assign(:database_config, nil)
    |> assign(:available_granularities, [])
    |> assign(:transponder_response_paths, [])
    |> assign(:transponder_info, %{})
    |> assign(:stats, nil)
    |> assign(:timeline, "[]")
    |> assign(:chart_type, "stacked")
    |> assign(:keys, %{})
    |> assign(:selected_key_color, nil)
    |> assign(:smart_timeframe_input, nil)
    |> assign(:key_search_filter, "")
    |> assign(:loading, false)
    |> assign(:loading_chunks, false)
    |> assign(:loading_progress, nil)
    |> assign(:transponding, false)
    |> assign(:show_timeframe_dropdown, false)
    |> assign(:show_sensitivity_dropdown, false)
    |> assign(:show_granularity_dropdown, false)
    |> assign(:transponder_errors, [])
    |> assign(:show_error_modal, false)
    |> assign(:transponder_results, [])
    |> assign(:key_transponder_results, %{successful: [], failed: [], errors: []})
    |> assign(:load_start_time, nil)
    |> assign(:load_duration_microseconds, nil)
    |> assign(:show_export_dropdown, false)
    |> assign(:breadcrumb_links, [])
  end

  defp ensure_source_in_list(sources, source) do
    cond do
      is_nil(source) ->
        sources || []

      Enum.any?(sources || [], &sources_equal?(&1, source)) ->
        sources || []

      true ->
        ((sources || []) ++ [source])
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(fn s ->
          {source_sort_key(Source.type(s)), String.downcase(Source.display_name(s))}
        end)
    end
  end

  defp source_sort_key(:database), do: 0
  defp source_sort_key(:project), do: 1
  defp source_sort_key(_other), do: 2

  defp component_source_ref(nil), do: nil

  defp component_source_ref(source) do
    %{type: Source.type(source), id: to_string(Source.id(source))}
  end

  defp database_from_source(source) do
    case Source.type(source) do
      :database -> Source.record(source)
      _ -> nil
    end
  end

  defp build_transponder_info(transponders) do
    info =
      transponders
      |> Enum.map(fn transponder ->
        response_path = Map.get(transponder.config, "response_path", "")
        transponder_name = transponder.name || transponder.key
        if response_path != "", do: {response_path, transponder_name}, else: nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.into(%{})

    {info, Map.keys(info)}
  end

  defp source_params(nil), do: %{}

  defp source_params(source) do
    id = Source.id(source) |> to_string()
    type = Source.type(source)

    params = %{
      source_type: Atom.to_string(type),
      source_id: id
    }

    if type == :database do
      Map.put(params, :database_id, id)
    else
      params
    end
  end

  defp push_source_patch(socket, extra_params) do
    params =
      socket.assigns.source
      |> source_params()
      |> Map.merge(extra_params)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    push_patch(socket, to: ~p"/explore?#{params}")
  end

  defp source_from_change(change, sources)

  defp source_from_change(%{type: type, id: id}, sources) do
    type_atom = parse_source_type(type)
    Source.find_in_list(sources, type_atom, id)
  end

  defp source_from_change(%{"type" => type, "id" => id}, sources) do
    type_atom = parse_source_type(type)
    Source.find_in_list(sources, type_atom, id)
  end

  defp source_from_change(_other, _sources), do: nil

  defp determine_new_source(changes, sources) do
    cond do
      Map.has_key?(changes, :source) ->
        source_from_change(changes.source, sources)

      Map.has_key?(changes, :database_id) ->
        Source.find_in_list(sources, :database, changes.database_id)

      true ->
        nil
    end
  end

  defp recalculate_timeframe_for_source(socket, source) do
    config = Source.stats_config(source)
    source_default_tf = Source.default_timeframe(source) || "24h"
    available_granularities = Source.available_granularities(source) || []

    current_granularity = socket.assigns[:granularity]

    granularity =
      if current_granularity in available_granularities do
        current_granularity
      else
        List.first(available_granularities) || current_granularity
      end

    {from, to, smart_input, use_fixed} =
      if socket.assigns[:use_fixed_display] do
        {socket.assigns[:from], socket.assigns[:to], socket.assigns[:smart_timeframe_input], true}
      else
        tf = socket.assigns[:smart_timeframe_input] || source_default_tf

        case TimeframeParsing.parse_smart_timeframe(tf, config) do
          {:ok, f, t, si, uf} ->
            {f, t, si, uf}

          {:error, _} ->
            default_to = DateTime.utc_now()
            default_from = DateTime.shift(default_to, hour: -24)
            {default_from, default_to, "24h", false}
        end
      end

    socket
    |> assign(:granularity, granularity)
    |> assign(:from, from)
    |> assign(:to, to)
    |> assign(:smart_timeframe_input, smart_input)
    |> assign(:use_fixed_display, use_fixed)
  end

  defp fallback_timeframe(config, timeframe) do
    case TimeframeParsing.parse_smart_timeframe(timeframe, config) do
      {:ok, from, to, smart_input, use_fixed} ->
        {from, to, smart_input, use_fixed}

      {:error, _} ->
        default_to = DateTime.utc_now()
        default_from = DateTime.shift(default_to, hour: -24)
        {default_from, default_to, "24h", false}
    end
  end

  defp ensure_granularity(granularity, []), do: granularity

  defp ensure_granularity(granularity, available) do
    if granularity in available do
      granularity
    else
      List.first(available) || granularity
    end
  end

  defp parse_source_type(nil), do: nil
  defp parse_source_type(type) when is_atom(type), do: type

  defp parse_source_type(type) when is_binary(type) do
    case String.trim(type) do
      "" -> nil
      "database" -> :database
      "project" -> :project
      other -> String.to_atom(other)
    end
  rescue
    ArgumentError -> nil
  end

  defp sources_equal?(nil, nil), do: true
  defp sources_equal?(_, nil), do: false
  defp sources_equal?(nil, _), do: false

  defp sources_equal?(a, b) do
    Source.type(a) == Source.type(b) && to_string(Source.id(a)) == to_string(Source.id(b))
  end

  def series_from(series_input, path) when is_list(path) do
    path = Enum.join(path, ".")
    series_struct = ensure_series_struct(series_input)

    format_timeline_map(series_struct, path, 1, &timeline_chart_point/2)
    |> Enum.into(%{}, fn {k, v} -> {k, normalize_timeline_points(v)} end)
  end

  def series_from_all_keys(series_input, keys_sum) do
    series_struct = ensure_series_struct(series_input)
    option_values = Map.keys(keys_sum)
    timeline_map = format_timeline_map(series_struct, "keys.*", 1, &timeline_chart_point/2)

    cond do
      map_size(timeline_map) == 0 ->
        fallback_series_from_keys_sum(keys_sum)

      true ->
        option_values
        |> Enum.sort()
        |> Enum.map(fn key ->
          path = "keys." <> key
          points = normalize_timeline_points(Map.get(timeline_map, path))

          data =
            case points do
              [] -> fallback_points_for_key(keys_sum, key)
              list -> list
            end

          %{name: key, data: data}
        end)
    end
  end

  defp ensure_series_struct(%Trifle.Stats.Series{} = series), do: series
  defp ensure_series_struct(series) when is_map(series), do: Trifle.Stats.Series.new(series)

  defp format_timeline_map(series_struct, path, slices, callback) do
    series_struct
    |> Trifle.Stats.Series.format_timeline(path, slices, callback)
    |> case do
      %{} = map -> map
      list when is_list(list) -> %{path => list}
      _ -> %{}
    end
  end

  defp normalize_timeline_points(nil), do: []
  defp normalize_timeline_points(list) when is_list(list), do: list
  defp normalize_timeline_points(other), do: List.wrap(other)

  defp timeline_chart_point(at, value) do
    naive = DateTime.to_naive(at)
    utc_dt = DateTime.from_naive!(naive, "Etc/UTC")
    ts = DateTime.to_unix(utc_dt, :millisecond)

    val =
      cond do
        match?(%Decimal{}, value) -> Decimal.to_float(value)
        is_number(value) -> value * 1.0
        true -> 0.0
      end

    [ts, val]
  end

  defp fallback_series_from_keys_sum(keys_sum) when map_size(keys_sum) == 0, do: []

  defp fallback_series_from_keys_sum(keys_sum) do
    current_time = DateTime.to_unix(DateTime.utc_now(), :millisecond)

    keys_sum
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map(fn key ->
      %{name: key, data: [[current_time, normalize_chart_value(Map.get(keys_sum, key))]]}
    end)
  end

  defp fallback_points_for_key(keys_sum, key) do
    current_time = DateTime.to_unix(DateTime.utc_now(), :millisecond)
    [[current_time, normalize_chart_value(Map.get(keys_sum, key))]]
  end

  defp normalize_chart_value(%Decimal{} = value), do: Decimal.to_float(value)
  defp normalize_chart_value(value) when is_number(value), do: value * 1.0
  defp normalize_chart_value(_), do: 0.0

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
      %{
        key: key,
        stats: stats,
        transponder_info: transponder_info,
        key_transponder_results: key_transponder_results
      }
      when not is_nil(key) and key != "" and not is_nil(stats) ->
        # Count columns (timeline points)
        column_count = if stats[:at], do: length(stats[:at]), else: 0

        # Count paths (rows)
        path_count = if stats[:paths], do: length(stats[:paths]), else: 0

        # Use actual transponder results returned by Source.fetch_series
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

  # Export dropdown handlers
  def handle_event("toggle_export_dropdown", _params, socket) do
    {:noreply,
     assign(socket, :show_export_dropdown, !(socket.assigns[:show_export_dropdown] || false))}
  end

  def handle_event("hide_export_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_export_dropdown, false)}
  end

  def handle_event("download_explore_csv", _params, socket) do
    series = SeriesExport.extract_series(socket.assigns[:stats])

    if SeriesExport.has_data?(series) do
      csv = SeriesExport.to_csv(series)
      fname = export_filename("explore", socket.assigns, ".csv")

      {:noreply,
       push_event(socket, "file_download", %{content: csv, filename: fname, type: "text/csv"})}
    else
      {:noreply, put_flash(socket, :error, "No data to export")}
    end
  end

  def handle_event("download_explore_json", _params, socket) do
    raw =
      socket.assigns[:series_raw]
      |> case do
        nil -> socket.assigns[:stats]
        other -> other
      end
      |> SeriesExport.extract_series()

    if SeriesExport.has_data?(raw) do
      json = SeriesExport.to_json(raw)
      fname = export_filename("explore", socket.assigns, ".json")

      {:noreply,
       push_event(socket, "file_download", %{
         content: json,
         filename: fname,
         type: "application/json"
       })}
    else
      {:noreply, put_flash(socket, :error, "No data to export")}
    end
  end

  defp export_filename(prefix, assigns, ext) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)

    source_name =
      cond do
        Map.has_key?(assigns, :source) && assigns.source -> Source.display_name(assigns.source)
        Map.has_key?(assigns, :database) && assigns.database -> assigns.database.display_name
        true -> nil
      end

    base =
      [prefix, source_name, assigns[:key]]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&String.replace(to_string(&1), ~r/[^a-zA-Z0-9_-]+/, "-"))
      |> Enum.join("-")

    if(base == "", do: prefix, else: base) <> "-" <> ts <> ext
  end

  def format_nested_path(path, all_paths, transponder_info \\ %{}, opts \\ [])
      when is_binary(path) do
    display_path =
      opts
      |> Keyword.get(:display_path, path)
      |> to_string()

    transponder_lookup =
      opts
      |> Keyword.get(:transponder_path, path)
      |> to_string()

    transponder_name = Map.get(transponder_info, transponder_lookup)

    formatted_path =
      display_path
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
    <%= if @no_source do %>
      <div
        id="explore-root"
        class="flex flex-col dark:bg-slate-900 min-h-screen relative"
        phx-hook="FileDownload"
      >
        <div class="max-w-3xl mx-auto mt-16">
          <div class="bg-white dark:bg-slate-800 rounded-lg shadow p-6">
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-2">
              No sources found
            </h2>
            <p class="text-gray-600 dark:text-slate-300">
              Please add a database or project first to use Explore.
            </p>
            <div class="mt-4">
              <.link
                navigate={~p"/dbs"}
                class="inline-flex items-center px-3 py-2 bg-teal-600 text-white rounded-md hover:bg-teal-700"
              >
                Go to Databases
              </.link>
            </div>
          </div>
        </div>
      </div>
    <% else %>
      <div
        id="explore-root"
        class="flex flex-col dark:bg-slate-900 min-h-screen relative"
        phx-hook="FileDownload"
      >
        <!-- Loading Overlay (covers entire page content; message at 1/3 height) -->
        <%= if (@loading_chunks && @loading_progress) || @transponding do %>
          <div class="absolute inset-0 bg-white bg-opacity-75 dark:bg-slate-900 dark:bg-opacity-90 z-50">
            <div class="absolute left-1/2 -translate-x-1/2" style="top: 33%;">
              <div class="flex flex-col items-center space-y-3">
                <div class="flex items-center space-x-2">
                  <div class="animate-spin rounded-full h-6 w-6 border-2 border-gray-300 dark:border-slate-600 border-t-teal-500">
                  </div>
                  <span class="text-sm text-gray-600 dark:text-white">
                    <%= if @transponding do %>
                      Transponding data...
                    <% else %>
                      Scientificating piece {@loading_progress.current} of {@loading_progress.total}...
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
                      >
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        <% end %>
        
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
          sources={@sources}
          selected_source={@selected_source_ref}
          force_granularity_dropdown={false}
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
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke-width="1.5"
                      stroke="currentColor"
                      class="w-6 h-6 text-gray-500 dark:text-slate-400"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="M15.362 5.214A8.252 8.252 0 0 1 12 21 8.25 8.25 0 0 1 6.038 7.047 8.287 8.287 0 0 0 9 9.601a8.983 8.983 0 0 1 3.361-6.867 8.21 8.21 0 0 0 3 2.48Z"
                      />
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="M12 18a3.75 3.75 0 0 0 .495-7.468 5.99 5.99 0 0 0-1.925 3.547 5.975 5.975 0 0 1-2.133-1.001A3.75 3.75 0 0 0 12 18Z"
                      />
                    </svg>
                  </div>
                  <p class="text-sm text-gray-500 dark:text-slate-400 max-w-md">
                    Your dashboard is having trust issues with empty data. Feed it some metrics and it'll start showing off!
                  </p>
                  <%= if @source && Source.type(@source) == :database do %>
                    <div class="mt-4">
                      <.link
                        navigate={~p"/dbs/#{Source.id(@source)}/transponders"}
                        class="inline-flex items-center gap-2 text-sm font-medium text-teal-600 hover:text-teal-700 dark:text-teal-400 dark:hover:text-teal-300"
                      >
                        <svg
                          class="h-4 w-4"
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke-width="1.5"
                          stroke="currentColor"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            d="m21 7.5-2.25-1.313M21 7.5v2.25m0-2.25l-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3l2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75l2.25-1.313M12 21.75V19.5m0 2.25l-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25"
                          />
                        </svg>
                        Set up Transponders →
                      </.link>
                    </div>
                  <% end %>
                </div>
              </div>
            <% else %>
              <!-- Chart (when data exists) -->
              <div
                id="timeline-hook"
                phx-hook="DatabaseExploreChart"
                data-events={@timeline}
                data-key={@key}
                data-timezone={(@source && Source.time_zone(@source)) || "UTC"}
                data-chart-type={@chart_type}
                data-colors={ChartColors.json_palette()}
                data-selected-key-color={@selected_key_color}
                class=""
              >
              </div>
              <div id="timeline-chart-wrapper" phx-update="ignore" class="mt-3 h-full">
                <div id="timeline-chart"></div>
              </div>
            <% end %>
          </div>
        </div>
        
    <!-- Row 3: Key Selection -->
        <div class="mb-6">
          <.data_table>
            <:header>
              <.table_header title="Keys" count={length(filter_keys(@keys, @key_search_filter))}>
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
                      <svg
                        class="h-4 w-4 text-gray-400 dark:text-slate-400"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
                        />
                      </svg>
                    </div>
                  </div>
                </:search>
              </.table_header>
            </:header>

            <:body>
              <div class="h-48 overflow-auto rounded-b-lg">
                <!-- Fixed height for ~3 items with scrolling -->
                <ul
                  role="list"
                  class="divide-y divide-gray-100 dark:divide-slate-700 rounded-b-lg overflow-hidden"
                >
                  <%= for {key, count} <- filter_keys(@keys, @key_search_filter) do %>
                    <li class={
                      if @key == key,
                        do: "relative bg-teal-50 dark:bg-teal-900/30",
                        else:
                          "relative bg-white dark:bg-transparent hover:bg-gray-50 dark:hover:bg-slate-700"
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
                    <% trimmed_filter = String.trim(@key_search_filter || "") %>
                    <div class="flex flex-col items-center justify-center gap-3 h-48 text-gray-500 dark:text-slate-400 text-sm">
                      <span>No keys found</span>
                      <%= if trimmed_filter != "" do %>
                        <button
                          type="button"
                          phx-click="select_key"
                          phx-value-key={trimmed_filter}
                          class="inline-flex items-center gap-2 rounded-md border border-teal-200 dark:border-teal-800 bg-teal-50 dark:bg-teal-900/30 px-3 py-1.5 text-xs font-medium text-teal-600 hover:bg-teal-100 dark:text-teal-300 dark:hover:bg-teal-900/40"
                        >
                          <svg
                            class="h-4 w-4"
                            fill="none"
                            viewBox="0 0 24 24"
                            stroke-width="1.5"
                            stroke="currentColor"
                          >
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3"
                            />
                          </svg>
                          Try the "{@key_search_filter}" key anyway
                        </button>
                      <% end %>
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
            <% table_dataset =
                 DataTable.from_stats(
                   @stats,
                   granularity: @granularity,
                   empty_message: "No data available yet."
                 ) %>
            <DataTable.table
              dataset={table_dataset}
              transponder_info={@transponder_info}
              outer_class="bg-white dark:bg-slate-800"
            />
            
    <!-- Sticky Summary Footer -->
            <%= if summary = get_summary_stats(assigns) do %>
              <div class="sticky bottom-0 border-t border-white/60 dark:border-white/10 bg-white/80 dark:bg-slate-800/70 backdrop-blur-xl px-4 py-3 shadow-lg dark:shadow-none z-30">
                <div class="flex flex-wrap items-center gap-4 text-xs">
                  <!-- Selected Key (only show if key is selected) -->
                  <%= if summary.key do %>
                    <div class="flex items-center gap-1">
                      <svg
                        class="h-4 w-4 text-teal-500"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M12 3c2.755 0 5.455.232 8.083.678.533.09.917.556.917 1.096v1.044a2.25 2.25 0 0 1-.659 1.591l-5.432 5.432a2.25 2.25 0 0 0-.659 1.591v2.927a2.25 2.25 0 0 1-1.244 2.013L9.75 21v-6.568a2.25 2.25 0 0 0-.659-1.591L3.659 7.409A2.25 2.25 0 0 1 3 5.818V4.774c0-.54.384-1.006.917-1.096A48.32 48.32 0 0 1 12 3Z"
                        />
                      </svg>
                      <span class="font-medium text-gray-700 dark:text-slate-300">Key:</span>
                      <span
                        class="font-mono text-gray-900 dark:text-white max-w-xs truncate"
                        title={summary.key}
                      >
                        {summary.key}
                      </span>
                    </div>
                  <% end %>
                  
    <!-- Columns -->
                  <div class="flex items-center gap-1">
                    <svg
                      class="h-4 w-4 text-teal-500"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke-width="1.5"
                      stroke="currentColor"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="M9 4.5v15m6-15v15m-10.875 0h15.75c.621 0 1.125-.504 1.125-1.125V5.625c0-.621-.504-1.125-1.125-1.125H4.125C3.504 4.5 3 5.004 3 5.625v12.75c0 .621.504 1.125 1.125 1.125Z"
                      />
                    </svg>
                    <span class="font-medium text-gray-700 dark:text-slate-300">Columns:</span>
                    <span class="text-gray-900 dark:text-white">{summary.column_count}</span>
                  </div>
                  
    <!-- Paths -->
                  <div class="flex items-center gap-1">
                    <svg
                      class="h-4 w-4 text-teal-500"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke-width="1.5"
                      stroke="currentColor"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5"
                      />
                    </svg>
                    <span class="font-medium text-gray-700 dark:text-slate-300">Paths:</span>
                    <span class="text-gray-900 dark:text-white">{summary.path_count}</span>
                  </div>
                  
    <!-- Transponders -->
                  <div class="flex items-center gap-1">
                    <svg
                      class="h-4 w-4 text-teal-500"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke-width="1.5"
                      stroke="currentColor"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="m21 7.5-2.25-1.313M21 7.5v2.25m0-2.25-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3 2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75 2.25-1.313M12 21.75V19.5m0 2.25-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25"
                      />
                    </svg>
                    <span class="font-medium text-gray-700 dark:text-slate-300">Transponders:</span>
                    
    <!-- Success count -->
                    <div class="flex items-center gap-1">
                      <svg
                        class="h-3 w-3 text-green-600"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
                        />
                      </svg>
                      <span class="text-gray-900 dark:text-white">
                        {summary.successful_transponders}
                      </span>
                    </div>
                    
    <!-- Fail count -->
                    <div class="flex items-center gap-1">
                      <svg
                        class="h-3 w-3 text-red-500"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"
                        />
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
                      <svg
                        class="h-4 w-4 text-teal-500"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="m3.75 13.5 10.5-11.25L12 10.5h8.25L9.75 21.75 12 13.5H3.75Z"
                        />
                      </svg>
                      <span class="text-gray-900 dark:text-white">
                        {format_duration(@load_duration_microseconds)}
                      </span>
                    </div>
                  <% end %>
                  
    <!-- Export drop-up -->
                  <div
                    id="explore-download-menu"
                    class="ml-auto relative"
                    data-default-label="Export"
                    data-download-menu="true"
                    phx-hook="DownloadMenu"
                  >
                    <button
                      type="button"
                      phx-click="toggle_export_dropdown"
                      data-role="download-button"
                      class="inline-flex items-center rounded-md bg-white dark:bg-slate-700 px-2.5 py-1.5 text-xs font-medium text-gray-700 dark:text-slate-200 shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                    >
                      <span class="mr-1 inline-flex items-center" data-role="download-icon">
                        <svg
                          xmlns="http://www.w3.org/2000/svg"
                          class="h-4 w-4 text-teal-600 dark:text-teal-400"
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
                      </span>
                      <span class="mr-1 hidden" data-role="download-spinner">
                        <span class="inline-flex h-4 w-4 items-center justify-center">
                          <span class="h-4 w-4 rounded-full border-2 border-teal-500 border-t-transparent dark:border-slate-300 dark:border-t-transparent animate-spin"></span>
                        </span>
                      </span>
                      <span class="inline" data-role="download-text">Export</span>
                      <svg
                        class="ml-1 h-3 w-3 text-gray-500 dark:text-slate-400"
                        xmlns="http://www.w3.org/2000/svg"
                        viewBox="0 0 20 20"
                        fill="currentColor"
                      >
                        <path
                          fill-rule="evenodd"
                          d="M5.23 7.21a.75.75 0 011.06.02L10 10.94l3.71-3.71a.75.75 0 011.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
                          clip-rule="evenodd"
                        />
                      </svg>
                    </button>
                    <%= if @show_export_dropdown do %>
                      <div
                        data-role="download-dropdown"
                        class="absolute bottom-9 right-0 w-48 bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-md shadow-lg py-1 z-40"
                        phx-click-away="hide_export_dropdown"
                      >
                        <button
                          type="button"
                          phx-click="download_explore_csv"
                          data-export-trigger="csv"
                          class="w-full text-left px-3 py-2 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700 flex items-center"
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
                          phx-click="download_explore_json"
                          data-export-trigger="json"
                          class="w-full text-left px-3 py-2 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700 flex items-center"
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
                      </div>
                    <% end %>
                  </div>
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
                <div class="fixed inset-0 transition-opacity bg-gray-500 bg-opacity-75 dark:bg-gray-900 dark:bg-opacity-75">
                </div>

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
    <% end %>
    """
  end
end
