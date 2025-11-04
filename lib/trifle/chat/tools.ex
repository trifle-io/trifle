defmodule Trifle.Chat.Tools do
  @moduledoc """
  Tool catalogue and execution layer exposed to OpenAI for ChatLive.
  """

  alias Decimal, as: D
  alias Trifle.Chat.Notifier
  alias Trifle.Stats.Source
  alias Trifle.Stats.Tabler
  alias Trifle.Stats.Series
  alias TrifleApp.Components.DashboardWidgets.{Timeseries, Category}
  alias TrifleApp.TimeframeParsing

  @default_timeframe "24h"
  @default_granularity "1h"
  @system_key "__system__key__"
  @aggregators %{
    "sum" => &Series.aggregate_sum/3,
    "mean" => &Series.aggregate_mean/3,
    "min" => &Series.aggregate_min/3,
    "max" => &Series.aggregate_max/3
  }
  @aggregator_names @aggregators |> Map.keys() |> Enum.sort()

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
    aggregator_options = @aggregator_names

    [
      %{
        "type" => "function",
        "function" => %{
          "name" => "fetch_metric_timeseries",
          "description" =>
            "Fetch detailed metric timeline data for a specific Metrics Key on the active analytics source. " <>
              "Use this when you need concrete numbers to answer the user.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "metric_key" => %{
                "type" => "string",
                "description" => "Metrics Key (exact path string) to query."
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
          "name" => "aggregate_metric_series",
          "description" =>
            "Aggregate timeseries values using built-in analytics aggregators (sum, mean, min, max). " <>
              "Use this for totals, averages, and extrema instead of estimating manually.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "metric_key" => %{
                "type" => "string",
                "description" => "Metrics Key (exact path string) to query."
              },
              "value_path" => %{
                "type" => "string",
                "description" =>
                  "Path to the numeric value inside each data point (dot notation, e.g. data.orders.sum)."
              },
              "aggregator" => %{
                "type" => "string",
                "enum" => aggregator_options,
                "description" => "Aggregator to apply. Case-insensitive."
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
              },
              "slices" => %{
                "type" => "integer",
                "minimum" => 1,
                "description" =>
                  "Optional number of equal slices to evaluate (e.g. compare halves). Defaults to 1."
              }
            },
            "required" => ["metric_key", "value_path", "aggregator"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "format_metric_timeline",
          "description" =>
            "Format timeseries data as a timeline for plotting or structured inspection. " <>
              "Returns ISO timestamps with numeric values.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "metric_key" => %{
                "type" => "string",
                "description" => "Metrics Key (exact path string) to query."
              },
              "value_path" => %{
                "type" => "string",
                "description" =>
                  "Path (supports wildcards) pointing to values to include, e.g. timeline.orders or timeline.*.value."
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
              },
              "chart_type" => %{
                "type" => "string",
                "enum" => ["line", "area", "bar"],
                "description" => "Optional chart presentation."
              },
              "stacked" => %{
                "type" => "boolean",
                "description" => "Stack multiple series together (line/area/bar only)."
              },
              "normalized" => %{
                "type" => "boolean",
                "description" => "Convert stacked values into percentages."
              },
              "legend" => %{
                "type" => "boolean",
                "description" => "Force legend visibility (defaults to automatic)."
              },
              "y_label" => %{
                "type" => "string",
                "description" => "Optional label for the Y-axis."
              },
              "slices" => %{
                "type" => "integer",
                "minimum" => 1,
                "description" =>
                  "Optional number of equal slices to partition the timeline (defaults to 1)."
              }
            },
            "required" => ["metric_key", "value_path"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "format_metric_category",
          "description" =>
            "Format metric data into categorical totals (e.g. status buckets or product mix) for charting.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "metric_key" => %{
                "type" => "string",
                "description" => "Metrics Key (exact path string) to query."
              },
              "value_path" => %{
                "type" => "string",
                "description" =>
                  "Path (supports wildcards) pointing to categorical fields, e.g. categories.*.orders."
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
              },
              "chart_type" => %{
                "type" => "string",
                "enum" => ["bar", "pie", "donut"],
                "description" => "Optional visualization style."
              },
              "slices" => %{
                "type" => "integer",
                "minimum" => 1,
                "description" =>
                  "Optional number of equal slices to compare segments over time (defaults to 1)."
              }
            },
            "required" => ["metric_key", "value_path"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "list_available_metrics",
          "description" =>
            "Inspect the active analytics source and return observed Metrics Keys. " <>
              "Use this when you are unsure which paths exist.",
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
         {:ok, metric_key} <- require_string(args, "metric_key", "Metrics Key required."),
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
           Source.fetch_series(
             source,
             metric_key,
             from,
             to,
             granularity,
             progressive: false
           ),
         table <- tabularize_series(result.series) do
      summary = summarise_series(result.series)
      available = available_paths(result.series)

      payload =
        %{
          status: "ok",
          path: metric_key,
          metric_key: metric_key,
          timeframe: %{
            from: DateTime.to_iso8601(from),
            to: DateTime.to_iso8601(to),
            label: timeframe_label,
            granularity: granularity
          },
          summary: summary,
          timeline: format_series_points(result.series),
          available_paths: available
        }
        |> maybe_put_table(table)

      {:ok, payload}
    else
      {:error, %{} = err} ->
        Notifier.notify(context, {:progress, :tool_error, %{tool: "fetch_metric_timeseries"}})
        {:error, err}

      {:error, reason} ->
        Notifier.notify(context, {:progress, :tool_error, %{tool: "fetch_metric_timeseries"}})
        {:error, %{status: "error", error: inspect(reason)}}
    end
  end

  def execute("aggregate_metric_series", arguments_json, context) do
    with {:ok, args} <- decode_args(arguments_json),
         {:ok, source} <- ensure_source(context),
         {:ok, metric_key} <- require_string(args, "metric_key", "Metrics Key required."),
         {:ok, value_path} <- require_string(args, "value_path", "Value path required."),
         {:ok, {aggregator_name, aggregator_fun}} <- resolve_aggregator(args["aggregator"]),
         {:ok, {from, to, timeframe_label}} <- resolve_timeframe(args, source),
         {:ok, granularity} <- resolve_granularity(args, source),
         {:ok, slices} <- resolve_slices(args),
         :ok <-
           Notifier.notify(
             context,
             {:progress, :aggregating_series,
              %{
                metric_key: metric_key,
                value_path: value_path,
                aggregator: aggregator_name,
                timeframe: timeframe_label,
                granularity: granularity
              }}
           ),
         {:ok, result} <-
           Source.fetch_series(
             source,
             metric_key,
             from,
             to,
             granularity,
             progressive: false
           ),
         paths = normalize_paths(value_path),
         {:ok, resolved_path} <- ensure_single_path(paths),
         {:ok, resolved_path} <- ensure_no_wildcards(resolved_path),
         available <- available_paths(result.series),
         :ok <- ensure_paths_exist([resolved_path], available),
         {:ok, values} <- aggregate_series(result.series, aggregator_fun, resolved_path, slices) do
      if values == [] do
        {:error,
         %{
           status: "error",
           error: "No data available for path #{resolved_path} in the selected timeframe.",
           available_paths: available
         }}
      else
        table = tabularize_series(result.series, only_paths: [resolved_path])

        payload =
          %{
            status: "ok",
            aggregator: aggregator_name,
            metric_key: metric_key,
            value_path: resolved_path,
            slices: slices,
            values: values,
            count: length(values),
            timeframe: %{
              from: DateTime.to_iso8601(from),
              to: DateTime.to_iso8601(to),
              label: timeframe_label,
              granularity: granularity
            },
            available_paths: available,
            matched_paths: [resolved_path]
          }
          |> maybe_put_primary_value(slices)
          |> maybe_put_table(table)

        {:ok, payload}
      end
    else
      {:error, %{} = err} ->
        Notifier.notify(context, {:progress, :tool_error, %{tool: "aggregate_metric_series"}})
        {:error, err}

      {:error, reason} ->
        Notifier.notify(context, {:progress, :tool_error, %{tool: "aggregate_metric_series"}})
        {:error, %{status: "error", error: inspect(reason)}}
    end
  end

  def execute("format_metric_timeline", arguments_json, context) do
    with {:ok, args} <- decode_args(arguments_json),
         {:ok, source} <- ensure_source(context),
         {:ok, metric_key} <- require_string(args, "metric_key", "Metrics Key required."),
         {:ok, value_path} <- require_string(args, "value_path", "Value path required."),
         {:ok, {from, to, timeframe_label}} <- resolve_timeframe(args, source),
         {:ok, granularity} <- resolve_granularity(args, source),
         {:ok, slices} <- resolve_slices(args),
         :ok <-
           Notifier.notify(
             context,
             {:progress, :formatting_series,
              %{
                metric_key: metric_key,
                value_path: value_path,
                formatter: "timeline"
              }}
         ),
         {:ok, result} <-
           Source.fetch_series(
             source,
             metric_key,
             from,
             to,
             granularity,
             progressive: false
           ),
         paths = normalize_paths(value_path),
         {:ok, resolved_path} <- ensure_single_path(paths),
         {:ok, resolved_path} <- ensure_no_wildcards(resolved_path),
         available <- available_paths(result.series),
         :ok <- ensure_paths_exist([resolved_path], available),
         table_all <- tabularize_series(result.series),
         {:ok, formatted, matched_paths} <-
           format_timeline_result(result.series, resolved_path, slices),
         matched_paths <- Enum.filter(matched_paths, &Enum.member?(available, &1)),
         true <- matched_paths != [] || {:missing_timeline, available, resolved_path} do
      chart = build_timeseries_chart(result.series, resolved_path, slices, args)
      table = subset_table(table_all, matched_paths)

      payload =
        %{
          status: "ok",
          formatter: "timeline",
          metric_key: metric_key,
          value_path: resolved_path,
          slices: slices,
          timeframe: %{
            from: DateTime.to_iso8601(from),
            to: DateTime.to_iso8601(to),
            label: timeframe_label,
            granularity: granularity
          },
          result: formatted,
          available_paths: available,
          matched_paths: matched_paths
        }
        |> maybe_put_chart(chart)
        |> maybe_put_table(table)

      {:ok, payload}
    else
      {:error, %{} = err} ->
        Notifier.notify(context, {:progress, :tool_error, %{tool: "format_metric_timeline"}})
        {:error, err}

      {:missing_timeline, available, missing_path} ->
        {:error,
         %{
           status: "error",
           error: "No matching data found for path #{missing_path} in the selected timeframe.",
           available_paths: available
         }}

      {:error, reason} ->
        Notifier.notify(context, {:progress, :tool_error, %{tool: "format_metric_timeline"}})
        {:error, %{status: "error", error: inspect(reason)}}
    end
  end

  def execute("format_metric_category", arguments_json, context) do
    with {:ok, args} <- decode_args(arguments_json),
         {:ok, source} <- ensure_source(context),
         {:ok, metric_key} <- require_string(args, "metric_key", "Metrics Key required."),
         {:ok, value_path} <- require_string(args, "value_path", "Value path required."),
         {:ok, {from, to, timeframe_label}} <- resolve_timeframe(args, source),
         {:ok, granularity} <- resolve_granularity(args, source),
         {:ok, slices} <- resolve_slices(args),
         :ok <-
           Notifier.notify(
             context,
             {:progress, :formatting_series,
              %{
                metric_key: metric_key,
                value_path: value_path,
                formatter: "category"
              }}
           ),
         {:ok, result} <-
           Source.fetch_series(
             source,
             metric_key,
             from,
             to,
             granularity,
             progressive: false
           ),
         paths = normalize_paths(value_path),
         {:ok, resolved_path} <- ensure_single_path(paths),
         {:ok, resolved_path} <- ensure_no_wildcards(resolved_path),
         available <- available_paths(result.series),
         {:ok, formatted, matched_paths} <-
           format_category_result(result.series, resolved_path, slices),
         matched_paths <- Enum.filter(matched_paths, &Enum.member?(available, &1)),
         true <- matched_paths != [] || {:missing_categories, available, resolved_path},
         table_all <- tabularize_series(result.series) do
      chart = build_category_chart(result.series, resolved_path, args)
      table = subset_table(table_all, matched_paths)

      payload =
        %{
          status: "ok",
          formatter: "category",
          metric_key: metric_key,
          value_path: resolved_path,
          slices: slices,
          timeframe: %{
            from: DateTime.to_iso8601(from),
            to: DateTime.to_iso8601(to),
            label: timeframe_label,
            granularity: granularity
          },
          result: formatted,
          available_paths: available,
          matched_paths: matched_paths
        }
        |> maybe_put_chart(chart)
        |> maybe_put_table(table)

      {:ok, payload}
    else
      {:error, %{} = err} ->
        Notifier.notify(context, {:progress, :tool_error, %{tool: "format_metric_category"}})
        {:error, err}

      {:missing_categories, available, missing_path} ->
        {:error,
         %{
           status: "error",
           error: "No matching data found for path #{missing_path} in the selected timeframe.",
           available_paths: available
         }}

      {:error, reason} ->
        Notifier.notify(context, {:progress, :tool_error, %{tool: "format_metric_category"}})
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
           Source.fetch_series(
             source,
             @system_key,
             from,
             to,
             granularity,
             progressive: false,
             transponders: :none
           ) do
      paths =
        result.series.series
        |> Map.get(:values, [])
        |> Enum.map(&Map.get(&1, "keys", %{}))
        |> Enum.reduce(%{}, fn keys_map, acc ->
          Map.merge(acc, keys_map, fn _key, left, right -> (left || 0) + (right || 0) end)
        end)
        |> Enum.map(fn {key, count} ->
          %{
            path: key,
            metric_key: key,
            observations: count
          }
        end)
        |> Enum.sort_by(& &1.path)

      {:ok,
       %{
         status: "ok",
         timeframe: %{
           from: DateTime.to_iso8601(from),
           to: DateTime.to_iso8601(to),
           label: timeframe_label,
           granularity: granularity
         },
         paths: paths,
         total_paths: length(paths)
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

    Before attempting to aggregate, format, or visualise a metric, first call `list_available_metrics`
    (or use prior responses) to inspect the precise paths available for the timeframe. After fetching a
    metric, prefer the provided `available_paths` and `matched_paths` without guessing. If a requested path
    is absent, state that explicitly and present the actual paths. Never use wildcard characters (for
    example `*`) in any path—they are not supported by the tools.

    Output short, factual explanations. Always cite the Metrics Key and timeframe you used, and label any retrieved values as [path: ...].
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

  defp derive_shorthand(_now, seconds) do
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

  defp resolve_aggregator(nil) do
    {:error,
     %{
       status: "error",
       error: "Aggregator must be provided (options: #{Enum.join(@aggregator_names, ", ")})."
     }}
  end

  defp resolve_aggregator(value) when is_atom(value), do: resolve_aggregator(Atom.to_string(value))

  defp resolve_aggregator(value) when is_binary(value) do
    key =
      value
      |> String.trim()
      |> String.downcase()

    case Map.get(@aggregators, key) do
      nil ->
        {:error,
         %{
           status: "error",
           error: "Unsupported aggregator #{inspect(value)}.",
           allowed: @aggregator_names
         }}

      fun ->
        {:ok, {key, fun}}
    end
  end

  defp resolve_aggregator(_other) do
    {:error,
     %{
       status: "error",
       error: "Aggregator must be a string."
     }}
  end

  defp aggregate_series(%Series{} = series, aggregator_fun, path, slices)
       when is_function(aggregator_fun, 3) and is_integer(slices) and slices >= 1 do
    try do
      values =
        aggregator_fun.(series, path, slices)
        |> List.wrap()
        |> Enum.map(&convert_numeric/1)
        |> Enum.reject(&is_nil/1)

      {:ok, values}
    rescue
      error ->
        {:error,
         %{
           status: "error",
           error: "Aggregator failed for #{path}: #{Exception.message(error)}"
         }}
    end
  end

  defp aggregate_series(_series, _fun, _path, _slices) do
    {:error,
     %{
       status: "error",
       error: "Series data unavailable."
     }}
  end

  defp maybe_put_chart(payload, nil), do: payload

  defp maybe_put_chart(payload, chart) when is_map(chart) do
    Map.put(payload, :chart, chart)
  end

  defp maybe_put_table(payload, nil), do: payload

  defp maybe_put_table(payload, table) when is_map(table) do
    Map.put(payload, :table, table)
  end

  defp maybe_put_primary_value(%{values: [value | _]} = payload, 1) when not is_nil(value) do
    Map.put(payload, :value, value)
  end

  defp maybe_put_primary_value(payload, _), do: payload

  defp resolve_slices(args, default \\ 1) do
    case Map.get(args, "slices") do
      nil -> {:ok, default}
      value -> cast_positive_integer(value)
    end
  end

  defp cast_positive_integer(value) when is_integer(value) and value >= 1, do: {:ok, value}

  defp cast_positive_integer(value) when is_float(value) and value >= 1 do
    if value == trunc(value) do
      {:ok, trunc(value)}
    else
      slices_error()
    end
  end

  defp cast_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int >= 1 -> {:ok, int}
      _ -> slices_error()
    end
  end

  defp cast_positive_integer(_), do: slices_error()

  defp slices_error do
    {:error,
     %{
       status: "error",
       error: "slices must be a positive integer."
     }}
  end

  defp format_timeline_result(%Series{} = series, path, slices) do
    try do
      result = Series.format_timeline(series, path, slices)
      formatted = normalize_timeline_output(result)
      matched_paths =
        formatted
        |> extract_timeline_paths()
        |> case do
          [] -> [path]
          list -> list
        end

      {:ok, formatted, matched_paths}
    rescue
      error ->
        {:error,
         %{
           status: "error",
           error: "Timeline formatter failed for #{path}: #{Exception.message(error)}"
         }}
    end
  end

  defp format_timeline_result(_series, _path, _slices) do
    {:error,
     %{
       status: "error",
       error: "Series data unavailable."
     }}
  end

  defp format_category_result(%Series{} = series, path, slices) do
    try do
      result = Series.format_category(series, path, slices)
      formatted = normalize_category_output(result)
      matched_paths =
        formatted
        |> extract_category_paths()
        |> case do
          [] -> []
          list -> list
        end

      {:ok, formatted, matched_paths}
    rescue
      error ->
        {:error,
         %{
           status: "error",
           error: "Category formatter failed for #{path}: #{Exception.message(error)}"
         }}
    end
  end

  defp format_category_result(_series, _path, _slices) do
    {:error,
     %{
       status: "error",
       error: "Series data unavailable."
     }}
  end

  defp build_timeseries_chart(%Series{} = series_struct, value_path, slices, args) do
    paths = normalize_paths(value_path)

    if paths == [] do
      nil
    else
      chart_id = "chat-ts-" <> Integer.to_string(System.unique_integer([:positive]))

      item = %{
        "id" => chart_id,
        "type" => "timeseries",
        "paths" => paths,
        "chart_type" => Map.get(args, "chart_type") || Map.get(args, :chart_type) || "line",
        "stacked" => truthy?(Map.get(args, "stacked") || Map.get(args, :stacked)),
        "normalized" => truthy?(Map.get(args, "normalized") || Map.get(args, :normalized)),
        "legend" => truthy?(Map.get(args, "legend") || Map.get(args, :legend)),
        "y_label" => Map.get(args, "y_label") || Map.get(args, :y_label) || ""
      }

      dataset = Timeseries.dataset(series_struct, item)

      %{
        "type" => "timeseries",
        "dataset" => stringify_keys(dataset),
        "slices" => slices,
        "chart_type" => Map.get(item, "chart_type"),
        "legend" => Map.get(item, "legend"),
        "stacked" => Map.get(item, "stacked"),
        "normalized" => Map.get(item, "normalized"),
        "y_label" => Map.get(item, "y_label")
      }
    end
  end

  defp build_category_chart(%Series{} = series_struct, value_path, args) do
    paths = normalize_paths(value_path)

    if paths == [] do
      nil
    else
      chart_id = "chat-cat-" <> Integer.to_string(System.unique_integer([:positive]))

      item = %{
        "id" => chart_id,
        "type" => "category",
        "paths" => paths,
        "chart_type" => Map.get(args, "chart_type") || Map.get(args, :chart_type) || "bar"
      }

      dataset = Category.dataset(series_struct, item)

      %{
        "type" => "category",
        "dataset" => stringify_keys(dataset),
        "chart_type" => Map.get(item, "chart_type")
      }
    end
  end

  defp stringify_keys(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {to_string(k), stringify_keys(v)} end)
    |> Map.new()
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp normalize_paths(value) do
    value
    |> List.wrap()
    |> Enum.flat_map(fn
      path when is_binary(path) ->
        path
        |> String.trim()
        |> case do
          "" -> []
          cleaned -> [cleaned]
        end

      other ->
        other
        |> to_string()
        |> String.trim()
        |> case do
          "" -> []
          cleaned -> [cleaned]
        end
    end)
  end

  defp ensure_single_path([]), do: {:error, %{status: "error", error: "Value path required."}}

  defp ensure_single_path([path]), do: {:ok, path}

  defp ensure_single_path(paths) when is_list(paths) do
    {:error,
     %{
       status: "error",
       error: "Only a single value_path is supported for this tool.",
       provided_paths: paths
     }}
  end

  defp ensure_no_wildcards(path) do
    if String.contains?(path, "*") do
      {:error,
       %{
         status: "error",
         error: "Wildcards are not supported in value_path #{inspect(path)}"
       }}
    else
      {:ok, path}
    end
  end

  defp available_paths(%Series{} = series) do
    series.series[:values]
    |> List.wrap()
    |> Enum.flat_map(fn row ->
      row
      |> flatten_numeric_paths()
      |> Map.keys()
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp available_paths(_), do: []

  defp ensure_paths_exist(paths, available) do
    missing = Enum.reject(paths, &Enum.member?(available, &1))

    case missing do
      [] -> :ok
      _ ->
        {:error,
         %{
           status: "error",
           error: "Unknown path(s): #{Enum.join(missing, ", ")}",
           missing_paths: missing,
           available_paths: available
         }}
    end
  end

  defp extract_timeline_paths(result) when is_map(result) do
    result
    |> Map.keys()
    |> Enum.map(&to_string/1)
  end

  defp extract_timeline_paths(result) when is_list(result) do
    result
    |> Enum.flat_map(&extract_timeline_paths/1)
    |> Enum.uniq()
  end

  defp extract_timeline_paths(_), do: []

  defp extract_category_paths(result) when is_map(result) do
    result
    |> Map.keys()
    |> Enum.map(&to_string/1)
  end

  defp extract_category_paths(result) when is_list(result) do
    result
    |> Enum.flat_map(&extract_category_paths/1)
    |> Enum.uniq()
  end

  defp extract_category_paths(_), do: []

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

  defp convert_data_map(%D{} = decimal), do: normalize_number(D.to_float(decimal))
  defp convert_data_map(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp convert_data_map(number) when is_float(number) or is_integer(number),
    do: normalize_number(number)

  defp convert_data_map(struct) when is_struct(struct) do
    struct
    |> Map.from_struct()
    |> convert_data_map()
  end

  defp convert_data_map(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} -> {to_string(k), convert_data_map(v)} end)
    |> Map.new()
  end

  defp convert_data_map(list) when is_list(list), do: Enum.map(list, &convert_data_map/1)
  defp convert_data_map(other), do: other

  defp convert_numeric(%D{} = decimal), do: normalize_number(D.to_float(decimal))

  defp convert_numeric(number) when is_number(number), do: normalize_number(number)
  defp convert_numeric(_other), do: nil

  defp flatten_numeric_paths(value, prefix \\ nil)

  defp flatten_numeric_paths(%D{} = decimal, prefix) when not is_nil(prefix) do
    case normalize_number(D.to_float(decimal)) do
      nil -> %{}
      cleaned -> %{prefix => cleaned}
    end
  end

  defp flatten_numeric_paths(map, prefix) when is_map(map) and not is_struct(map) do
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

  defp flatten_numeric_paths(number, prefix) when is_number(number) and not is_nil(prefix) do
    case normalize_number(number) do
      nil -> %{}
      cleaned -> %{prefix => cleaned}
    end
  end

  defp flatten_numeric_paths(_other, _prefix), do: %{}

  defp join_path(nil, key), do: to_string(key)
  defp join_path(prefix, key), do: "#{prefix}.#{key}"

  defp normalize_number(number) when is_integer(number), do: number

  defp normalize_number(number) when is_float(number) do
    if number == number do
      number
    else
      nil
    end
  end

  defp normalize_number(_other), do: nil

  defp tabularize_series(series_struct, opts \\ [])

  defp tabularize_series(%Series{} = series_struct, opts) do
    stats = Map.get(series_struct, :series)

    with %{at: at_list, paths: raw_paths, values: values} <- safe_tabulize(stats) do
      normalized_paths =
        raw_paths
        |> Enum.map(&to_string/1)
        |> Enum.uniq()
        |> Enum.sort()

      selected_paths =
        case Keyword.get(opts, :only_paths) do
          nil -> normalized_paths
          filter -> Enum.filter(normalized_paths, &Enum.member?(filter, &1))
        end

      if selected_paths == [] do
        nil
      else
        value_lookup =
          values
          |> Enum.reduce(%{}, fn {{path, at}, value}, acc ->
            Map.put(acc, {to_string(path), at}, convert_numeric(value))
          end)

        timestamps = Enum.reverse(at_list)

        rows =
          Enum.map(timestamps, fn timestamp ->
            iso = ensure_datetime(timestamp) |> DateTime.to_iso8601()
            [iso |
              Enum.map(selected_paths, fn path ->
                Map.get(value_lookup, {path, timestamp})
              end)]
          end)

        %{
          "columns" => ["at" | selected_paths],
          "rows" => rows
        }
      end
    else
      _ -> nil
    end
  end

  defp tabularize_series(_other, _opts), do: nil

  defp safe_tabulize(nil), do: nil

  defp safe_tabulize(stats) do
    Tabler.tabulize(stats)
  rescue
    _ -> nil
  end

  defp subset_table(nil, _paths), do: nil

  defp subset_table(%{"columns" => columns, "rows" => rows}, paths) when is_list(paths) do
    subset_paths = Enum.filter(paths, &Enum.member?(columns, &1))

    if subset_paths == [] do
      nil
    else
      indices =
        ["at" | subset_paths]
        |> Enum.map(fn col -> Enum.find_index(columns, &(&1 == col)) end)

      if Enum.any?(indices, &is_nil/1) do
        nil
      else
        subset_rows =
          rows
          |> Enum.map(fn row -> Enum.map(indices, fn idx -> Enum.at(row, idx) end) end)

        %{
          "columns" => ["at" | subset_paths],
          "rows" => subset_rows
        }
      end
    end
  end

  defp subset_table(_table, _paths), do: nil

  defp normalize_timeline_output(result) when is_map(result) do
    result
    |> Enum.map(fn {path, entries} -> {path, normalize_timeline_entries(entries)} end)
    |> Map.new()
  end

  defp normalize_timeline_output(result) when is_list(result) do
    Enum.map(result, &normalize_timeline_entries/1)
  end

  defp normalize_timeline_output(other), do: other

  defp normalize_timeline_entries(entries) when is_list(entries) do
    Enum.map(entries, fn
      %{} = entry -> normalize_timeline_entry(entry)
      list when is_list(list) -> normalize_timeline_entries(list)
      other -> other
    end)
  end

  defp normalize_timeline_entries(%{} = entry), do: normalize_timeline_entry(entry)
  defp normalize_timeline_entries(other), do: other

  defp normalize_timeline_entry(entry) when is_map(entry) do
    entry
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      key_string = to_string(key)

      normalized_value =
        case key_string do
          "at" -> normalize_datetime_value(value)
          _ -> normalize_timeline_value(value)
        end

      Map.put(acc, key_string, normalized_value)
    end)
  end

  defp normalize_timeline_value(value) when is_list(value) do
    Enum.map(value, &normalize_timeline_value/1)
  end

  defp normalize_timeline_value(value) when is_map(value) do
    normalize_timeline_entry(value)
  end

  defp normalize_timeline_value(value) do
    convert_numeric(value) || value
  end

  defp normalize_datetime_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp normalize_datetime_value(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp normalize_datetime_value(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> DateTime.to_iso8601(dt)
      _ -> value
    end
  end

  defp normalize_datetime_value(other), do: other

  defp normalize_category_output(result) when is_map(result), do: normalize_category_map(result)

  defp normalize_category_output(result) when is_list(result) do
    Enum.map(result, fn
      %{} = map -> normalize_category_map(map)
      other -> other
    end)
  end

  defp normalize_category_output(other), do: other

  defp normalize_category_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      normalized =
        cond do
          is_map(value) -> normalize_category_map(value)
          is_list(value) -> Enum.map(value, &normalize_category_value/1)
          true -> convert_numeric(value) || value
        end

      Map.put(acc, to_string(key), normalized)
    end)
  end

  defp normalize_category_value(value) when is_map(value), do: normalize_category_map(value)
  defp normalize_category_value(value), do: convert_numeric(value) || value

  defp truthy?(value) when value in [true, false], do: value
  defp truthy?("true"), do: true
  defp truthy?("false"), do: false
  defp truthy?(value) when is_binary(value) do
    normalized = String.trim(String.downcase(value))
    normalized in ["yes", "y", "1", "true"]
  end

  defp truthy?(value) when is_integer(value), do: value != 0
  defp truthy?(_), do: false

  if Mix.env() == :test do
    @doc false
    def __tabularize_for_test__(series, opts \\ []) do
      tabularize_series(series, opts)
    end

    @doc false
    def __subset_table_for_test__(table, paths) do
      subset_table(table, paths)
    end
  end
end
