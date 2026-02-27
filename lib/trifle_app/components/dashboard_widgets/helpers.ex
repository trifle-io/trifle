defmodule TrifleApp.Components.DashboardWidgets.Helpers do
  @moduledoc false

  alias TrifleApp.DesignSystem.ChartColors
  alias TrifleApp.Components.DashboardWidgets.SharedParse

  @text_widget_colors [
    %{id: "default", label: "Default (white)", background: "#ffffff", text: "#0f172a"},
    %{id: "slate", label: "Slate", background: "#0f172a", text: "#f8fafc"},
    %{id: "teal", label: "Teal", background: "#0f766e", text: "#ecfdf5"},
    %{id: "amber", label: "Amber", background: "#f59e0b", text: "#1f2937"},
    %{id: "emerald", label: "Emerald", background: "#10b981", text: "#064e3b"},
    %{id: "rose", label: "Rose", background: "#f43f5e", text: "#fff1f2"}
  ]

  @default_series_color_selector "default.*"
  @palette_rotate_selector_regex ~r/^([a-z0-9_-]+)\.\*$/
  @palette_fixed_selector_regex ~r/^([a-z0-9_-]+)\.(\d+)$/
  @custom_color_selector_regex ~r/^custom\.(#[0-9a-fA-F]{6})$/
  @distribution_path_aggregations ["none", "sum", "mean", "max", "min"]
  @heatmap_color_modes ["auto", "single", "palette", "diverging"]
  @default_heatmap_palette_id "default"
  @default_heatmap_negative_color "#0EA5E9"
  @default_heatmap_positive_color "#EF4444"
  @palette_ids ChartColors.palette_options() |> Enum.map(& &1.id)
  @allowed_text_widget_tags MapSet.new(
                              ~w[a b blockquote br code div em h1 h2 h3 h4 h5 h6 hr i li ol p pre s span strong table tbody td th thead tr u ul]
                            )
  @void_text_widget_tags MapSet.new(~w[br hr])
  @global_text_widget_attrs MapSet.new(~w[class title role])
  @text_widget_tag_attrs %{
    "a" => MapSet.new(~w[href target rel]),
    "th" => MapSet.new(~w[colspan rowspan scope]),
    "td" => MapSet.new(~w[colspan rowspan])
  }
  @safe_url_schemes ["http", "https", "mailto", "tel"]

  ## Text helpers

  def text_widget_colors, do: @text_widget_colors
  def text_widget_color_options, do: text_widget_colors()
  def default_text_widget_color, do: List.first(@text_widget_colors)

  def resolve_text_widget_color(color_id) do
    id =
      color_id
      |> to_string()
      |> String.downcase()

    Enum.find(@text_widget_colors, &(&1.id == id)) || default_text_widget_color()
  end

  def normalize_text_subtype(value) do
    value
    |> to_string()
    |> String.downcase()
    |> case do
      "html" -> "html"
      "header" -> "header"
      _ -> "header"
    end
  end

  def normalize_text_alignment(value) do
    value
    |> to_string()
    |> String.downcase()
    |> case do
      "left" -> "left"
      "right" -> "right"
      _ -> "center"
    end
  end

  def normalize_text_title_size(value) do
    value
    |> to_string()
    |> String.downcase()
    |> case do
      "small" -> "small"
      "s" -> "small"
      "medium" -> "medium"
      "m" -> "medium"
      "large" -> "large"
      "l" -> "large"
      _ -> "large"
    end
  end

  def normalize_text_color_id(value) do
    resolve_text_widget_color(value).id
  end

  def sanitize_text_widget_html(value) do
    value
    |> to_string()
    |> String.replace("\u0000", "")
    |> remove_dangerous_text_widget_blocks()
    |> String.replace(~r/<!--[\s\S]*?-->/, "")
    |> sanitize_text_widget_tags()
  end

  ## KPI helpers

  def normalize_kpi_subtype(value, item \\ %{}) do
    raw =
      value
      |> to_string()
      |> String.downcase()

    cond do
      raw in ["number", "split", "goal"] -> raw
      Map.get(item, "split") -> "split"
      true -> "number"
    end
  end

  ## Path helpers

  def timeseries_paths_for_form(nil), do: [""]

  def timeseries_paths_for_form(paths) when is_list(paths) do
    cleaned = Enum.map(paths, &to_string/1)

    case cleaned do
      [] -> [""]
      list -> list
    end
  end

  def timeseries_paths_for_form(path), do: timeseries_paths_for_form([path])

  def normalize_timeseries_paths_param(value) do
    value
    |> case do
      nil -> []
      list when is_list(list) -> list
      other -> [other]
    end
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def normalize_timeseries_paths_for_edit(paths) do
    cleaned =
      paths
      |> case do
        nil -> []
        list when is_list(list) -> list
        other -> [other]
      end
      |> Enum.map(&to_string/1)

    case cleaned do
      [] -> [""]
      list -> list
    end
  end

  def normalize_category_paths_param(value), do: normalize_timeseries_paths_param(value)
  def normalize_category_paths_for_edit(paths), do: normalize_timeseries_paths_for_edit(paths)

  def normalize_chart_path_inputs_param(value), do: normalize_timeseries_paths_param(value)
  def normalize_chart_path_inputs_for_edit(value), do: normalize_timeseries_paths_for_edit(value)

  defp remove_dangerous_text_widget_blocks(html) do
    html =
      Enum.reduce(dangerous_block_regexes(), html, fn regex, acc ->
        Regex.replace(regex, acc, "")
      end)

    Enum.reduce(dangerous_self_closing_regexes(), html, fn regex, acc ->
      Regex.replace(regex, acc, "")
    end)
  end

  defp dangerous_block_regexes do
    [
      ~r/<\s*script\b[^>]*>.*?<\s*\/\s*script\s*>/is,
      ~r/<\s*noscript\b[^>]*>.*?<\s*\/\s*noscript\s*>/is,
      ~r/<\s*style\b[^>]*>.*?<\s*\/\s*style\s*>/is,
      ~r/<\s*template\b[^>]*>.*?<\s*\/\s*template\s*>/is,
      ~r/<\s*iframe\b[^>]*>.*?<\s*\/\s*iframe\s*>/is,
      ~r/<\s*object\b[^>]*>.*?<\s*\/\s*object\s*>/is,
      ~r/<\s*embed\b[^>]*>.*?<\s*\/\s*embed\s*>/is,
      ~r/<\s*link\b[^>]*>.*?<\s*\/\s*link\s*>/is,
      ~r/<\s*meta\b[^>]*>.*?<\s*\/\s*meta\s*>/is,
      ~r/<\s*base\b[^>]*>.*?<\s*\/\s*base\s*>/is,
      ~r/<\s*form\b[^>]*>.*?<\s*\/\s*form\s*>/is,
      ~r/<\s*input\b[^>]*>.*?<\s*\/\s*input\s*>/is,
      ~r/<\s*button\b[^>]*>.*?<\s*\/\s*button\s*>/is,
      ~r/<\s*textarea\b[^>]*>.*?<\s*\/\s*textarea\s*>/is,
      ~r/<\s*select\b[^>]*>.*?<\s*\/\s*select\s*>/is,
      ~r/<\s*option\b[^>]*>.*?<\s*\/\s*option\s*>/is,
      ~r/<\s*svg\b[^>]*>.*?<\s*\/\s*svg\s*>/is,
      ~r/<\s*math\b[^>]*>.*?<\s*\/\s*math\s*>/is
    ]
  end

  defp dangerous_self_closing_regexes do
    [
      ~r/<\s*script\b[^>]*\/\s*>/is,
      ~r/<\s*noscript\b[^>]*\/\s*>/is,
      ~r/<\s*style\b[^>]*\/\s*>/is,
      ~r/<\s*template\b[^>]*\/\s*>/is,
      ~r/<\s*iframe\b[^>]*\/\s*>/is,
      ~r/<\s*object\b[^>]*\/\s*>/is,
      ~r/<\s*embed\b[^>]*\/\s*>/is,
      ~r/<\s*link\b[^>]*\/\s*>/is,
      ~r/<\s*meta\b[^>]*\/\s*>/is,
      ~r/<\s*base\b[^>]*\/\s*>/is,
      ~r/<\s*form\b[^>]*\/\s*>/is,
      ~r/<\s*input\b[^>]*\/\s*>/is,
      ~r/<\s*button\b[^>]*\/\s*>/is,
      ~r/<\s*textarea\b[^>]*\/\s*>/is,
      ~r/<\s*select\b[^>]*\/\s*>/is,
      ~r/<\s*option\b[^>]*\/\s*>/is,
      ~r/<\s*svg\b[^>]*\/\s*>/is,
      ~r/<\s*math\b[^>]*\/\s*>/is
    ]
  end

  defp sanitize_text_widget_tags(html) do
    Regex.replace(~r/<\s*(\/?)\s*([a-zA-Z0-9:-]+)([^>]*)>/, html, fn _full,
                                                                     closing,
                                                                     raw_tag,
                                                                     attrs ->
      tag =
        raw_tag
        |> to_string()
        |> String.downcase()

      cond do
        !MapSet.member?(@allowed_text_widget_tags, tag) ->
          ""

        closing == "/" ->
          if MapSet.member?(@void_text_widget_tags, tag), do: "", else: "</#{tag}>"

        true ->
          "<#{tag}#{sanitize_text_widget_attrs(tag, attrs)}>"
      end
    end)
  end

  defp sanitize_text_widget_attrs(tag, attrs_raw) do
    attrs =
      Regex.scan(
        ~r/([^\s"'<>\/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/,
        to_string(attrs_raw),
        capture: :all_but_first
      )

    attrs
    |> Enum.reduce(%{}, fn captures, acc ->
      [raw_name | raw_values] = captures

      name =
        raw_name
        |> to_string()
        |> String.downcase()

      value = first_non_empty(raw_values)

      cond do
        String.starts_with?(name, "on") ->
          acc

        name in ["style", "srcdoc"] ->
          acc

        String.contains?(name, ":") ->
          acc

        !allowed_text_widget_attr_for_tag?(tag, name) ->
          acc

        true ->
          case normalize_text_widget_attr_value(tag, name, value) do
            nil -> acc
            normalized -> Map.put(acc, name, normalized)
          end
      end
    end)
    |> maybe_enforce_text_widget_anchor_rel()
    |> Enum.sort_by(fn {name, _value} -> name end)
    |> Enum.map_join(fn {name, value} ->
      escaped_value = html_escape_to_string(value)
      " #{name}=\"#{escaped_value}\""
    end)
  end

  defp allowed_text_widget_attr_for_tag?(tag, name) do
    MapSet.member?(@global_text_widget_attrs, name) or
      MapSet.member?(Map.get(@text_widget_tag_attrs, tag, MapSet.new()), name)
  end

  defp normalize_text_widget_attr_value("a", "href", value) do
    sanitize_text_widget_href(value)
  end

  defp normalize_text_widget_attr_value("a", "target", value) do
    case value
         |> to_string()
         |> String.trim()
         |> String.downcase() do
      target when target in ["_blank", "_self", "_parent", "_top"] -> target
      _ -> nil
    end
  end

  defp normalize_text_widget_attr_value(_tag, _name, value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp sanitize_text_widget_href(value) do
    href =
      value
      |> to_string()
      |> String.trim()
      |> String.replace(~r/[\x00-\x1F\x7F\s]+/u, "")

    cond do
      href == "" ->
        nil

      String.starts_with?(href, "#") ->
        href

      String.starts_with?(href, "/") and !String.starts_with?(href, "//") ->
        href

      true ->
        case URI.parse(href) do
          %URI{scheme: nil} ->
            href

          %URI{scheme: scheme} ->
            if String.downcase(scheme || "") in @safe_url_schemes do
              href
            else
              nil
            end
        end
    end
  end

  defp maybe_enforce_text_widget_anchor_rel(attrs) when is_map(attrs) do
    case Map.get(attrs, "target") do
      "_blank" ->
        rel_tokens =
          attrs
          |> Map.get("rel", "")
          |> to_string()
          |> String.downcase()
          |> String.split(~r/\s+/, trim: true)
          |> MapSet.new()
          |> MapSet.union(MapSet.new(["noopener", "noreferrer", "nofollow"]))
          |> MapSet.to_list()
          |> Enum.sort()
          |> Enum.join(" ")

        Map.put(attrs, "rel", rel_tokens)

      _ ->
        attrs
    end
  end

  defp first_non_empty(values) do
    Enum.find(values, "", fn value ->
      !is_nil(value) and to_string(value) != ""
    end)
  end

  defp html_escape_to_string(value) do
    value
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  def category_paths_for_form(%{} = widget) do
    paths = normalize_category_paths_for_edit(Map.get(widget, "paths"))

    has_populated_path =
      paths
      |> Enum.map(&String.trim/1)
      |> Enum.any?(&(&1 != ""))

    if has_populated_path do
      paths
    else
      widget
      |> Map.get("path")
      |> normalize_category_paths_for_edit()
    end
  end

  def category_paths_for_form(paths), do: normalize_category_paths_for_edit(paths)

  ## Chart color selector helpers

  def default_series_color_selector, do: @default_series_color_selector

  def color_selector_options(current_selector \\ nil) do
    rotate_options =
      ChartColors.palette_options()
      |> Enum.map(fn palette ->
        %{
          value: "#{palette.id}.*",
          label: "#{palette.label} series"
        }
      end)

    fixed_options =
      ChartColors.palette_options()
      |> Enum.flat_map(fn palette ->
        palette.colors
        |> Enum.with_index()
        |> Enum.map(fn {color, index} ->
          %{
            value: "#{palette.id}.#{index}",
            label: "#{palette.label} ##{index}",
            color: color
          }
        end)
      end)

    custom_option =
      case parse_series_color_selector(current_selector) do
        %{type: :single_custom, color: color} ->
          [%{value: "custom.#{color}", label: "Custom #{color}", color: color}]

        _ ->
          []
      end

    %{
      rotate: rotate_options,
      fixed: fixed_options,
      custom: custom_option
    }
  end

  def path_inputs_for_form(widget, type) do
    explicit_inputs =
      widget
      |> Map.get("path_inputs")
      |> normalize_chart_path_inputs_for_edit()

    has_explicit_inputs? =
      explicit_inputs
      |> Enum.map(&String.trim/1)
      |> Enum.any?(&(&1 != ""))

    if has_explicit_inputs? do
      explicit_inputs
    else
      case normalize_chart_type(type) do
        "timeseries" ->
          timeseries_paths_for_form(Map.get(widget, "paths", Map.get(widget, "path")))

        "category" ->
          category_paths_for_form(widget)

        "table" ->
          table_paths_for_form(widget)

        "distribution" ->
          distribution_paths_for_form(widget)

        "heatmap" ->
          distribution_paths_for_form(widget)

        _ ->
          [""]
      end
    end
  end

  def chart_path_rows(widget, type) do
    chart_type = normalize_chart_type(type)
    path_inputs = path_inputs_for_form(widget, chart_type)
    expanded_paths = expanded_paths_for_rows(widget, chart_type, path_inputs)

    selectors =
      normalize_series_color_selectors_for_paths(
        path_inputs,
        [],
        Map.get(widget, "series_color_selectors", %{})
      )

    path_inputs
    |> Enum.with_index()
    |> Enum.map(fn {path_input, index} ->
      expanded_path = Enum.at(expanded_paths, index) || path_input
      normalized_path = String.trim(to_string(path_input || ""))
      selector = selector_for_path(selectors, normalized_path)
      parsed = parse_series_color_selector(selector)

      %{
        index: index,
        path_input: path_input,
        expanded_path: expanded_path,
        selector: selector,
        selector_type: selector_type(parsed),
        selector_palette_id: Map.get(parsed, :palette_id),
        selector_color: resolve_series_color(selector, 0),
        wildcard: wildcard_state(path_input, expanded_path)
      }
    end)
  end

  def normalize_series_color_selectors_map(value) when is_map(value) do
    value
    |> Enum.reduce(%{}, fn {raw_path, raw_selector}, acc ->
      path =
        raw_path
        |> to_string()
        |> String.trim()

      if path == "" do
        acc
      else
        selector = normalize_series_color_selector(raw_selector)
        Map.put(acc, path, selector)
      end
    end)
  end

  def normalize_series_color_selectors_map(_), do: %{}

  def normalize_series_color_selectors_for_paths(
        path_inputs,
        selectors_param,
        existing_selectors \\ %{}
      ) do
    normalized_paths = normalize_chart_path_inputs_for_edit(path_inputs)
    existing_map = normalize_series_color_selectors_map(existing_selectors)

    selector_values =
      selectors_param
      |> selector_values_for_form()
      |> Enum.map(&normalize_series_color_selector/1)

    selector_values_provided? = selector_values != []

    normalized_paths
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {raw_path, index}, acc ->
      path =
        raw_path
        |> to_string()
        |> String.trim()

      if path == "" do
        acc
      else
        selector =
          cond do
            selector_values_provided? ->
              selector_values
              |> Enum.at(index)
              |> case do
                nil -> Map.get(existing_map, path, @default_series_color_selector)
                value -> value
              end

            true ->
              Map.get(existing_map, path, @default_series_color_selector)
          end

        Map.put(acc, path, selector)
      end
    end)
  end

  def normalize_series_color_selector(selector) do
    normalized =
      selector
      |> to_string()
      |> String.trim()
      |> String.downcase()

    cond do
      normalized == "" ->
        @default_series_color_selector

      Regex.match?(@palette_rotate_selector_regex, normalized) ->
        normalized

      Regex.match?(@palette_fixed_selector_regex, normalized) ->
        normalized

      Regex.match?(@custom_color_selector_regex, normalized) ->
        [_, raw_color] = Regex.run(@custom_color_selector_regex, normalized)
        "custom.#{String.upcase(raw_color)}"

      true ->
        @default_series_color_selector
    end
  end

  def parse_series_color_selector(selector) do
    normalized = normalize_series_color_selector(selector)

    cond do
      Regex.match?(@palette_rotate_selector_regex, normalized) ->
        [_, palette_id] = Regex.run(@palette_rotate_selector_regex, normalized)
        %{type: :palette_rotate, palette_id: palette_id}

      Regex.match?(@palette_fixed_selector_regex, normalized) ->
        [_, palette_id, raw_index] = Regex.run(@palette_fixed_selector_regex, normalized)
        %{type: :single_palette, palette_id: palette_id, index: String.to_integer(raw_index)}

      Regex.match?(@custom_color_selector_regex, normalized) ->
        [_, color] = Regex.run(@custom_color_selector_regex, normalized)
        %{type: :single_custom, color: String.upcase(color)}

      true ->
        %{type: :palette_rotate, palette_id: "default"}
    end
  end

  def resolve_series_color(selector, series_index \\ 0) when is_integer(series_index) do
    safe_index = max(series_index, 0)

    case parse_series_color_selector(selector) do
      %{type: :palette_rotate, palette_id: palette_id} ->
        ChartColors.color_for(palette_id, safe_index)

      %{type: :single_palette, palette_id: palette_id, index: index} ->
        ChartColors.color_at(palette_id, index) || ChartColors.color_for(palette_id, 0)

      %{type: :single_custom, color: color} ->
        color
    end
  end

  def selector_for_path(selectors, path_input) when is_map(selectors) do
    path =
      path_input
      |> to_string()
      |> String.trim()

    selectors
    |> Map.get(path, @default_series_color_selector)
    |> normalize_series_color_selector()
  end

  def selector_for_path(_selectors, _path_input), do: @default_series_color_selector

  defp normalize_chart_type(type) do
    type
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> case do
      "timeseries" -> "timeseries"
      "category" -> "category"
      "table" -> "table"
      "distribution" -> "distribution"
      "heatmap" -> "heatmap"
      other -> other
    end
  end

  defp expanded_paths_for_rows(widget, chart_type, _path_inputs) do
    case chart_type do
      "timeseries" ->
        widget
        |> Map.get("paths", Map.get(widget, "path"))
        |> normalize_timeseries_paths_for_edit()

      "category" ->
        category_paths_for_form(widget)

      "table" ->
        table_paths_for_form(widget)

      "distribution" ->
        distribution_paths_for_form(widget)

      "heatmap" ->
        distribution_paths_for_form(widget)

      _ ->
        [""]
    end
  end

  defp selector_type(%{type: :palette_rotate}), do: "palette"
  defp selector_type(_), do: "single"

  defp wildcard_state(path_input, expanded_path) do
    typed_path = to_string(path_input || "") |> String.trim()
    normalized_expanded = to_string(expanded_path || "") |> String.trim()
    explicit_wildcard? = String.contains?(typed_path, "*")
    auto_wildcard? = !explicit_wildcard? and String.contains?(normalized_expanded, "*")

    cond do
      typed_path == "" -> :unknown
      explicit_wildcard? -> :explicit
      auto_wildcard? -> :auto
      true -> :single
    end
  end

  defp selector_values_for_form(value) do
    value
    |> case do
      nil -> []
      map when is_map(map) -> selector_values_from_map(map)
      list when is_list(list) -> list
      other -> [other]
    end
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
  end

  defp selector_values_from_map(map) do
    map
    |> Enum.sort_by(fn {raw_key, _value} ->
      raw_key
      |> to_string()
      |> String.trim()
      |> Integer.parse()
      |> case do
        {index, ""} -> {0, index}
        _ -> {1, to_string(raw_key)}
      end
    end)
    |> Enum.map(fn {_key, value} -> value end)
  end

  ## Table helpers

  def table_paths_for_form(widget), do: category_paths_for_form(widget)
  def normalize_table_paths_param(value), do: normalize_category_paths_param(value)
  def normalize_table_paths_for_edit(paths), do: normalize_category_paths_for_edit(paths)

  ## Distribution helpers

  @distribution_axes [:horizontal, :vertical]

  def distribution_paths_for_form(widget), do: category_paths_for_form(widget)
  def normalize_distribution_paths_param(value), do: normalize_category_paths_param(value)
  def normalize_distribution_paths_for_edit(paths), do: normalize_category_paths_for_edit(paths)

  def normalize_distribution_mode(value) do
    value
    |> to_string()
    |> String.downcase()
    |> case do
      "3d" -> "3d"
      _ -> "2d"
    end
  end

  def normalize_distribution_path_aggregation(value) do
    normalized =
      value
      |> to_string()
      |> String.trim()
      |> String.downcase()

    case normalized do
      v when v in ["avg", "average"] -> "mean"
      v when v in @distribution_path_aggregations -> v
      _ -> "none"
    end
  end

  def distribution_path_aggregation_for_form(widget) when is_map(widget) do
    widget
    |> Map.get("path_aggregation", Map.get(widget, :path_aggregation))
    |> normalize_distribution_path_aggregation()
  end

  def distribution_path_aggregation_for_form(_widget), do: "none"

  def normalize_heatmap_color_mode(value) do
    normalized =
      value
      |> to_string()
      |> String.trim()
      |> String.downcase()

    if normalized in @heatmap_color_modes, do: normalized, else: "auto"
  end

  def heatmap_color_mode_for_form(widget) when is_map(widget) do
    widget
    |> Map.get("color_mode", Map.get(widget, :color_mode))
    |> normalize_heatmap_color_mode()
  end

  def heatmap_color_mode_for_form(_widget), do: "auto"

  def heatmap_palette_options, do: ChartColors.palette_options()

  def heatmap_single_color_fallback(widget) when is_map(widget) do
    path_inputs = path_inputs_for_form(widget, "distribution")

    selectors =
      widget
      |> Map.get("series_color_selectors", Map.get(widget, :series_color_selectors, %{}))
      |> normalize_series_color_selectors_map()

    heatmap_single_color_from_paths(path_inputs, selectors)
  end

  def heatmap_single_color_fallback(_widget), do: ChartColors.primary()

  def heatmap_single_color_from_paths(path_inputs, selectors) do
    normalized_path =
      path_inputs
      |> normalize_chart_path_inputs_for_edit()
      |> Enum.map(&String.trim/1)
      |> Enum.find(&(&1 != ""))

    selector =
      case normalized_path do
        nil -> @default_series_color_selector
        path -> selector_for_path(selectors, path)
      end

    resolve_series_color(selector, 0)
  end

  def normalize_heatmap_color_config(config, fallback_single_color \\ nil) do
    config_map = normalize_string_key_map(config)

    fallback_color =
      fallback_single_color
      |> normalize_hex_color()
      |> Kernel.||(normalize_hex_color(ChartColors.primary()))
      |> Kernel.||("#14B8A6")

    %{
      "single_color" =>
        normalize_hex_color(Map.get(config_map, "single_color")) || fallback_color,
      "palette_id" => normalize_palette_id(Map.get(config_map, "palette_id")),
      "negative_color" =>
        normalize_hex_color(Map.get(config_map, "negative_color")) ||
          @default_heatmap_negative_color,
      "positive_color" =>
        normalize_hex_color(Map.get(config_map, "positive_color")) ||
          @default_heatmap_positive_color,
      "center_value" => normalize_designator_number(Map.get(config_map, "center_value"), 0.0),
      "symmetric" => normalize_boolean(Map.get(config_map, "symmetric"), true)
    }
  end

  def normalize_heatmap_color_config_params(
        params,
        existing_config \\ %{},
        fallback_single_color \\ nil
      ) do
    existing = normalize_heatmap_color_config(existing_config, fallback_single_color)

    config =
      %{
        "single_color" =>
          Map.get(params, "dist_heatmap_single_color", Map.get(existing, "single_color")),
        "palette_id" =>
          Map.get(params, "dist_heatmap_palette_id", Map.get(existing, "palette_id")),
        "negative_color" =>
          Map.get(params, "dist_heatmap_negative_color", Map.get(existing, "negative_color")),
        "positive_color" =>
          Map.get(params, "dist_heatmap_positive_color", Map.get(existing, "positive_color")),
        "center_value" =>
          Map.get(params, "dist_heatmap_center_value", Map.get(existing, "center_value")),
        "symmetric" => Map.get(params, "dist_heatmap_symmetric", Map.get(existing, "symmetric"))
      }

    normalize_heatmap_color_config(config, fallback_single_color)
  end

  def heatmap_color_config_for_form(widget) when is_map(widget) do
    widget
    |> Map.get("color_config", Map.get(widget, :color_config, %{}))
    |> normalize_heatmap_color_config(heatmap_single_color_fallback(widget))
  end

  def heatmap_color_config_for_form(_widget),
    do: normalize_heatmap_color_config(%{}, ChartColors.primary())

  def distribution_designators_for_form(widget) do
    designators = existing_distribution_designators(widget)

    %{
      horizontal: designator_form(Map.get(designators, "horizontal")),
      vertical: designator_form(Map.get(designators, "vertical"))
    }
  end

  def distribution_designator_for_form(widget) do
    distribution_designators_for_form(widget).horizontal
  end

  def normalize_distribution_designators(params, existing \\ %{}) do
    existing_designators = existing_distribution_designators(existing)

    axis_designators =
      @distribution_axes
      |> Enum.reduce(%{}, fn axis, acc ->
        axis_key = to_string(axis)
        prefix = distribution_designator_prefix(axis)

        normalized =
          normalize_distribution_designator(
            params,
            Map.get(existing_designators, axis_key),
            prefix: prefix
          )

        Map.put(acc, axis_key, normalized)
      end)

    Map.merge(existing_designators, axis_designators)
  end

  def normalize_distribution_designator(params, existing \\ %{}, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "dist_designator_")
    existing = normalize_designator_map(existing)

    type =
      params
      |> Map.get("#{prefix}type", Map.get(existing, "type") || "custom")
      |> normalize_distribution_designator_type()

    case type do
      "linear" ->
        %{
          "type" => "linear",
          "min" =>
            normalize_designator_number(Map.get(params, "#{prefix}min"), Map.get(existing, "min")),
          "max" =>
            normalize_designator_number(Map.get(params, "#{prefix}max"), Map.get(existing, "max")),
          "step" =>
            normalize_designator_number(
              Map.get(params, "#{prefix}step"),
              Map.get(existing, "step")
            )
        }

      "geometric" ->
        %{
          "type" => "geometric",
          "min" =>
            normalize_designator_number(Map.get(params, "#{prefix}min"), Map.get(existing, "min")),
          "max" =>
            normalize_designator_number(Map.get(params, "#{prefix}max"), Map.get(existing, "max"))
        }

      _ ->
        buckets =
          Map.get(params, "#{prefix}buckets", Map.get(existing, "buckets"))
          |> normalize_distribution_buckets()

        %{
          "type" => "custom",
          "buckets" =>
            case buckets do
              [] -> [0, 10, 20]
              list -> list
            end
        }
    end
  end

  def default_distribution_designator do
    %{"type" => "custom", "buckets" => [10, 20, 30]}
  end

  def default_distribution_designators do
    default = default_distribution_designator()
    %{"horizontal" => default, "vertical" => default}
  end

  def normalize_distribution_legend(value) do
    case value do
      v when v in [true, "true", 1, "1", "on"] -> true
      v when v in [false, "false", 0, "0", nil, ""] -> false
      other -> !!other
    end
  end

  defp existing_distribution_designators(nil), do: default_distribution_designators()

  defp existing_distribution_designators(%{} = source) do
    base_designators =
      cond do
        Map.has_key?(source, "designators") -> Map.get(source, "designators") || %{}
        Map.has_key?(source, :designators) -> Map.get(source, :designators) || %{}
        Map.has_key?(source, "horizontal") or Map.has_key?(source, :horizontal) -> source
        true -> %{}
      end
      |> normalize_designator_axes()

    horizontal =
      base_designators
      |> Map.get("horizontal")
      |> case do
        nil ->
          source
          |> Map.get("designator") || Map.get(source, :designator) ||
            default_distribution_designator()
            |> normalize_designator_map()

        value ->
          normalize_designator_map(value)
      end

    vertical =
      base_designators
      |> Map.get("vertical")
      |> case do
        nil -> horizontal
        value -> normalize_designator_map(value)
      end

    base_designators
    |> Map.put("horizontal", horizontal)
    |> Map.put("vertical", vertical)
  end

  defp distribution_designator_prefix(axis) do
    case axis do
      :vertical -> "dist_v_designator_"
      "vertical" -> "dist_v_designator_"
      _ -> "dist_designator_"
    end
  end

  defp designator_form(designator) do
    type = Map.get(designator, "type", "custom")
    buckets = Map.get(designator, "buckets", [])

    %{
      type: type,
      buckets_text: Enum.join(buckets, ", "),
      buckets: buckets,
      min: number_to_string(Map.get(designator, "min")),
      max: number_to_string(Map.get(designator, "max")),
      step: number_to_string(Map.get(designator, "step")),
      designator: designator
    }
  end

  defp normalize_distribution_buckets(value) when is_list(value) do
    buckets =
      value
      |> Enum.map(&normalize_distribution_bucket_value/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce({[], MapSet.new()}, fn bucket, {acc, seen} ->
        key = distribution_bucket_dedup_key(bucket)

        if MapSet.member?(seen, key) do
          {acc, seen}
        else
          {[bucket | acc], MapSet.put(seen, key)}
        end
      end)
      |> elem(0)
      |> Enum.reverse()

    if Enum.all?(buckets, &is_number/1) do
      Enum.sort(buckets)
    else
      buckets
    end
  end

  defp normalize_distribution_buckets(value) when is_binary(value) do
    value
    |> String.split(~r/[\n,]+/, trim: true)
    |> normalize_distribution_buckets()
  end

  defp normalize_distribution_buckets(_other), do: []

  defp normalize_distribution_bucket_value(value) when is_integer(value), do: value * 1.0
  defp normalize_distribution_bucket_value(value) when is_float(value), do: value

  defp normalize_distribution_bucket_value(value) when is_binary(value) do
    trimmed = String.trim(value)

    case trimmed do
      "" ->
        nil

      _ ->
        case SharedParse.parse_numeric_bucket(trimmed) do
          nil -> trimmed
          number -> number
        end
    end
  end

  defp normalize_distribution_bucket_value(_other), do: nil

  defp distribution_bucket_dedup_key(value) when is_number(value), do: {:number, value * 1.0}
  defp distribution_bucket_dedup_key(value) when is_binary(value), do: {:text, value}
  defp distribution_bucket_dedup_key(value), do: {:other, value}

  defp normalize_distribution_designator_type(value) do
    value
    |> to_string()
    |> String.downcase()
    |> case do
      "linear" -> "linear"
      "geometric" -> "geometric"
      _ -> "custom"
    end
  end

  defp normalize_designator_axes(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      case normalize_axis_key(k) do
        nil -> acc
        axis -> Map.put(acc, axis, normalize_designator_map(v))
      end
    end)
  end

  defp normalize_designator_axes(_other), do: %{}

  defp normalize_designator_map(value) when is_map(value) do
    value
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      case normalize_designator_key(k) do
        nil -> acc
        key -> Map.put(acc, key, v)
      end
    end)
    |> Map.put_new("type", "custom")
  end

  defp normalize_designator_map(_other), do: default_distribution_designator()

  defp normalize_axis_key(key) do
    key
    |> case do
      value when is_atom(value) -> Atom.to_string(value)
      value -> to_string(value)
    end
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      other -> other
    end
  end

  defp normalize_designator_key(key) do
    key
    |> case do
      value when is_atom(value) -> Atom.to_string(value)
      value -> to_string(value)
    end
    |> String.trim()
    |> case do
      "" -> nil
      other -> other
    end
  end

  defp number_to_string(nil), do: ""

  defp number_to_string(value) when is_integer(value),
    do: Integer.to_string(value)

  defp number_to_string(value) when is_float(value) do
    trimmed =
      :erlang.float_to_binary(value, decimals: 6)
      |> String.replace(~r/\.0+$/, "")
      |> String.replace(~r/(\.\d*?)0+$/, "\\1")

    if trimmed == "", do: "", else: trimmed
  end

  defp number_to_string(value) when is_binary(value), do: value
  defp number_to_string(_), do: ""

  defp parse_number(value) when is_integer(value), do: value * 1.0
  defp parse_number(value) when is_float(value), do: value * 1.0

  defp parse_number(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> parse_float(trimmed)
    end
  end

  defp parse_number(_), do: nil

  defp parse_float(string) do
    trimmed = String.trim(string || "")

    case Float.parse(trimmed) do
      {value, ""} ->
        value

      _ ->
        case Integer.parse(trimmed) do
          {int, ""} -> int * 1.0
          _ -> nil
        end
    end
  rescue
    ArgumentError ->
      nil
  end

  defp normalize_designator_number(value, fallback) do
    parsed =
      case value do
        nil -> nil
        "" -> nil
        other -> parse_number(other)
      end

    case parsed do
      nil -> fallback
      number -> number
    end
  end

  defp normalize_boolean(value, default) do
    case value do
      v when v in [true, "true", 1, "1", "on"] -> true
      v when v in [false, "false", 0, "0"] -> false
      v when v in [nil, ""] -> default
      _ -> default
    end
  end

  defp normalize_hex_color(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      <<?#, a::binary-size(6)>> = full ->
        if String.match?(a, ~r/^[0-9a-f]{6}$/), do: String.upcase(full), else: nil

      <<?#, a::binary-size(3)>> ->
        if String.match?(a, ~r/^[0-9a-f]{3}$/) do
          a
          |> String.graphemes()
          |> Enum.map_join(&(&1 <> &1))
          |> then(&String.upcase("##{&1}"))
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp normalize_hex_color(_), do: nil

  defp normalize_palette_id(value) do
    palette_id =
      value
      |> to_string()
      |> String.trim()
      |> String.downcase()

    cond do
      palette_id == "" ->
        @default_heatmap_palette_id

      palette_id in @palette_ids ->
        palette_id

      true ->
        @default_heatmap_palette_id
    end
  end

  defp normalize_string_key_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {k, v}, acc ->
      key =
        k
        |> case do
          atom when is_atom(atom) -> Atom.to_string(atom)
          other -> to_string(other)
        end
        |> String.trim()

      if key == "", do: acc, else: Map.put(acc, key, v)
    end)
  end

  defp normalize_string_key_map(_), do: %{}
end
