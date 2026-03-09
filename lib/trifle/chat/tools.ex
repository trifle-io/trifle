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
  alias Trifle.Stats.Nocturnal.Parser, as: GranularityParser
  alias Trifle.Stats.Source
  alias TrifleApp.TimeframeParsing

  @default_timeframe "24h"
  @default_granularity "1h"
  @system_key "__system__key__"
  @model_timeline_limit 30
  @chat_point_limit 1000
  @model_path_preview_limit 50
  @model_summary_preview_limit 25

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
              "Use this when you need timeframe-specific numbers after the metric structure and paths are already known. " <>
              "Granularity may be widened automatically to stay within the chat point limit.",
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
              "Use this for totals, averages, and extrema once you know the exact value path. " <>
              "Granularity may be widened automatically to stay within the chat point limit.",
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
              "Use this only when the user did not already name a specific Metrics Key. " <>
              "This tool uses a single coarse sample bucket internally.",
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
          "name" => "inspect_metric_schema",
          "description" =>
            "Inspect one Metrics Key using a single coarse sample bucket and return its tracked paths plus one representative sample point. " <>
              "Use this to understand structure safely before requesting detailed timeframe data.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "metric_key" => %{
                "type" => "string",
                "description" => "Metrics Key (exact path string) to inspect."
              }
            },
            "required" => ["metric_key"]
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
            "Validate a GridStack dashboard payload, fetch series data for a Metrics Key, and return a persisted inline dashboard visualization block for chat rendering. " <>
              "Granularity may be widened automatically to stay within the chat point limit.",
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
         {:ok, requested_granularity} <- resolve_granularity(args, source),
         {:ok, {granularity, adjusted_from}} <-
           adjust_chat_fetch_granularity(source, requested_granularity, from, to),
         :ok <-
           Notifier.notify(
             context,
             {:progress, :fetching_timeseries,
              %{
                metric_key: metric_key,
                timeframe: timeframe_label,
                from: DateTime.to_iso8601(from),
                to: DateTime.to_iso8601(to),
                granularity: granularity,
                adjusted_from: adjusted_from
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
        |> maybe_put_requested_granularity(adjusted_from)
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
         {:ok, requested_granularity} <- resolve_granularity(args, source),
         {:ok, {granularity, adjusted_from}} <-
           adjust_chat_fetch_granularity(source, requested_granularity, from, to),
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
                granularity: granularity,
                adjusted_from: adjusted_from
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
          |> maybe_put_requested_granularity(adjusted_from)
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
    with {:ok, _args} <- decode_args(arguments_json),
         {:ok, source} <- ensure_source(context),
         {:ok, granularity} <- resolve_schema_granularity(source),
         {:ok, {from, to, timeframe_label}} <- resolve_schema_timeframe(source, granularity),
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

  def execute("inspect_metric_schema", arguments_json, context) do
    with {:ok, args} <- decode_args(arguments_json),
         {:ok, source} <- ensure_source(context),
         {:ok, metric_key} <- require_string(args, "metric_key", "Metrics Key required."),
         {:ok, granularity} <- resolve_schema_granularity(source),
         {:ok, {from, to, timeframe_label}} <- resolve_schema_timeframe(source, granularity),
         :ok <-
           Notifier.notify(
             context,
             {:progress, :inspecting_metric_schema,
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
         {:ok, payload} <- build_schema_payload(metric_key, result.series, granularity, from, to) do
      {:ok, payload}
    else
      {:error, %{} = err} ->
        notify_tool_error(context, "inspect_metric_schema", err)
        {:error, err}

      {:error, reason} ->
        err = sanitized_tool_error(reason)
        notify_tool_error(context, "inspect_metric_schema", err)
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
         {:ok, requested_granularity} <- resolve_granularity(args, source),
         {:ok, {granularity, adjusted_from}} <-
           adjust_chat_fetch_granularity(source, requested_granularity, from, to),
         :ok <-
           Notifier.notify(
             context,
             {:progress, :formatting_series,
              %{
                metric_key: metric_key,
                formatter: "dashboard",
                timeframe: timeframe_label,
                granularity: granularity,
                adjusted_from: adjusted_from
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

    If the user already named a Metrics Key such as `sales`, skip `list_available_metrics` and call
    `inspect_metric_schema` directly. Only call `list_available_metrics` when the user did not give you
    a concrete Metrics Key and you need to discover which keys exist. After you know the right Metrics Key,
    call `inspect_metric_schema` to inspect that specific metric using a single coarse sample bucket.
    Both discovery tools already use the coarsest available granularity and only one sample bucket.
    Do not use `fetch_metric_timeseries` just to discover structure or tracked paths.
    All chat-side data fetches are hard-capped at 1000 points. Prefer sensible coarse granularities for long ranges.

    If a requested path is absent, state that explicitly and present the actual paths. `aggregate_metric_series`
    value_path inputs must be exact paths and must not contain wildcard characters such as `*`; use
    `inspect_metric_schema` and its returned `paths` to choose the concrete path. Only use wildcard-style
    paths inside dashboard widget configs passed to `build_metric_dashboard`.

    Use `fetch_metric_timeseries` only when you need timeframe-specific numbers after the path structure is
    already known. When the user asks for any visual output, use `build_metric_dashboard`. For a simple
    chart request, build a compact single-widget dashboard instead of inventing a separate chart payload.
    When the user asks for pie or donut charts, use category widgets only, and every such widget must set
    `chart_type` explicitly to `pie` or `donut`. Do not use distribution widgets for pies.
    Use only supported widget fields. `chart` and `style` are invalid; use `chart_type`.
    Use `describe_dashboard_widgets` if you need the exact widget contract. Only use supported widget
    types and only build dashboards for the active analytics source.

    #{DashboardSpec.prompt_fragment()}

    Output short, factual explanations. Always cite the Metrics Key and timeframe you used, and label any retrieved values as [path: ...].
    If a tool fails, report the error plainly and suggest a safe follow-up.
    """
  end

  @doc false
  @spec compact_tool_content_for_model(String.t() | nil, String.t() | nil) :: String.t() | nil
  def compact_tool_content_for_model(_tool_name, nil), do: nil

  def compact_tool_content_for_model(tool_name, content) when is_binary(content) do
    tool_name
    |> compact_tool_payload_for_model(content)
    |> Jason.encode!()
  end

  @doc false
  @spec compact_tool_payload_for_model(String.t() | nil, map() | String.t() | nil) :: map()
  def compact_tool_payload_for_model(tool_name, content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, %{} = payload} ->
        compact_tool_payload_for_model(tool_name, payload)

      _ ->
        %{
          status: "ok",
          tool: tool_name,
          note: "tool output omitted from model history"
        }
    end
  end

  def compact_tool_payload_for_model(tool_name, %{} = payload) do
    compact_tool_payload(tool_name, stringify_keys(payload))
  end

  def compact_tool_payload_for_model(tool_name, _payload) do
    %{
      status: "ok",
      tool: tool_name,
      note: "tool output omitted from model history"
    }
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
    case normalize_grid_argument(Map.get(args, "grid")) do
      grid when is_list(grid) and grid != [] ->
        {:ok, grid}

      [] ->
        {:error, %{status: "error", error: "grid must contain at least one widget."}}

      _ ->
        {:error, %{status: "error", error: "grid must be an array of widget objects."}}
    end
  end

  defp normalize_grid_argument(grid) when is_list(grid), do: grid

  defp normalize_grid_argument(%{} = grid) do
    cond do
      is_list(Map.get(grid, "grid")) ->
        Map.get(grid, "grid")

      is_list(Map.get(grid, :grid)) ->
        Map.get(grid, :grid)

      is_map(Map.get(grid, "payload")) ->
        normalize_grid_argument(Map.get(grid, "payload"))

      is_map(Map.get(grid, :payload)) ->
        normalize_grid_argument(Map.get(grid, :payload))

      is_list(Map.get(grid, "widgets")) ->
        Map.get(grid, "widgets")

      is_list(Map.get(grid, :widgets)) ->
        Map.get(grid, :widgets)

      likely_widget_map?(grid) ->
        [grid]

      true ->
        grid
    end
  end

  defp normalize_grid_argument(grid) when is_binary(grid) do
    case Jason.decode(grid) do
      {:ok, decoded} -> normalize_grid_argument(decoded)
      _ -> grid
    end
  end

  defp normalize_grid_argument(grid), do: grid

  defp likely_widget_map?(grid) when is_map(grid) do
    Enum.any?(["type", :type, "path", :path, "paths", :paths, "title", :title], &Map.has_key?(grid, &1))
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

  defp resolve_schema_granularity(source) do
    available =
      source
      |> Source.available_granularities()
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    case pick_coarsest_granularity(available) do
      nil ->
        {:ok, Source.default_granularity(source) || @default_granularity}

      granularity ->
        {:ok, granularity}
    end
  end

  defp resolve_schema_timeframe(source, granularity) do
    time_zone = Source.time_zone(source) || "UTC"
    now = DateTime.utc_now()

    {:ok, schema_sample_window(time_zone, granularity, now)}
  end

  defp schema_sample_window(time_zone, granularity, now) do
    shifted_now = DateTime.shift_zone!(now, time_zone)
    duration = granularity_duration_seconds(granularity)
    from = DateTime.add(shifted_now, -duration, :second)

    {from, shifted_now, "schema sample"}
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

  defp maybe_put_requested_granularity(payload, nil), do: payload

  defp maybe_put_requested_granularity(payload, requested_granularity) do
    Map.put(payload, :requested_granularity, requested_granularity)
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

  defp build_schema_payload(metric_key, series, granularity, from, to) do
    points = MetricsQuery.format_series_points(series)
    paths = MetricsQuery.available_paths(series)

    case List.last(points) do
      nil ->
        {:error,
         %{
           status: "error",
           error: "No recent data available for schema inspection."
         }}

      sample_point ->
        {:ok,
         %{
           status: "ok",
           metric_key: metric_key,
           timeframe: %{
             from: DateTime.to_iso8601(from),
             to: DateTime.to_iso8601(to),
             label: "schema_sample",
             granularity: granularity
           },
           path_count: length(paths),
           paths: paths,
           sample_point: sample_point
         }}
    end
  end

  defp compact_tool_payload(tool_name, %{"status" => "error"} = payload) do
    %{
      status: "error",
      error: Map.get(payload, "error") || "tool error",
      tool: tool_name
    }
  end

  defp compact_tool_payload("fetch_metric_timeseries", payload) do
    timeline = payload |> map_get("timeline") |> List.wrap()
    available_paths = payload |> map_get("available_paths") |> List.wrap()
    summary = payload |> map_get("summary") |> List.wrap()

    %{
      status: payload |> map_get("status") || "ok",
      metric_key: payload |> map_get("metric_key"),
      timeframe: compact_timeframe(payload |> map_get("timeframe")),
      requested_granularity: payload |> map_get("requested_granularity"),
      point_count: length(timeline),
      path_count: length(available_paths),
      available_paths_preview: Enum.take(available_paths, @model_path_preview_limit),
      available_paths_truncated: length(available_paths) > @model_path_preview_limit,
      summary_preview: Enum.take(summary, @model_summary_preview_limit),
      summary_truncated: length(summary) > @model_summary_preview_limit,
      timeline_preview: take_evenly(timeline, @model_timeline_limit),
      timeline_truncated: length(timeline) > @model_timeline_limit
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, [], %{}] end)
    |> Map.new()
  end

  defp compact_tool_payload("aggregate_metric_series", payload) do
    %{
      status: payload |> map_get("status") || "ok",
      metric_key: payload |> map_get("metric_key"),
      value_path: payload |> map_get("value_path"),
      aggregator: payload |> map_get("aggregator"),
      timeframe: compact_timeframe(payload |> map_get("timeframe")),
      requested_granularity: payload |> map_get("requested_granularity"),
      count: payload |> map_get("count"),
      value: payload |> map_get("value"),
      values: payload |> map_get("values"),
      matched_paths: payload |> map_get("matched_paths")
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, [], %{}] end)
    |> Map.new()
  end

  defp compact_tool_payload("list_available_metrics", payload) do
    paths =
      payload
      |> map_get("paths")
      |> List.wrap()
      |> Enum.map(fn
        %{"path" => path} -> path
        %{path: path} -> path
        other -> other
      end)

    %{
      status: payload |> map_get("status") || "ok",
      timeframe: compact_timeframe(payload |> map_get("timeframe")),
      total_paths: payload |> map_get("total_paths") || length(paths),
      paths: paths
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, [], %{}] end)
    |> Map.new()
  end

  defp compact_tool_payload("inspect_metric_schema", payload) do
    %{
      status: payload |> map_get("status") || "ok",
      metric_key: payload |> map_get("metric_key"),
      timeframe: compact_timeframe(payload |> map_get("timeframe")),
      path_count: payload |> map_get("path_count"),
      paths: payload |> map_get("paths"),
      sample_point: payload |> map_get("sample_point")
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, [], %{}] end)
    |> Map.new()
  end

  defp compact_tool_payload("describe_dashboard_widgets", payload) do
    %{
      status: payload |> map_get("status") || "ok",
      note: "dashboard widget spec already provided"
    }
  end

  defp compact_tool_payload("build_metric_dashboard", payload) do
    visualization = payload |> map_get("visualization") |> Kernel.||(%{})
    dashboard = visualization |> map_get("dashboard") |> Kernel.||(%{})

    widgets =
      dashboard
      |> map_get("payload")
      |> map_get("grid")
      |> List.wrap()
      |> Enum.map(&compact_widget_outline/1)

    %{
      status: payload |> map_get("status") || "ok",
      metric_key: payload |> map_get("metric_key") || visualization |> map_get("metric_key"),
      visualization: %{
        id: visualization |> map_get("id"),
        type: "dashboard",
        title: visualization |> map_get("title"),
        timeframe: compact_timeframe(visualization |> map_get("timeframe")),
        widget_count: length(widgets),
        widgets: widgets
      }
    }
  end

  defp compact_tool_payload("explain_available_sources", payload) do
    %{
      status: payload |> map_get("status") || "ok",
      active_source: payload |> map_get("active_source"),
      sources:
        payload
        |> map_get("sources")
        |> List.wrap()
        |> Enum.map(fn source ->
          %{
            id: map_get(source, "id"),
            type: map_get(source, "type"),
            display_name: map_get(source, "display_name")
          }
        end)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, [], %{}] end)
    |> Map.new()
  end

  defp compact_tool_payload(_tool_name, payload) do
    %{
      status: payload |> map_get("status") || "ok",
      note: "tool output compacted for model history"
    }
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

  defp compact_widget_outline(widget) when is_map(widget) do
    %{
      id: map_get(widget, "id"),
      type: map_get(widget, "type"),
      title: map_get(widget, "title"),
      path: map_get(widget, "path"),
      paths: map_get(widget, "paths"),
      x: map_get(widget, "x"),
      y: map_get(widget, "y"),
      w: map_get(widget, "w"),
      h: map_get(widget, "h")
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, [], %{}] end)
    |> Map.new()
  end

  defp compact_widget_outline(_widget), do: %{}

  defp compact_timeframe(nil), do: nil

  defp compact_timeframe(timeframe) when is_map(timeframe) do
    %{
      from: map_get(timeframe, "from"),
      to: map_get(timeframe, "to"),
      label: map_get(timeframe, "label"),
      granularity: map_get(timeframe, "granularity")
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", %{}] end)
    |> Map.new()
  end

  defp compact_timeframe(other), do: other

  defp adjust_chat_fetch_granularity(source, requested_granularity, from, to) do
    requested = to_string(requested_granularity)

    if estimated_point_count(from, to, requested) <= @chat_point_limit do
      {:ok, {requested, nil}}
    else
      available =
        source
        |> Source.available_granularities()
        |> normalize_granularity_list()

      adjusted =
        available
        |> Enum.filter(&(granularity_duration_seconds(&1) >= granularity_duration_seconds(requested)))
        |> Enum.sort_by(&granularity_duration_seconds/1)
        |> Enum.find(&(estimated_point_count(from, to, &1) <= @chat_point_limit))
        |> Kernel.||(
          pick_coarsest_granularity(available) ||
            requested
        )

      if estimated_point_count(from, to, adjusted) > @chat_point_limit do
        {:error,
         %{
           status: "error",
           error:
             "Requested timeframe exceeds the chat limit of #{@chat_point_limit} points even at the coarsest supported granularity.",
           point_limit: @chat_point_limit,
           requested_granularity: requested,
           suggested_granularity: adjusted
         }}
      else
        if adjusted == requested do
          {:ok, {requested, nil}}
        else
          {:ok, {adjusted, requested}}
        end
      end
    end
  end

  defp pick_coarsest_granularity([]), do: nil

  defp pick_coarsest_granularity(granularities) when is_list(granularities) do
    granularities
    |> normalize_granularity_list()
    |> Enum.max_by(&granularity_duration_seconds/1, fn -> nil end)
  end

  defp normalize_granularity_list(granularities) when is_list(granularities) do
    granularities
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_granularity_list(_), do: []

  defp granularity_duration_seconds(granularity) do
    parser = GranularityParser.new(to_string(granularity))

    if GranularityParser.valid?(parser) do
      unit_seconds =
        case parser.unit do
          :second -> 1
          :minute -> 60
          :hour -> 60 * 60
          :day -> 24 * 60 * 60
          :week -> 7 * 24 * 60 * 60
          :month -> 30 * 24 * 60 * 60
          :quarter -> 90 * 24 * 60 * 60
          :year -> 365 * 24 * 60 * 60
          _ -> 1
        end

      parser.offset * unit_seconds
    else
      0
    end
  rescue
    _ -> 0
  end

  defp estimated_point_count(%DateTime{} = from, %DateTime{} = to, granularity) do
    duration = max(granularity_duration_seconds(granularity), 1)
    span = max(DateTime.diff(to, from, :second), 0)

    max(div(span + duration - 1, duration), 1)
  end

  defp take_evenly(list, limit) when is_list(list) and is_integer(limit) and limit > 0 do
    count = length(list)

    cond do
      count <= limit ->
        list

      true ->
        last_index = count - 1

        0..(limit - 1)
        |> Enum.map(fn step ->
          round(step * last_index / max(limit - 1, 1))
        end)
        |> Enum.uniq()
        |> Enum.map(&Enum.at(list, &1))
    end
  end

  defp take_evenly(_list, _limit), do: []

  defp map_get(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp map_get(_map, _key), do: nil

  defp stringify_keys(value) when is_map(value) do
    value
    |> Enum.map(fn {key, inner} -> {to_string(key), stringify_keys(inner)} end)
    |> Map.new()
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value

  if Mix.env() == :test do
    @doc false
    def __tabularize_for_test__(series, opts \\ []) do
      MetricsQuery.tabularize_series(series, opts)
    end

    @doc false
    def __subset_table_for_test__(table, paths) do
      MetricsQuery.subset_table(table, paths)
    end

    @doc false
    def __pick_coarsest_granularity_for_test__(granularities) do
      pick_coarsest_granularity(granularities)
    end

    @doc false
    def __build_schema_payload_for_test__(metric_key, series, granularity, from, to) do
      build_schema_payload(metric_key, series, granularity, from, to)
    end

    @doc false
    def __resolve_schema_timeframe_for_test__(time_zone, granularity, now) do
      schema_sample_window(time_zone, granularity, now)
    end

    @doc false
    def __adjust_chat_fetch_granularity_for_test__(source, granularity, from, to) do
      adjust_chat_fetch_granularity(source, granularity, from, to)
    end

    @doc false
    def __require_grid_for_test__(args) do
      require_grid(args)
    end

    @doc false
    def __chat_point_limit_for_test__ do
      @chat_point_limit
    end
  end
end
