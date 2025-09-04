defmodule TrifleApp.TimeframeParsing do
  @moduledoc """
  Unified timeframe parsing and formatting utilities.
  
  Handles parsing of smart timeframe inputs, custom ranges, and formatting
  for display across different LiveView components.
  """
  
  
  @doc """
  Parses smart timeframe input (e.g., "5m", "1h", "24h", "7d") into DateTime range.
  
  Returns {:ok, from, to, smart_input, use_fixed_display} or {:error, reason}
  """
  def parse_smart_timeframe(input, config) when input in ["", nil] do
    # Default to 24 hours
    parse_smart_timeframe("24h", config)
  end
  
  def parse_smart_timeframe("c", config) do
    # Custom timeframe - return a default range and indicate custom mode
    to = DateTime.utc_now() |> DateTime.shift_zone!(config.time_zone || "UTC")
    from = DateTime.add(to, -24 * 60 * 60, :second)
    {:ok, from, to, "c", true}
  end
  
  def parse_smart_timeframe(input, config) do
    case String.contains?(input, " - ") do
      true ->
        parse_direct_timeframe(input, config)
      false ->
        parse_relative_timeframe(input, config)
    end
  end
  
  defp parse_relative_timeframe(input, config) do
    try do
      parser = Trifle.Stats.Nocturnal.Parser.new(input)

      if Trifle.Stats.Nocturnal.Parser.valid?(parser) do
        to = DateTime.utc_now() |> DateTime.shift_zone!(config.time_zone || "UTC")
        nocturnal = Trifle.Stats.Nocturnal.new(to, config)

        from = case Trifle.Stats.Nocturnal.add(nocturnal, -parser.offset, parser.unit) do
          from_datetime when is_struct(from_datetime, DateTime) -> from_datetime
          _ -> raise "Failed to calculate from time"
        end

        {:ok, from, to, input, false}
      else
        {:error, "Invalid format. Use formats like: 1s, 5m, 2h, 1d, 3w, 6mo, 1q, 1y"}
      end
    rescue
      _ -> {:error, "Invalid format. Use formats like: 1s, 5m, 2h, 1d, 3w, 6mo, 1q, 1y"}
    end
  end
  
  defp parse_direct_timeframe(input, config) do
    case String.split(input, " - ") do
      [from_str, to_str] when length([from_str, to_str]) == 2 ->
        with {:ok, from} <- parse_date(from_str, config.time_zone || "UTC"),
             {:ok, to} <- parse_date(to_str, config.time_zone || "UTC") do
          detected_shorthand = detect_shorthand_from_range(from, to, config)
          {:ok, from, to, detected_shorthand, true}
        else
          _ -> {:error, "Invalid datetime format"}
        end
      _ ->
        {:error, "Invalid timeframe format"}
    end
  end
  
  def parse_date(date_str, time_zone) do
    case NaiveDateTime.from_iso8601(date_str) do
      {:ok, naive} -> {:ok, DateTime.from_naive!(naive, time_zone)}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def detect_shorthand_from_range(from, to, config) do
    diff_seconds = DateTime.diff(to, from, :second)
    now = DateTime.utc_now() |> DateTime.shift_zone!(config.time_zone || "UTC")
    to_diff_from_now = abs(DateTime.diff(to, now, :second))
    
    if to_diff_from_now <= 60 do
      case diff_seconds do
        300 -> "5m"
        600 -> "10m"
        900 -> "15m"
        1800 -> "30m"
        3600 -> "1h"
        7200 -> "2h"
        10800 -> "3h"
        21600 -> "6h"
        43200 -> "12h"
        86400 -> "1d"
        172800 -> "2d"
        259200 -> "3d"
        604800 -> "1w"
        1209600 -> "2w"
        2629746 -> "1mo"
        5259492 -> "2mo"
        7889238 -> "3mo"
        15778476 -> "6mo"
        31556952 -> "1y"
        _ -> "c"
      end
    else
      "c"
    end
  end
  
  @doc """
  Formats timeframe for display in inputs and UI.
  """
  def format_smart_timeframe_display(smart_input, config, use_fixed_display \\ false, fixed_from \\ nil, fixed_to \\ nil)
  
  def format_smart_timeframe_display(smart_input, _config, _, _, _) when smart_input in ["", nil] do
    ""
  end
  
  def format_smart_timeframe_display(_smart_input, _config, true, fixed_from, fixed_to)
      when not is_nil(fixed_from) and not is_nil(fixed_to) do
    format_timeframe_display(fixed_from, fixed_to)
  end
  
  def format_smart_timeframe_display(smart_input, config, _, _, _) do
    case parse_smart_timeframe(smart_input, config) do
      {:ok, from, to, _detected, _fixed} ->
        format_timeframe_display(from, to)
      {:error, _reason} ->
        smart_input
    end
  end
  
  def format_timeframe_display(from, to) do
    from_date = from |> DateTime.to_date() |> Date.to_string()
    to_date = to |> DateTime.to_date() |> Date.to_string()
    from_time = DateTime.to_time(from) |> Time.truncate(:second) |> Time.to_string()
    to_time = DateTime.to_time(to) |> Time.truncate(:second) |> Time.to_string()

    # Always show full format as requested
    "#{from_date} #{from_time} - #{to_date} #{to_time}"
  end
  
  @doc """
  Formats DateTime for HTML datetime-local input.
  """
  def format_for_datetime_input(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_iso8601()
  end
  
  @doc """
  Gets timezone offset display string.
  """
  def get_timezone_offset_display(timezone) do
    try do
      now = DateTime.utc_now()
      tz_now = DateTime.shift_zone!(now, timezone)
      
      # Get offset in seconds
      offset_seconds = case DateTime.to_unix(tz_now) - DateTime.to_unix(now) do
        0 -> 0
        diff when diff > 0 -> diff
        diff -> diff
      end
      
      hours = div(abs(offset_seconds), 3600)
      minutes = div(rem(abs(offset_seconds), 3600), 60)
      sign = if offset_seconds >= 0, do: "+", else: "-"
      
      " (#{sign}#{String.pad_leading("#{hours}", 2, "0")}:#{String.pad_leading("#{minutes}", 2, "0")})"
    rescue
      _ -> ""
    end
  end
  
  @doc """
  Gets available timeframe presets for dropdown.
  """
  def timeframe_presets do
    [
      {"5m", "Last 5 minutes"},
      {"15m", "Last 15 minutes"},
      {"30m", "Last 30 minutes"},
      {"1h", "Last hour"},
      {"6h", "Last 6 hours"},
      {"12h", "Last 12 hours"},
      {"24h", "Last 24 hours"},
      {"2d", "Last 2 days"},
      {"7d", "Last week"},
      {"30d", "Last 30 days"},
      {"90d", "Last 3 months"},
      {"1y", "Last year"}
    ]
  end
  
  @doc """
  Converts description back to short code for reverse lookup.
  """
  def find_short_code_from_description(input) do
    preset_map = Enum.into(timeframe_presets(), %{}, fn {short_code, description} ->
      {description, short_code}
    end)

    preset_map[input]
  end
  
  @doc """
  Generates description from shorthand for display purposes.
  """
  def generate_description_from_shorthand(input) do
    case input do
      "5m" -> "Last 5 minutes"
      "15m" -> "Last 15 minutes"
      "30m" -> "Last 30 minutes"
      "1h" -> "Last 1 hour"
      "4h" -> "Last 4 hours"
      "24h" -> "Last 1 day"
      "1d" -> "Last 1 day"
      "2d" -> "Last 2 days"
      "1w" -> "Last 1 week"
      "1mo" -> "Last 1 month"
      "c" -> "Custom"
      _ -> input
    end
  end
  
  @doc """
  Gets description for smart timeframe input.
  """
  def get_smart_timeframe_description(smart_input) when smart_input in ["", nil], do: ""
  def get_smart_timeframe_description(smart_input), do: generate_description_from_shorthand(smart_input)
  
  @doc """
  Calculates previous timeframe based on current from/to range.
  """
  def calculate_previous_timeframe(from, to) do
    duration = DateTime.diff(to, from, :second)
    new_to = from
    new_from = DateTime.add(from, -duration, :second)
    {new_from, new_to}
  end
  
  @doc """
  Calculates next timeframe based on current from/to range.
  """
  def calculate_next_timeframe(from, to) do
    duration = DateTime.diff(to, from, :second)
    new_from = to
    new_to = DateTime.add(to, duration, :second)
    {new_from, new_to}
  end
end