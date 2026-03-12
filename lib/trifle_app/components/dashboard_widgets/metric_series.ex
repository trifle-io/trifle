defmodule TrifleApp.Components.DashboardWidgets.MetricSeries do
  @moduledoc false

  alias Trifle.Stats.Tabler
  alias Trifle.Stats.Transponder.ExpressionEngine
  alias TrifleApp.Components.DashboardWidgets.Helpers

  @metric_widget_types ~w[kpi timeseries category table list distribution heatmap]

  def metric_widget?(type_or_widget) do
    type_or_widget
    |> widget_type()
    |> then(&(&1 in @metric_widget_types))
  end

  def normalize_widget(widget) when is_map(widget) do
    if metric_widget?(widget) do
      widget
      |> Map.put(
        "series",
        normalize_series_rows(current_series_rows(widget), ensure_default: false)
      )
      |> prune_legacy_metric_fields()
    else
      widget
    end
  end

  def normalize_widget(other), do: other

  def normalize_widget_for_form(widget) when is_map(widget) do
    if metric_widget?(widget) do
      Map.put(
        widget,
        "series",
        normalize_series_rows(current_series_rows(widget),
          preserve_empty: true
        )
      )
    else
      widget
    end
  end

  def normalize_widget_for_form(other), do: other

  def normalize_series_rows(rows, opts \\ [])

  def normalize_series_rows(rows, opts) when is_list(rows) do
    preserve_empty? = Keyword.get(opts, :preserve_empty, false)
    ensure_default? = Keyword.get(opts, :ensure_default, true)

    rows
    |> Enum.map(&normalize_row/1)
    |> maybe_drop_empty_rows(preserve_empty?)
    |> maybe_ensure_default_row(ensure_default?)
  end

  def normalize_series_rows(rows, opts) when is_map(rows) do
    rows
    |> Enum.sort_by(fn {key, _value} ->
      key
      |> to_string()
      |> Integer.parse()
      |> case do
        {index, ""} -> {0, index}
        _ -> {1, to_string(key)}
      end
    end)
    |> Enum.map(fn {_key, value} -> value end)
    |> normalize_series_rows(opts)
  end

  def normalize_series_rows(_rows, opts),
    do: maybe_ensure_default_row([], Keyword.get(opts, :ensure_default, true))

  def normalize_event_rows(rows) when is_list(rows),
    do: normalize_series_rows(rows, preserve_empty: true)

  def normalize_event_rows(_), do: ensure_default_row([])

  def normalize_series_rows_params(params, opts \\ [])

  def normalize_series_rows_params(params, opts) when is_map(params) do
    kinds = field_values(params, "widget_series_kind")
    paths = field_values(params, "widget_series_path")
    expressions = field_values(params, "widget_series_expression")
    labels = field_values(params, "widget_series_label")
    visibility = field_values(params, "widget_series_visible")
    color_selectors = field_values(params, "widget_series_color_selector")

    max_len =
      [
        length(kinds),
        length(paths),
        length(expressions),
        length(labels),
        length(visibility),
        length(color_selectors)
      ]
      |> Enum.max(fn -> 0 end)

    rows =
      if max_len == 0 do
        []
      else
        Enum.map(0..(max_len - 1), fn index ->
          %{
            "kind" => Enum.at(kinds, index),
            "path" => Enum.at(paths, index),
            "expression" => Enum.at(expressions, index),
            "label" => Enum.at(labels, index),
            "visible" => Enum.at(visibility, index),
            "color_selector" => Enum.at(color_selectors, index)
          }
        end)
      end

    normalize_series_rows(rows, opts)
  end

  def normalize_series_rows_params(_params, opts),
    do: maybe_ensure_default_row([], Keyword.get(opts, :ensure_default, true))

  def rows_for_form(widget, path_options \\ [])

  def rows_for_form(widget, path_options) when is_map(widget) do
    option_values = normalize_option_values(path_options)

    widget
    |> normalize_widget_for_form()
    |> Map.get("series", [])
    |> normalize_series_rows(preserve_empty: true)
    |> Enum.with_index()
    |> Enum.map(fn {row, index} ->
      path = Map.get(row, "path", "")

      expanded_path =
        case row_kind(row) do
          "path" -> expand_path(path, option_values)
          _ -> ""
        end

      selector = Map.get(row, "color_selector", Helpers.default_series_color_selector())
      parsed_selector = Helpers.parse_series_color_selector(selector)
      row_letter = row_letter(index)

      row
      |> Map.put("index", index)
      |> Map.put("row_letter", row_letter)
      |> Map.put("expanded_path", expanded_path)
      |> Map.put("wildcard", wildcard_state(path, expanded_path))
      |> Map.put("selector", selector)
      |> Map.put("selector_type", selector_type(parsed_selector))
      |> Map.put("selector_palette_id", Map.get(parsed_selector, :palette_id))
      |> Map.put("selector_color", Helpers.resolve_series_color(selector, 0))
    end)
  end

  def rows_for_form(_widget, _path_options), do: ensure_default_row([])

  def row_kind(row), do: Map.get(row, "kind", "path")
  def path_row?(row), do: row_kind(row) == "path"
  def expression_row?(row), do: row_kind(row) == "expression"

  def visible?(row) do
    row
    |> Map.get("visible", true)
    |> normalize_boolean(true)
  end

  def row_path(row), do: row |> Map.get("path", "") |> to_string() |> String.trim()
  def row_expression(row), do: row |> Map.get("expression", "") |> to_string() |> String.trim()
  def row_label(row), do: row |> Map.get("label", "") |> to_string() |> String.trim()

  def row_color_selector(row),
    do: Map.get(row, "color_selector", Helpers.default_series_color_selector())

  def row_letter(index) when is_integer(index) and index >= 0 do
    ExpressionEngine.allowed_vars(index + 1)
    |> List.last()
    |> Kernel.||("a")
  end

  def row_letter(_), do: "a"

  def expand_path(path, options) do
    trimmed = path |> to_string() |> String.trim()

    cond do
      trimmed == "" -> ""
      String.contains?(trimmed, "*") -> trimmed
      Enum.any?(options, &String.starts_with?(&1, trimmed <> ".")) -> trimmed <> ".*"
      true -> trimmed
    end
  end

  def available_paths(%Trifle.Stats.Series{series: series_map}) when is_map(series_map) do
    table = Tabler.tabulize(series_map)

    table
    |> Map.get(:paths, [])
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  rescue
    _ -> []
  end

  def available_paths(_), do: []

  def prune_legacy_metric_fields(widget) when is_map(widget) do
    widget
    |> Map.delete("path")
    |> Map.delete(:path)
    |> Map.delete("paths")
    |> Map.delete(:paths)
    |> Map.delete("path_inputs")
    |> Map.delete(:path_inputs)
    |> Map.delete("series_color_selectors")
    |> Map.delete(:series_color_selectors)
  end

  def prune_legacy_metric_fields(other), do: other

  defp widget_type(widget) when is_map(widget) do
    (Map.get(widget, "type") ||
       Map.get(widget, :type) ||
       Map.get(widget, "widget_type") ||
       Map.get(widget, :widget_type) ||
       "")
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp widget_type(type) when is_atom(type), do: type |> Atom.to_string() |> widget_type()
  defp widget_type(type) when is_binary(type), do: type |> String.trim() |> String.downcase()
  defp widget_type(_), do: ""

  defp current_series_rows(widget) do
    Map.get(widget, :series) || Map.get(widget, "series") || legacy_rows(widget)
  end

  defp legacy_rows(widget) do
    case widget_type(widget) do
      "kpi" ->
        single_row_legacy(widget, Map.get(widget, "path") || Map.get(widget, :path))

      "list" ->
        single_row_legacy(widget, Map.get(widget, "path") || Map.get(widget, :path))

      type when type in ["timeseries", "category", "table", "distribution", "heatmap"] ->
        multi_row_legacy(widget)

      _ ->
        []
    end
  end

  defp single_row_legacy(widget, nil) do
    if legacy_selectors(widget) == %{}, do: [], else: [default_row()]
  end

  defp single_row_legacy(widget, path) do
    trimmed_path = path |> to_string() |> String.trim()

    if trimmed_path == "" do
      []
    else
      [
        %{
          "kind" => "path",
          "path" => trimmed_path,
          "expression" => "",
          "label" => "",
          "visible" => true,
          "color_selector" => selector_for_legacy_path(widget, trimmed_path)
        }
      ]
    end
  end

  defp multi_row_legacy(widget) do
    typed_paths =
      widget
      |> Map.get("path_inputs", Map.get(widget, :path_inputs))
      |> case do
        nil ->
          widget
          |> Map.get("paths", Map.get(widget, :paths))
          |> case do
            list when is_list(list) ->
              list

            nil ->
              case Map.get(widget, "path", Map.get(widget, :path)) do
                nil -> []
                other -> [other]
              end

            other ->
              [other]
          end

        value ->
          case value do
            list when is_list(list) -> list
            nil -> []
            other -> [other]
          end
      end
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    typed_paths
    |> Enum.map(fn path ->
      %{
        "kind" => "path",
        "path" => path,
        "expression" => "",
        "label" => "",
        "visible" => true,
        "color_selector" => selector_for_legacy_path(widget, path)
      }
    end)
  end

  defp selector_for_legacy_path(widget, path) do
    widget
    |> legacy_selectors()
    |> Helpers.selector_for_path(path)
  end

  defp legacy_selectors(widget) do
    widget
    |> Map.get("series_color_selectors", Map.get(widget, :series_color_selectors, %{}))
    |> Helpers.normalize_series_color_selectors_map()
  end

  defp normalize_row(row) when is_map(row) do
    normalized =
      %{
        "kind" =>
          row
          |> Map.get("kind", Map.get(row, :kind, "path"))
          |> to_string()
          |> String.trim()
          |> String.downcase()
          |> case do
            "expression" -> "expression"
            _ -> "path"
          end,
        "path" => row |> Map.get("path", Map.get(row, :path, "")) |> to_string() |> String.trim(),
        "expression" =>
          row
          |> Map.get("expression", Map.get(row, :expression, ""))
          |> to_string()
          |> String.trim(),
        "label" =>
          row
          |> Map.get("label", Map.get(row, :label, ""))
          |> to_string()
          |> String.trim(),
        "visible" =>
          normalize_boolean(Map.get(row, "visible", Map.get(row, :visible, true)), true),
        "color_selector" =>
          row
          |> Map.get(
            "color_selector",
            Map.get(row, :color_selector, Helpers.default_series_color_selector())
          )
          |> Helpers.normalize_series_color_selector()
      }

    case normalized["kind"] do
      "path" -> Map.put(normalized, "expression", "")
      _ -> Map.put(normalized, "path", "")
    end
  end

  defp normalize_row(_), do: default_row()

  defp default_row do
    %{
      "kind" => "path",
      "path" => "",
      "expression" => "",
      "label" => "",
      "visible" => true,
      "color_selector" => Helpers.default_series_color_selector()
    }
  end

  defp ensure_default_row([]), do: [default_row()]
  defp ensure_default_row(rows), do: rows
  defp maybe_ensure_default_row(rows, true), do: ensure_default_row(rows)
  defp maybe_ensure_default_row(rows, false), do: rows

  defp maybe_drop_empty_rows(rows, true), do: rows
  defp maybe_drop_empty_rows(rows, false), do: Enum.reject(rows, &drop_empty_row?/1)

  defp drop_empty_row?(row) do
    case row_kind(row) do
      "expression" -> row_expression(row) == "" and row_label(row) == ""
      _ -> row_path(row) == "" and row_label(row) == ""
    end
  end

  defp wildcard_state(path_input, expanded_path) do
    typed_path = path_input |> to_string() |> String.trim()
    normalized_expanded = expanded_path |> to_string() |> String.trim()
    explicit_wildcard? = String.contains?(typed_path, "*")
    auto_wildcard? = !explicit_wildcard? and String.contains?(normalized_expanded, "*")

    cond do
      typed_path == "" -> :unknown
      explicit_wildcard? -> :explicit
      auto_wildcard? -> :auto
      true -> :single
    end
  end

  defp selector_type(%{type: :palette_rotate}), do: "palette"
  defp selector_type(_), do: "single"

  defp field_values(params, key) do
    params
    |> Map.get(key, Map.get(params, "#{key}[]"))
    |> case do
      nil -> []
      list when is_list(list) -> list
      map when is_map(map) -> map_values(map)
      other -> [other]
    end
    |> Enum.map(fn
      nil -> nil
      value -> to_string(value)
    end)
  end

  defp map_values(map) do
    map
    |> Enum.sort_by(fn {raw_key, _value} ->
      raw_key
      |> to_string()
      |> Integer.parse()
      |> case do
        {index, ""} -> {0, index}
        _ -> {1, to_string(raw_key)}
      end
    end)
    |> Enum.map(fn {_key, value} -> value end)
  end

  defp normalize_option_values(options) do
    options
    |> Enum.map(&extract_option_value/1)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp extract_option_value(%{"value" => value}), do: to_option_string(value)
  defp extract_option_value(%{value: value}), do: to_option_string(value)
  defp extract_option_value(value), do: to_option_string(value)

  defp to_option_string(nil), do: ""
  defp to_option_string(value), do: value |> to_string() |> String.trim()

  defp normalize_boolean(value, default) do
    case value do
      true -> true
      false -> false
      "true" -> true
      "false" -> false
      "1" -> true
      "0" -> false
      1 -> true
      0 -> false
      nil -> default
      "" -> default
      _ -> default
    end
  end
end
