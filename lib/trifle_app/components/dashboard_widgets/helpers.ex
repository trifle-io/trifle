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
          "min" => normalize_designator_number(Map.get(params, "#{prefix}min"), Map.get(existing, "min")),
          "max" => normalize_designator_number(Map.get(params, "#{prefix}max"), Map.get(existing, "max")),
          "step" => normalize_designator_number(Map.get(params, "#{prefix}step"), Map.get(existing, "step"))
        }

      "geometric" ->
        %{
          "type" => "geometric",
          "min" => normalize_designator_number(Map.get(params, "#{prefix}min"), Map.get(existing, "min")),
          "max" => normalize_designator_number(Map.get(params, "#{prefix}max"), Map.get(existing, "max"))
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
          |> Map.get("designator") || Map.get(source, :designator) || default_distribution_designator()
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
    value
    |> Enum.map(&parse_number/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_distribution_buckets(value) when is_binary(value) do
    value
    |> String.split(~r/[\n,]+/, trim: true)
    |> normalize_distribution_buckets()
  end

  defp normalize_distribution_buckets(_other), do: []

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
end
