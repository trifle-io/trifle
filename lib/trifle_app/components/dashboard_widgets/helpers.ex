defmodule TrifleApp.Components.DashboardWidgets.Helpers do
  @moduledoc false

  @text_widget_colors [
    %{id: "default", label: "Default (white)", background: "#ffffff", text: "#0f172a"},
    %{id: "slate", label: "Slate", background: "#0f172a", text: "#f8fafc"},
    %{id: "teal", label: "Teal", background: "#0f766e", text: "#ecfdf5"},
    %{id: "amber", label: "Amber", background: "#f59e0b", text: "#1f2937"},
    %{id: "emerald", label: "Emerald", background: "#10b981", text: "#064e3b"},
    %{id: "rose", label: "Rose", background: "#f43f5e", text: "#fff1f2"}
  ]

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

  ## Table helpers

  def table_paths_for_form(widget), do: category_paths_for_form(widget)
  def normalize_table_paths_param(value), do: normalize_category_paths_param(value)
  def normalize_table_paths_for_edit(paths), do: normalize_category_paths_for_edit(paths)

  def normalize_table_mode(value) do
    value
    |> to_string()
    |> String.downcase()
    |> case do
      "aggrid" -> "aggrid"
      "ag-grid" -> "aggrid"
      _ -> "html"
    end
  end
end
