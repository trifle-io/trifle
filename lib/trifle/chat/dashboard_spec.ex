defmodule Trifle.Chat.DashboardSpec do
  @moduledoc """
  Source-of-truth widget contract for AI-generated inline dashboards.
  """

  @version 1

  @widget_specs [
    %{
      type: "kpi",
      best_for: "single headline numbers, goals, and compact status cards",
      required_one_of: [["path"]],
      defaults: %{w: 3, h: 2, function: "mean", size: "m", subtype: "number"},
      supported_fields: [
        %{name: "title", type: "string", required: false, description: "Widget title."},
        %{name: "path", type: "string", required: true, description: "Metric path to aggregate."},
        %{name: "function", type: "string", required: false, description: "Aggregator: mean, sum, min, or max.", default: "mean"},
        %{name: "subtype", type: "string", required: false, description: "number, split, or goal.", default: "number"},
        %{name: "size", type: "string", required: false, description: "s, m, or l.", default: "m"},
        %{name: "timeseries", type: "boolean", required: false, description: "Adds a sparkline."},
        %{name: "diff", type: "boolean", required: false, description: "For split KPIs, show change vs previous slice."},
        %{name: "goal_target", type: "number", required: false, description: "Goal target for goal KPIs."},
        %{name: "goal_progress", type: "boolean", required: false, description: "Render progress bar for goal KPIs."},
        %{name: "goal_invert", type: "boolean", required: false, description: "Invert goal semantics for lower-is-better metrics."}
      ]
    },
    %{
      type: "timeseries",
      best_for: "trends over time, multi-series comparisons, and stacked timelines",
      required_one_of: [["path", "paths"]],
      defaults: %{w: 12, h: 4, chart_type: "line", legend: false},
      supported_fields: [
        %{name: "title", type: "string", required: false, description: "Widget title."},
        %{name: "path", type: "string", required: false, description: "Single metric path."},
        %{name: "paths", type: "array<string>", required: false, description: "One or more metric paths."},
        %{name: "chart_type", type: "string", required: false, description: "line, area, dots, or bar.", default: "line"},
        %{name: "stacked", type: "boolean", required: false, description: "Stack multiple series."},
        %{name: "normalized", type: "boolean", required: false, description: "Convert stacked values into percentages."},
        %{name: "legend", type: "boolean", required: false, description: "Show legend.", default: false},
        %{name: "y_label", type: "string", required: false, description: "Optional y-axis label."}
      ]
    },
    %{
      type: "category",
      best_for: "breakdowns by category, composition, and ranking slices",
      required_one_of: [["path", "paths"]],
      defaults: %{w: 6, h: 4, chart_type: "bar"},
      examples: [
        %{type: "category", title: "Products share", paths: ["products.*"], chart_type: "pie", w: 6, h: 4},
        %{type: "category", title: "Products share", paths: ["products.*"], chart_type: "donut", w: 6, h: 4}
      ],
      supported_fields: [
        %{name: "title", type: "string", required: false, description: "Widget title."},
        %{name: "path", type: "string", required: false, description: "Single categorical path."},
        %{name: "paths", type: "array<string>", required: false, description: "One or more categorical paths."},
        %{name: "chart_type", type: "string", required: false, description: "bar, pie, or donut.", default: "bar"}
      ]
    },
    %{
      type: "table",
      best_for: "raw values, compact inspection, and multi-path comparison tables",
      required_one_of: [["path", "paths"]],
      defaults: %{w: 6, h: 4},
      supported_fields: [
        %{name: "title", type: "string", required: false, description: "Widget title."},
        %{name: "path", type: "string", required: false, description: "Single metric path."},
        %{name: "paths", type: "array<string>", required: false, description: "One or more metric paths."}
      ]
    },
    %{
      type: "text",
      best_for: "section headers, explanations, and inline notes",
      required_one_of: [],
      defaults: %{w: 12, h: 1, subtype: "header", alignment: "center", title_size: "large"},
      supported_fields: [
        %{name: "title", type: "string", required: false, description: "Main headline for header text widgets."},
        %{name: "subtitle", type: "string", required: false, description: "Supporting copy for header text widgets."},
        %{name: "payload", type: "string", required: false, description: "HTML payload for html subtype."},
        %{name: "subtype", type: "string", required: false, description: "header or html.", default: "header"},
        %{name: "alignment", type: "string", required: false, description: "left, center, or right.", default: "center"},
        %{name: "title_size", type: "string", required: false, description: "small, medium, or large.", default: "large"},
        %{name: "color", type: "string", required: false, description: "Named text-widget color preset."}
      ]
    },
    %{
      type: "list",
      best_for: "top items, ranked keys, and compact wildcard breakdowns",
      required_one_of: [["path"]],
      defaults: %{w: 4, h: 4, limit: 8, sort: "desc"},
      supported_fields: [
        %{name: "title", type: "string", required: false, description: "Widget title."},
        %{name: "path", type: "string", required: true, description: "Wildcard-friendly path, for example channel.*."},
        %{name: "limit", type: "integer", required: false, description: "Maximum rows to show.", default: 8},
        %{name: "sort", type: "string", required: false, description: "asc or desc.", default: "desc"},
        %{name: "empty_message", type: "string", required: false, description: "Fallback copy when no rows exist."}
      ]
    },
    %{
      type: "distribution",
      best_for: "bucketed distributions and histograms across one or more paths",
      required_one_of: [["path", "paths"]],
      defaults: %{w: 6, h: 4, chart_type: "bar", mode: "2d", legend: true},
      supported_fields: [
        %{name: "title", type: "string", required: false, description: "Widget title."},
        %{name: "path", type: "string", required: false, description: "Single value path."},
        %{name: "paths", type: "array<string>", required: false, description: "One or more value paths."},
        %{name: "mode", type: "string", required: false, description: "2d or 3d.", default: "2d"},
        %{name: "chart_type", type: "string", required: false, description: "bar for distribution widgets.", default: "bar"},
        %{name: "path_aggregation", type: "string", required: false, description: "sum, mean, min, or max."},
        %{name: "legend", type: "boolean", required: false, description: "Show legend.", default: true},
        %{name: "designators", type: "object", required: false, description: "Bucket definitions, usually horizontal linear buckets."}
      ]
    },
    %{
      type: "heatmap",
      best_for: "density heatmaps and multi-axis bucket visualisations",
      required_one_of: [["path", "paths"]],
      defaults: %{w: 6, h: 4, chart_type: "heatmap", mode: "3d", legend: true},
      supported_fields: [
        %{name: "title", type: "string", required: false, description: "Widget title."},
        %{name: "path", type: "string", required: false, description: "Single value path."},
        %{name: "paths", type: "array<string>", required: false, description: "One or more value paths."},
        %{name: "mode", type: "string", required: false, description: "3d for heatmaps.", default: "3d"},
        %{name: "chart_type", type: "string", required: false, description: "heatmap.", default: "heatmap"},
        %{name: "path_aggregation", type: "string", required: false, description: "sum, mean, min, or max."},
        %{name: "legend", type: "boolean", required: false, description: "Show legend.", default: true},
        %{name: "designators", type: "object", required: false, description: "Bucket definitions."},
        %{name: "color_mode", type: "string", required: false, description: "auto or custom.", default: "auto"},
        %{name: "color_config", type: "object", required: false, description: "Heatmap color settings."}
      ]
    }
  ]

  @type widget_type :: String.t()

  @spec version() :: pos_integer()
  def version, do: @version

  @spec supported_types() :: [widget_type()]
  def supported_types do
    Enum.map(@widget_specs, & &1.type)
  end

  @spec supported_type?(term()) :: boolean()
  def supported_type?(type) do
    type
    |> normalize_type()
    |> then(&(&1 in supported_types()))
  end

  @spec widget_spec(term()) :: map() | nil
  def widget_spec(type) do
    normalized = normalize_type(type)
    Enum.find(@widget_specs, &(&1.type == normalized))
  end

  @spec grid_spec() :: map()
  def grid_spec do
    %{
      version: @version,
      columns: 12,
      auto_layout: true,
      defaults: %{x: 0, y: 0, w: 3, h: 2},
      notes: [
        "Use a 12-column GridStack layout.",
        "Every widget should include w and h; x and y are optional because the server can auto-place widgets.",
        "Prefer compact dashboards with 2-5 widgets unless the user explicitly asks for more."
      ]
    }
  end

  @spec spec() :: map()
  def spec do
    %{
      version: @version,
      grid: stringify_keys(grid_spec()),
      widgets: Enum.map(@widget_specs, &stringify_keys/1)
    }
  end

  @spec default_layout(term()) :: %{w: pos_integer(), h: pos_integer()}
  def default_layout(type) do
    spec = widget_spec(type) || %{}
    defaults = Map.get(spec, :defaults, %{})

    %{
      w: Map.get(defaults, :w, 3),
      h: Map.get(defaults, :h, 2)
    }
  end

  @spec required_one_of(term()) :: [[String.t()]]
  def required_one_of(type) do
    type
    |> widget_spec()
    |> case do
      %{required_one_of: groups} when is_list(groups) -> groups
      _ -> []
    end
  end

  @spec prompt_fragment() :: String.t()
  def prompt_fragment do
    """
    Inline dashboards use the existing Trifle dashboard `payload.grid` format and a 12-column GridStack layout.
    Supported widget types: #{Enum.join(supported_types(), ", ")}.

    Practical rules:
    - Use `describe_dashboard_widgets` whenever you need the exact widget contract or examples.
    - Use `build_metric_dashboard` to validate and persist an inline dashboard visualization.
    - Pass `grid` as an array of widget objects. Do not wrap it inside another `grid`, `widgets`, or `payload` object unless reusing an existing dashboard payload.
    - Most widgets need `path` or `paths`; only `text` can omit metric paths.
    - Use only documented field names. `chart` and `style` are invalid widget fields; use `chart_type`.
    - Category widgets default to `bar`. If you want a pie or donut, use `type: "category"` and set `chart_type` to `pie` or `donut` explicitly.
    - Distribution and heatmap widgets are for histograms/buckets, not pie or donut charts.
    - Example category pie widget: `{"type":"category","title":"Products share","paths":["products.*"],"chart_type":"pie","w":6,"h":4}`.
    - Example timeseries bar widget: `{"type":"timeseries","title":"Revenue","paths":["revenue"],"chart_type":"bar","w":12,"h":4}`.
    - Prefer clear layouts: KPI cards in 3x2 blocks, charts in 6x4 or 12x4 blocks, text headers in 12x1.
    - Keep widget titles short and factual.
    """
    |> String.trim()
  end

  defp normalize_type(type) when is_atom(type), do: type |> Atom.to_string() |> normalize_type()

  defp normalize_type(type) when is_binary(type) do
    type
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_type(_), do: ""

  defp stringify_keys(value) when is_map(value) do
    value
    |> Enum.map(fn {key, inner} -> {to_string(key), stringify_keys(inner)} end)
    |> Map.new()
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
