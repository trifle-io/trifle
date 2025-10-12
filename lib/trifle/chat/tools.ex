defmodule Trifle.Chat.Tools do
  @moduledoc """
  Tool catalogue and execution layer exposed to OpenAI for ChatLive.
  """

  alias Decimal, as: D
  alias Trifle.Chat.Notifier
  alias Trifle.Chat.Session
  alias Trifle.Stats.SeriesFetcher
  alias Trifle.Stats.Source
  alias TrifleApp.TimeframeParsing

  @default_timeframe "24h"
  @default_granularity "1h"
  @system_key "__system__key__"

  @type context :: %{
          required(:source) => Source.t() | nil,
          optional(:sources) => [Source.t()],
          optional(:user) => struct(),
          optional(:organization) => struct(),
          optional(:notify) => function() | pid()
        }

  @doc """
  OpenAI tool specification list.
  """
  @spec definitions(context()) :: [map()]
  def definitions(context) do
    [
      %{
        "type" => "function",
        "function" => %{
          "name" => "fetch_metric_timeseries",
          "description" =>
            "Fetch detailed metric timeline data from the active analytics source. " <>
              "Use this when you need concrete numbers to answer the user.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "metric_key" => %{
                "type" => "string",
                "description" => "Metric identifier (exact key) to query."
              },
              "timeframe" => %{
                "type" => "string",
                "description" =>
                  "Shortcut timeframe like 24h, 7d, 1mo. Overrides from/to if present."
              },
              "from" => %{
                "type" => "string",
                "description" => "ISO8601 start timestamp (UTC)."
              },
              "to" => %{
                "type" => "string",
                "description" => "ISO8601 end timestamp (UTC)."
              },
              "granularity" => %{
                "type" => "string",
                "description" =>
                  "Sampling window such as 1m, 1h, 1d. Defaults to source preference."
              }
            },
            "required" => ["metric_key"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "list_available_metrics",
          "description" =>
            "Inspect the active analytics source and return observed metric keys. " <>
              "Use this when you are unsure which metrics exist.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "timeframe" => %{
                "type" => "string",
                "description" => "Optional timeframe window to analyse (default 7d)."
              },
              "granularity" => %{
                "type" => "string",
                "description" => "Sampling window such as 1h. Defaults to source preference."
              }
            },
            "required" => []
          }
        }
      }
    ]
    |> maybe_add_select_source(context)
  end

  defp maybe_add_select_source(definitions, %{sources: sources}) when is_list(sources) do
    definitions ++
      [
        %{
          "type" => "function",
          "function" => %{
            "name" => "explain_available_sources",
            "description" =>
              "Returns the analytics sources the user can access so you can confirm the right context.",
            "parameters" => %{
              "type" => "object",
              "properties" => %{},
              "required" => []
            }
          }
        }
      ]
  end

  defp maybe_add_select_source(definitions, _), do: definitions

  @doc """
  Executes a tool call with decoded arguments, returning a tuple ready to be
  serialized for OpenAI's tool response.
  """
  @spec execute(String.t(), String.t(), context()) ::
          {:ok, map()} | {:error, map()}
  def execute("fetch_metric_timeseries", arguments_json, context) do
    with {:ok, args} <- decode_args(arguments_json),
         {:ok, source} <- ensure_source(context),
         {:ok, metric_key} <- require_string(args, "metric_key", "Metric key required."),
         {:ok, {from, to, timeframe_label}} <- resolve_timeframe(args, source),
         {:ok, granularity} <- resolve_granularity(args, source),
         :ok <-
           Notifier.notify(
             context,
             {:progress, :fetching_timeseries,
              %{
                metric_key: metric_key,
                timeframe: timeframe_label,
                from: DateTime.to_iso8601(from),
                to: DateTime.to_iso8601(to),
                granularity: granularity
              }}
           ),
         {:ok, result} <-
           SeriesFetcher.fetch_series(
             source,
             metric_key,
             from,
             to,
             granularity,
             [],
             progressive: false
           ) do
      {:ok,
       %{
         status: "ok",
         metric_key: metric_key,
         timeframe: %{
           from: DateTime.to_iso8601(from),
           to: DateTime.to_iso8601(to),
           label: timeframe_label,
           granularity: granularity
         },
         summary: summarise_series(result.series),
         timeline: format_series_points(result.series)
       }}
    else
      {:error, %{} = err} ->
        Notifier.notify(context, {:progress, :tool_error, %{tool: "fetch_metric_timeseries"}})
        {:error, err}

      {:error, reason} ->
        Notifier.notify(context, {:progress, :tool_error, %{tool: "fetch_metric_timeseries"}})
        {:error, %{status: "error", error: inspect(reason)}}
    end
  end

  def execute("list_available_metrics", arguments_json, context) do
    with {:ok, args} <- decode_args(arguments_json),
         {:ok, source} <- ensure_source(context),
         {:ok, {from, to, timeframe_label}} <- resolve_timeframe(args, source, "7d"),
         {:ok, granularity} <- resolve_granularity(args, source),
         :ok <-
           Notifier.notify(
             context,
             {:progress, :listing_metrics,
              %{
                timeframe: timeframe_label,
                from: DateTime.to_iso8601(from),
                to: DateTime.to_iso8601(to),
                granularity: granularity
              }}
           ),
         {:ok, result} <-
           SeriesFetcher.fetch_series(
             source,
             @system_key,
             from,
             to,
             granularity,
             [],
             progressive: false
           ) do
      metrics =
        result.series.series
        |> Map.get(:values, [])
        |> Enum.map(&Map.get(&1, "keys", %{}))
        |> Enum.reduce(%{}, fn keys_map, acc ->
          Map.merge(acc, keys_map, fn _key, left, right -> (left || 0) + (right || 0) end)
        end)
        |> Enum.map(fn {key, count} -> %{metric_key: key, observations: count} end)
        |> Enum.sort_by(& &1.metric_key)

      {:ok,
       %{
         status: "ok",
         timeframe: %{
           from: DateTime.to_iso8601(from),
           to: DateTime.to_iso8601(to),
           label: timeframe_label,
           granularity: granularity
         },
         metrics: metrics,
         total_metrics: length(metrics)
       }}
    else
      {:error, %{} = err} ->
        Notifier.notify(context, {:progress, :tool_error, %{tool: "list_available_metrics"}})
        {:error, err}

      {:error, reason} ->
        Notifier.notify(context, {:progress, :tool_error, %{tool: "list_available_metrics"}})
        {:error, %{status: "error", error: inspect(reason)}}
    end
  end

  def execute("explain_available_sources", _arguments_json, context) do
    sources =
      context
      |> Map.get(:sources, [])
      |> Enum.map(fn source ->
        %{
          id: Source.id(source) |> to_string(),
          type: Source.type(source) |> Atom.to_string(),
          display_name: Source.display_name(source),
          time_zone: Source.time_zone(source),
          granularities: Source.available_granularities(source)
        }
      end)

    {:ok,
     %{
       status: "ok",
       sources: sources,
       active_source:
         context
         |> Map.get(:source)
         |> case do
           nil -> nil
           source -> to_string(Source.id(source))
         end
     }}
  end

  def execute(tool_name, arguments_json, _context) do
    {:error,
     %{
       status: "error",
       error: "Tool #{tool_name} not implemented",
       arguments: arguments_json
     }}
  end

  @doc """
  Builds the system prompt tailored to the active context.
  """
  @spec system_prompt(context()) :: String.t()
  def system_prompt(context) do
    active_source_text =
      case Map.get(context, :source) do
        nil ->
          "No analytics source is currently selected. Request the user to pick one or call `explain_available_sources`."

        source ->
          "You are analysing data for: " <>
            "#{Source.display_name(source)} (#{Source.type(source)} #{Source.id(source)}). " <>
            "Time zone: #{Source.time_zone(source)}."
      end

    sources_text =
      context
      |> Map.get(:sources, [])
      |> Enum.map(fn source ->
        "- #{Source.display_name(source)} [#{Source.type(source)} #{Source.id(source)}]"
      end)
      |> Enum.join("\n")

    """
    You are Trifle AI, an analytics copilot inside Trifle. You help users interpret metrics and must
    rely on the provided tools when data is required. Never fabricate numbers – fetch them.

    #{active_source_text}
    #{if sources_text != "", do: "Accessible sources:\n#{sources_text}", else: ""}

    Output short, factual explanations. Always cite the metric key and timeframe you used.
    If a tool fails, report the error plainly and suggest a safe follow-up.
    """
  end

  defp decode_args(arguments_json) when is_binary(arguments_json) do
    case Jason.decode(arguments_json) do
      {:ok, map} when is_map(map) ->
        {:ok, map}

      {:ok, other} ->
        {:error, %{status: "error", error: "Arguments must be an object", raw: other}}

      {:error, reason} ->
        {:error, %{status: "error", error: "Invalid JSON", details: reason}}
    end
  end

  defp ensure_source(%{source: %Source{} = source}), do: {:ok, source}

  defp ensure_source(_),
    do:
      {:error,
       %{
         status: "error",
         error: "No analytics source selected. Ask the user to pick one."
       }}

  defp require_string(args, key, message) do
    value = Map.get(args, key)

    if is_binary(value) and String.trim(value) != "" do
      {:ok, String.trim(value)}
    else
      {:error, %{status: "error", error: message}}
    end
  end

  defp resolve_timeframe(args, source, default_shorthand \\ @default_timeframe) do
    config = Source.stats_config(source)
    now = DateTime.utc_now() |> DateTime.shift_zone!(config.time_zone || "UTC")

    cond do
      is_binary(args["timeframe"]) and String.trim(args["timeframe"]) != "" ->
        case TimeframeParsing.parse_smart_timeframe(args["timeframe"], config) do
          {:ok, from, to, label, _} -> {:ok, {from, to, label}}
          {:error, _} -> {:error, %{status: "error", error: "Invalid timeframe"}}
        end

      args["from"] && args["to"] ->
        with {:ok, from} <- parse_datetime(args["from"], config.time_zone),
             {:ok, to} <- parse_datetime(args["to"], config.time_zone) do
          {:ok, {from, to, "custom"}}
        else
          _ -> {:error, %{status: "error", error: "Invalid from/to datetimes"}}
        end

      true ->
        shorthand =
          Source.default_timeframe(source) ||
            default_shorthand ||
            derive_shorthand(now, 24 * 60 * 60)

        case TimeframeParsing.parse_smart_timeframe(shorthand, config) do
          {:ok, from, to, label, _} -> {:ok, {from, to, label}}
          {:error, _} -> {:error, %{status: "error", error: "Unable to determine timeframe"}}
        end
    end
  end

  defp derive_shorthand(now, seconds) do
    cond do
      seconds <= 3600 -> "1h"
      seconds <= 12 * 3600 -> "12h"
      seconds <= 24 * 3600 -> "24h"
      seconds <= 7 * 24 * 3600 -> "7d"
      seconds <= 30 * 24 * 3600 -> "30d"
      true -> "90d"
    end
  end

  defp parse_datetime(value, time_zone) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} ->
        {:ok, DateTime.shift_zone!(dt, time_zone)}

      {:error, _} ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive} -> {:ok, DateTime.from_naive!(naive, time_zone)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp resolve_granularity(args, source) do
    available =
      source
      |> Source.available_granularities()
      |> List.wrap()

    supplied = args["granularity"]

    cond do
      is_binary(supplied) and supplied in available ->
        {:ok, supplied}

      is_binary(supplied) and supplied not in available and available != [] ->
        {:error,
         %{
           status: "error",
           error: "Granularity #{supplied} not supported.",
           allowed: available
         }}

      available != [] ->
        {:ok,
         Source.default_granularity(source) ||
           hd(available) ||
           @default_granularity}

      true ->
        {:ok, Source.default_granularity(source) || @default_granularity}
    end
  end

  defp summarise_series(%Trifle.Stats.Series{} = series) do
    data_points = series.series[:values] || []
    flattened_rows = Enum.map(data_points, &flatten_numeric_paths/1)

    flattened_rows
    |> Enum.reduce(%{}, fn row, acc ->
      Enum.reduce(row, acc, fn {path, value}, inner ->
        Map.update(inner, path, [value], fn existing -> [value | existing] end)
      end)
    end)
    |> Enum.map(fn {path, values} ->
      numeric_values =
        values
        |> Enum.map(&convert_numeric/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.reverse()

      if numeric_values == [] do
        nil
      else
        %{
          path: path,
          count: length(numeric_values),
          sum: Enum.sum(numeric_values),
          average: safe_average(numeric_values),
          min: Enum.min(numeric_values),
          max: Enum.max(numeric_values),
          latest: List.last(numeric_values)
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp summarise_series(_), do: []

  defp safe_average(list) when length(list) == 0, do: 0.0
  defp safe_average(list), do: Enum.sum(list) / length(list)

  defp format_series_points(%Trifle.Stats.Series{} = series) do
    timeline = series.series[:at] || []
    values = series.series[:values] || []

    timeline
    |> Enum.zip(values)
    |> Enum.map(fn {timestamp, data} ->
      %{
        at: timestamp |> ensure_datetime() |> DateTime.to_iso8601(),
        data: convert_data_map(data)
      }
    end)
  end

  defp format_series_points(_), do: []

  defp ensure_datetime(%DateTime{} = dt), do: dt

  defp ensure_datetime(%NaiveDateTime{} = ndt),
    do: DateTime.from_naive!(ndt, "Etc/UTC")

  defp ensure_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp ensure_datetime(_), do: DateTime.utc_now()

  defp convert_data_map(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} -> {to_string(k), convert_data_map(v)} end)
    |> Map.new()
  end

  defp convert_data_map(list) when is_list(list), do: Enum.map(list, &convert_data_map/1)

  defp convert_data_map(%D{} = decimal), do: D.to_float(decimal)
  defp convert_data_map(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp convert_data_map(other), do: other

  defp convert_numeric(%D{} = decimal), do: D.to_float(decimal)
  defp convert_numeric(number) when is_number(number), do: number
  defp convert_numeric(_other), do: nil

  defp flatten_numeric_paths(value, prefix \\ nil)

  defp flatten_numeric_paths(%{} = map, prefix) do
    Enum.reduce(map, %{}, fn {key, v}, acc ->
      path = join_path(prefix, key)
      Map.merge(acc, flatten_numeric_paths(v, path))
    end)
  end

  defp flatten_numeric_paths(list, prefix) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {v, index}, acc ->
      path = join_path(prefix, Integer.to_string(index))
      Map.merge(acc, flatten_numeric_paths(v, path))
    end)
  end

  defp flatten_numeric_paths(%D{} = decimal, prefix) when not is_nil(prefix),
    do: %{prefix => D.to_float(decimal)}

  defp flatten_numeric_paths(number, prefix) when is_number(number) and not is_nil(prefix),
    do: %{prefix => number}

  defp flatten_numeric_paths(_other, _prefix), do: %{}

  defp join_path(nil, key), do: to_string(key)
  defp join_path(prefix, key), do: "#{prefix}.#{key}"
end
