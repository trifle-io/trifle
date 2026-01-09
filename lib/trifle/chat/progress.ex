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

    parts =
      [
        metric && "Metrics Key #{metric}",
        timeframe && timeframe,
        granularity && "granularity #{granularity}"
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

  def text(:aggregating_series, payload) when is_map(payload) do
    metric = Map.get(payload, "metric_key") || Map.get(payload, :metric_key)
    value_path = Map.get(payload, "value_path") || Map.get(payload, :value_path)

    aggregator =
      payload
      |> Map.get("aggregator", Map.get(payload, :aggregator))
      |> case do
        nil -> nil
        value -> "using #{value |> to_string() |> String.upcase()}"
      end

    descriptor =
      [metric && "Metrics Key #{metric}", value_path && "path #{value_path}", aggregator]
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

    formatter =
      payload
      |> Map.get("formatter", Map.get(payload, :formatter))
      |> case do
        nil -> nil
        value -> "#{value |> to_string() |> String.capitalize()} formatter"
      end

    descriptor =
      [formatter, metric && "Metrics Key #{metric}", value_path && "path #{value_path}"]
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

    ensure_period("Issue encountered while running #{tool}")
  end

  def text(:error, payload) when is_map(payload) do
    reason =
      payload
      |> Map.get("reason", Map.get(payload, :reason))
      |> case do
        nil -> ""
        %{} = map -> inspect(map)
        other -> to_string(other)
      end

    ensure_period("Chat error: #{reason}")
  end

  def text(:error, payload), do: ensure_period("Chat error: #{inspect(payload)}")

  def text(_, _), do: nil

  defp ensure_period(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.trim_trailing(".")
    |> Kernel.<>(".")
  end
end
