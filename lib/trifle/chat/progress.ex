defmodule Trifle.Chat.Progress do
  @moduledoc """
  Shared helpers for chat progress events (status lines, human-readable text).
  """

  @type event_type :: atom() | String.t()
  @type payload :: map()

  @spec text(event_type(), payload()) :: String.t() | nil
  def text(type, payload \\ %{})

  def text(type, payload) when is_binary(type) do
    case type do
      "resume" -> text(:resume, payload)
      "thinking" -> text(:thinking, payload)
      "fetching_timeseries" -> text(:fetching_timeseries, payload)
      "listing_metrics" -> text(:listing_metrics, payload)
      "inspecting_metric_schema" -> text(:inspecting_metric_schema, payload)
      "aggregating_series" -> text(:aggregating_series, payload)
      "formatting_series" -> text(:formatting_series, payload)
      "processing_results" -> text(:processing_results, payload)
      "responding" -> text(:responding, payload)
      "tool_error" -> text(:tool_error, payload)
      "error" -> text(:error, payload)
      _ -> nil
    end
  end

  def text(:resume, _payload), do: ensure_period("Resuming conversation")

  def text(:thinking, %{"iteration" => iteration}) when is_integer(iteration) and iteration > 1 do
    ensure_period("Refining approach")
  end

  def text(:thinking, _payload), do: ensure_period("Thinking")

  def text(:fetching_timeseries, payload) when is_map(payload) do
    metric = Map.get(payload, "metric_key") || Map.get(payload, :metric_key)
    timeframe = Map.get(payload, "timeframe") || Map.get(payload, :timeframe)
    granularity = Map.get(payload, "granularity") || Map.get(payload, :granularity)
    adjusted_from = Map.get(payload, "adjusted_from") || Map.get(payload, :adjusted_from)

    parts =
      [
        metric && "Metrics Key #{metric}",
        timeframe && timeframe,
        granularity && "granularity #{granularity}",
        adjusted_from && "adjusted from #{adjusted_from}"
      ]
      |> Enum.reject(&is_nil/1)

    descriptor =
      case parts do
        [] -> "active source"
        list -> Enum.join(list, " • ")
      end

    ensure_period("Fetching data for #{descriptor}")
  end

  def text(:listing_metrics, payload) when is_map(payload) do
    timeframe = Map.get(payload, "timeframe") || Map.get(payload, :timeframe)
    granularity = Map.get(payload, "granularity") || Map.get(payload, :granularity)

    descriptor =
      [timeframe, granularity && "granularity #{granularity}"]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" • ")

    case descriptor do
      "" -> ensure_period("Listing available Metrics Keys")
      other -> ensure_period("Listing available Metrics Keys (#{other})")
    end
  end

  def text(:inspecting_metric_schema, payload) when is_map(payload) do
    metric = Map.get(payload, "metric_key") || Map.get(payload, :metric_key)
    timeframe = Map.get(payload, "timeframe") || Map.get(payload, :timeframe)
    granularity = Map.get(payload, "granularity") || Map.get(payload, :granularity)

    descriptor =
      [metric && "Metrics Key #{metric}", timeframe, granularity && "granularity #{granularity}"]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" • ")

    case descriptor do
      "" -> ensure_period("Inspecting metric schema")
      other -> ensure_period("Inspecting metric schema (#{other})")
    end
  end

  def text(:aggregating_series, payload) when is_map(payload) do
    metric = Map.get(payload, "metric_key") || Map.get(payload, :metric_key)
    value_path = Map.get(payload, "value_path") || Map.get(payload, :value_path)
    timeframe = Map.get(payload, "timeframe") || Map.get(payload, :timeframe)
    granularity = Map.get(payload, "granularity") || Map.get(payload, :granularity)
    adjusted_from = Map.get(payload, "adjusted_from") || Map.get(payload, :adjusted_from)

    aggregator =
      payload
      |> Map.get("aggregator", Map.get(payload, :aggregator))
      |> case do
        nil -> nil
        value -> "using #{value |> to_string() |> String.upcase()}"
      end

    descriptor =
      [
        metric && "Metrics Key #{metric}",
        value_path && "path #{value_path}",
        aggregator,
        timeframe,
        granularity && "granularity #{granularity}",
        adjusted_from && "adjusted from #{adjusted_from}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" • ")

    case descriptor do
      "" -> ensure_period("Aggregating series data")
      other -> ensure_period("Aggregating series data (#{other})")
    end
  end

  def text(:aggregating_series, _payload), do: ensure_period("Aggregating series data")

  def text(:formatting_series, payload) when is_map(payload) do
    metric = Map.get(payload, "metric_key") || Map.get(payload, :metric_key)
    value_path = Map.get(payload, "value_path") || Map.get(payload, :value_path)
    timeframe = Map.get(payload, "timeframe") || Map.get(payload, :timeframe)
    granularity = Map.get(payload, "granularity") || Map.get(payload, :granularity)
    adjusted_from = Map.get(payload, "adjusted_from") || Map.get(payload, :adjusted_from)

    formatter =
      payload
      |> Map.get("formatter", Map.get(payload, :formatter))
      |> case do
        nil -> nil
        value -> "#{value |> to_string() |> String.capitalize()} formatter"
      end

    descriptor =
      [
        formatter,
        metric && "Metrics Key #{metric}",
        value_path && "path #{value_path}",
        timeframe,
        granularity && "granularity #{granularity}",
        adjusted_from && "adjusted from #{adjusted_from}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" • ")

    case descriptor do
      "" -> ensure_period("Formatting series output")
      other -> ensure_period("Formatting series output (#{other})")
    end
  end

  def text(:formatting_series, _payload), do: ensure_period("Formatting series output")

  def text(:processing_results, _payload), do: ensure_period("Processing tool results")
  def text(:responding, _payload), do: ensure_period("Preparing final answer")

  def text(:tool_error, payload) when is_map(payload) do
    tool =
      payload
      |> Map.get("tool", Map.get(payload, :tool))
      |> case do
        nil -> "the requested tool"
        tool_name when is_binary(tool_name) -> tool_name
        other -> to_string(other)
      end

    reason =
      payload
      |> Map.get("reason", Map.get(payload, :reason))
      |> format_tool_error_reason()

    case reason do
      nil -> ensure_period("Issue encountered while running #{tool}")
      message -> ensure_period("Issue encountered while running #{tool}: #{message}")
    end
  end

  def text(:error, payload) when is_map(payload) do
    reason =
      payload
      |> Map.get("reason", Map.get(payload, :reason))
      |> format_tool_error_reason()

    case reason do
      nil -> ensure_period("Chat error")
      message -> ensure_period("Chat error: #{message}")
    end
  end

  def text(:error, payload), do: ensure_period("Chat error: #{inspect(payload)}")

  def text(_, _), do: nil

  defp ensure_period(text) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" -> "."
      String.ends_with?(trimmed, "...") -> trimmed
      String.ends_with?(trimmed, "!") -> trimmed
      String.ends_with?(trimmed, "?") -> trimmed
      String.ends_with?(trimmed, ".") -> trimmed
      true -> trimmed <> "."
    end
  end

  defp format_tool_error_reason(nil), do: nil

  defp format_tool_error_reason(reason) when is_binary(reason) do
    reason
    |> String.trim()
    |> case do
      "" -> nil
      text -> truncate_reason(text, 160)
    end
  end

  defp format_tool_error_reason(%{} = reason) do
    reason
    |> inspect()
    |> format_tool_error_reason()
  end

  defp format_tool_error_reason(reason) do
    reason
    |> inspect()
    |> format_tool_error_reason()
  end

  defp truncate_reason(text, limit) when is_binary(text) and is_integer(limit) and limit > 3 do
    if String.length(text) <= limit do
      text
    else
      String.slice(text, 0, limit - 3) <> "..."
    end
  end
end
