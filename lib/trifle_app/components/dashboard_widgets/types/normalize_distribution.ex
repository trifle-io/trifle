defmodule TrifleApp.Components.DashboardWidgets.Types.NormalizeDistribution do
  @moduledoc false

  alias TrifleApp.Components.DashboardWidgets.Helpers, as: WidgetHelpers

  @spec normalize(map(), String.t()) :: map()
  def normalize(item, widget_type) when is_map(item) do
    normalized_type = normalize_widget_type(widget_type)

    path_inputs =
      item
      |> WidgetHelpers.path_inputs_for_form("distribution")

    normalized_paths =
      item
      |> Map.get("paths", item["path"])
      |> WidgetHelpers.normalize_distribution_paths_for_edit()

    selectors =
      WidgetHelpers.normalize_series_color_selectors_for_paths(
        path_inputs,
        [],
        Map.get(item, "series_color_selectors", %{})
      )

    path_aggregation =
      item
      |> Map.get("path_aggregation")
      |> WidgetHelpers.normalize_distribution_path_aggregation()

    fallback_heatmap_color =
      WidgetHelpers.heatmap_single_color_from_paths(path_inputs, selectors)

    color_mode =
      case normalized_type do
        "heatmap" ->
          item
          |> Map.get("color_mode")
          |> WidgetHelpers.normalize_heatmap_color_mode()

        _ ->
          nil
      end

    color_config =
      case normalized_type do
        "heatmap" ->
          item
          |> Map.get("color_config", %{})
          |> WidgetHelpers.normalize_heatmap_color_config(fallback_heatmap_color)

        _ ->
          nil
      end

    mode_default = if(normalized_type == "heatmap", do: "3d", else: nil)

    designators = WidgetHelpers.normalize_distribution_designators(%{}, item)

    designator =
      Map.get(designators, "horizontal") ||
        WidgetHelpers.default_distribution_designator()

    item
    |> Map.put("type", normalized_type)
    |> Map.put("path_inputs", path_inputs)
    |> maybe_put_mode(mode_default, normalized_type)
    |> Map.put("paths", normalized_paths)
    |> Map.put("series_color_selectors", selectors)
    |> Map.put("chart_type", if(normalized_type == "heatmap", do: "heatmap", else: "bar"))
    |> Map.put("path_aggregation", path_aggregation)
    |> Map.put("designators", designators)
    |> Map.put("designator", designator)
    |> Map.put_new("legend", true)
    |> put_heatmap_color_fields(normalized_type, color_mode, color_config)
  end

  def normalize(other, _widget_type), do: other

  defp normalize_widget_type(value) do
    value
    |> to_string()
    |> String.downcase()
    |> case do
      "heatmap" -> "heatmap"
      _ -> "distribution"
    end
  end

  defp maybe_put_mode(widget, nil, _widget_type), do: widget

  defp maybe_put_mode(widget, default, widget_type) do
    mode =
      widget
      |> Map.get("mode")
      |> WidgetHelpers.normalize_distribution_mode()
      |> case do
        "2d" when widget_type == "heatmap" -> "3d"
        normalized -> normalized
      end

    Map.put(widget, "mode", mode || default)
  end

  defp put_heatmap_color_fields(widget, "heatmap", color_mode, color_config) do
    widget
    |> Map.put("color_mode", color_mode || "auto")
    |> Map.put("color_config", color_config || %{})
  end

  defp put_heatmap_color_fields(widget, _widget_type, _color_mode, _color_config) do
    widget
    |> Map.delete("color_mode")
    |> Map.delete("color_config")
  end
end
