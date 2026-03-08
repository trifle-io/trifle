defmodule Trifle.Chat.Tools do
  @moduledoc """
  Tool catalogue and execution layer exposed to OpenAI for ChatLive.
  """

  require Logger

  alias Trifle.Chat.DashboardSpec
  alias Trifle.Chat.InlineDashboard
  alias Trifle.Chat.Notifier
  alias Trifle.Exports.Series, as: SeriesExport
  alias Trifle.Metrics.Query, as: MetricsQuery
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
    aggregator_options = MetricsQuery.aggregator_names()

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
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "describe_dashboard_widgets",
          "description" =>
            "Return the supported inline dashboard widget types, their best use cases, required fields, defaults, and layout guidance.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{},
            "required" => []
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "build_metric_dashboard",
          "description" =>
            "Validate a GridStack dashboard payload, fetch series data for a Metrics Key, and return a persisted inline dashboard visualization block for chat rendering.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "metric_key" => %{
                "type" => "string",
                "description" => "Metrics Key (exact path string) to query."
              },
              "title" => %{
                "type" => "string",
                "description" => "Optional dashboard title."
              },
              "grid" => %{
                "type" => "array",
                "description" =>
                  "GridStack widgets array. Use `describe_dashboard_widgets` for supported widget fields.",
                "items" => %{"type" => "object"}
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
            "required" => ["metric_key", "grid"]
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
         table <- MetricsQuery.tabularize_series(result.series) do
      summary = MetricsQuery.summarise_series(result.series)
      available = MetricsQuery.available_paths(result.series)

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
          timeline: MetricsQuery.format_series_points(result.series),
          available_paths: available
        }
        |> maybe_put_table(table)

      {:ok, payload}
    else
      {:error, %{} = err} ->
        notify_tool_error(context, "fetch_metric_timeseries", err)
        {:error, err}

      {:error, reason} ->
        err = sanitized_tool_error(reason)
        notify_tool_error(context, "fetch_metric_timeseries", err)
        {:error, err}
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
         paths = MetricsQuery.normalize_paths(value_path),
         {:ok, resolved_path} <- MetricsQuery.ensure_single_path(paths),
         {:ok, resolved_path} <- MetricsQuery.ensure_no_wildcards(resolved_path),
         available <- MetricsQuery.available_paths(result.series),
         :ok <- MetricsQuery.ensure_paths_exist([resolved_path], available),
         {:ok, values} <-
           MetricsQuery.aggregate_series(result.series, aggregator_fun, resolved_path, slices) do
      if values == [] do
        {:error,
         %{
           status: "error",
           error: "No data available for path #{resolved_path} in the selected timeframe.",
           available_paths: available
         }}
      else
        table = MetricsQuery.tabularize_series(result.series, only_paths: [resolved_path])

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
        notify_tool_error(context, "aggregate_metric_series", err)
        {:error, err}

      {:error, reason} ->
        err = sanitized_tool_error(reason)
        notify_tool_error(context, "aggregate_metric_series", err)
        {:error, err}
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
        notify_tool_error(context, "list_available_metrics", err)
        {:error, err}

      {:error, reason} ->
        err = sanitized_tool_error(reason)
        notify_tool_error(context, "list_available_metrics", err)
        {:error, err}
    end
  end

  def execute("describe_dashboard_widgets", _arguments_json, _context) do
    {:ok,
     %{
       status: "ok",
       widget_spec: DashboardSpec.spec(),
       prompt_fragment: DashboardSpec.prompt_fragment()
     }}
  end

  def execute("build_metric_dashboard", arguments_json, context) do
    with {:ok, args} <- decode_args(arguments_json),
         {:ok, source} <- ensure_source(context),
         {:ok, metric_key} <- require_string(args, "metric_key", "Metrics Key required."),
         {:ok, grid} <- require_grid(args),
         {:ok, {from, to, timeframe_label}} <- resolve_timeframe(args, source),
         {:ok, granularity} <- resolve_granularity(args, source),
         :ok <-
           Notifier.notify(
             context,
             {:progress, :formatting_series,
              %{
                metric_key: metric_key,
                formatter: "dashboard"
              }}
           ),
         {:ok, export} <-
           SeriesExport.fetch(
             source,
             metric_key,
             from,
             to,
             granularity,
             progress_callback: nil
           ),
         {:ok, series_snapshot} <- encode_series_snapshot(export),
         {:ok, visualization} <-
           InlineDashboard.build_visualization(
             source_meta(source),
             metric_key,
             grid,
             series_snapshot,
             title: Map.get(args, "title"),
             timeframe: %{
               from: DateTime.to_iso8601(from),
               to: DateTime.to_iso8601(to),
               label: timeframe_label,
               granularity: granularity
             },
             default_timeframe: timeframe_label,
             default_granularity: granularity
           ) do
      {:ok,
       %{
         status: "ok",
         metric_key: metric_key,
         visualization: visualization
       }}
    else
      {:error, :no_data} ->
        err = %{
          status: "error",
          error: "No data available in the selected timeframe."
        }

        notify_tool_error(context, "build_metric_dashboard", err)
        {:error, err}

      {:error, %{} = err} ->
        notify_tool_error(context, "build_metric_dashboard", err)
        {:error, err}

      {:error, reason} ->
        err = sanitized_tool_error(reason)
        notify_tool_error(context, "build_metric_dashboard", err)
        {:error, err}
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

    Before attempting to aggregate or visualise a metric, first call `list_available_metrics`
    (or use prior responses) to inspect the precise paths available for the timeframe via its `paths`
    field. If a later metric tool narrows the usable paths, prefer that exact result instead of guessing.
    If a requested path is absent, state that explicitly and present the actual paths. `aggregate_metric_series`
    value_path inputs must be exact paths and must not contain wildcard characters such as `*`; use
    `list_available_metrics` and its returned `paths` to choose the concrete path. Only use wildcard-style
    paths inside dashboard widget configs passed to `build_metric_dashboard`.

    When the user asks for any visual output, use `build_metric_dashboard`. For a simple chart request,
    build a compact single-widget dashboard instead of inventing a separate chart payload. Use
    `describe_dashboard_widgets` if you need the exact widget contract. Only use supported widget types
    and only build dashboards for the active analytics source.

    #{DashboardSpec.prompt_fragment()}

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

  defp require_grid(args) do
    case Map.get(args, "grid") do
      grid when is_list(grid) and grid != [] ->
        {:ok, grid}

      [] ->
        {:error, %{status: "error", error: "grid must contain at least one widget."}}

      _ ->
        {:error, %{status: "error", error: "grid must be an array of widget objects."}}
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
    MetricsQuery.resolve_aggregator(nil)
  end

  defp resolve_aggregator(value) when is_atom(value),
    do: MetricsQuery.resolve_aggregator(value)

  defp resolve_aggregator(value) when is_binary(value) do
    MetricsQuery.resolve_aggregator(value)
  end

  defp resolve_aggregator(_other) do
    {:error,
     %{
       status: "error",
       error: "Aggregator must be a string."
     }}
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

  defp encode_series_snapshot(export) do
    export
    |> SeriesExport.to_json()
    |> Jason.decode()
    |> case do
      {:ok, %{} = snapshot} -> {:ok, snapshot}
      {:error, reason} -> {:error, %{status: "error", error: "Unable to encode series snapshot", details: inspect(reason)}}
    end
  end

  defp source_meta(source) do
    %{
      id: Source.id(source) |> to_string(),
      type: Source.type(source) |> Atom.to_string(),
      display_name: Source.display_name(source),
      time_zone: Source.time_zone(source)
    }
  end

  defp notify_tool_error(context, tool_name, reason) when is_binary(tool_name) do
    error_message = tool_error_message(reason)
    source_context = tool_error_source_context(context)

    Logger.warning("Chat tool #{tool_name} failed#{source_context}: #{error_message}")
    Logger.debug("Chat tool #{tool_name} failure details#{source_context}: #{inspect(reason)}")

    Notifier.notify(
      context,
      {:progress, :tool_error, %{tool: tool_name, reason: error_message}}
    )
  end

  defp tool_error_message(%{error: message}) when is_binary(message), do: message
  defp tool_error_message(%{"error" => message}) when is_binary(message), do: message
  defp tool_error_message(%{message: message}) when is_binary(message), do: message
  defp tool_error_message(%{"message" => message}) when is_binary(message), do: message
  defp tool_error_message(reason) when is_binary(reason) do
    reason
    |> String.trim()
    |> case do
      "" -> "unexpected tool failure"
      message -> message
    end
  end

  defp tool_error_message(_reason), do: "unexpected tool failure"

  defp sanitized_tool_error(reason) do
    %{
      status: "error",
      error: tool_error_message(reason)
    }
  end

  defp tool_error_source_context(%{source: %Source{} = source}) do
    " for #{Source.type(source)} #{Source.id(source)}"
  end

  defp tool_error_source_context(_context), do: ""

  if Mix.env() == :test do
    @doc false
    def __tabularize_for_test__(series, opts \\ []) do
      MetricsQuery.tabularize_series(series, opts)
    end

    @doc false
    def __subset_table_for_test__(table, paths) do
      MetricsQuery.subset_table(table, paths)
    end
  end
end
