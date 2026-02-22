defmodule TrifleApp.Components.DashboardWidgets.Category do
  @moduledoc false

  alias Trifle.Stats.Series
  alias TrifleApp.Components.DashboardWidgets.Helpers, as: WidgetHelpers
  require Logger

  @spec datasets(Series.t() | nil, list()) :: list()
  def datasets(nil, _grid_items), do: []

  def datasets(series_struct, grid_items) do
    items =
      grid_items
      |> Enum.filter(fn item ->
        String.downcase(to_string(item["type"] || "")) == "category"
      end)
      |> Enum.map(&dataset(series_struct, &1))
      |> Enum.reject(&is_nil/1)

    Logger.debug(fn ->
      summary = Enum.map(items, fn i -> %{id: i.id, entries: length(i.data)} end)
      "Category widgets: " <> inspect(summary)
    end)

    items
  end

  @spec dataset(Series.t() | nil, map()) :: map() | nil
  def dataset(nil, _item), do: nil

  def dataset(series_struct, item) do
    id = to_string(item["id"])

    raw_paths =
      case item["paths"] do
        list when is_list(list) -> list
        _ -> []
      end

    fallback_paths =
      case Map.get(item, "path") do
        nil -> []
        "" -> []
        value -> [value]
      end

    path_sources =
      case raw_paths do
        [] -> fallback_paths
        list -> list
      end

    paths =
      path_sources
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    chart_type = String.downcase(to_string(item["chart_type"] || "bar"))

    slice_count =
      series_struct
      |> Map.get(:series, %{})
      |> case do
        series_map when is_map(series_map) ->
          values = Map.get(series_map, :values) || Map.get(series_map, "values") || []
          if is_list(values) and length(values) > 1, do: 2, else: 1

        _ ->
          1
      end

    path_inputs =
      item
      |> WidgetHelpers.path_inputs_for_form("category")
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)

    selectors =
      item
      |> Map.get("series_color_selectors", %{})
      |> WidgetHelpers.normalize_series_color_selectors_map()

    path_specs =
      paths
      |> Enum.with_index()
      |> Enum.map(fn {path, index} ->
        path_input =
          path_inputs
          |> Enum.at(index)
          |> case do
            nil -> path
            "" -> path
            value -> value
          end

        %{path: path, path_input: path_input}
      end)

    {merged_map, encounter_order, source_map} =
      Enum.reduce(path_specs, {%{}, [], %{}}, fn %{path: path, path_input: path_input}, acc ->
        formatted = Series.format_category(series_struct, path, slice_count)
        merge_category_formatted_with_order(acc, formatted, path_input)
      end)

    wildcard_paths? = Enum.any?(paths, &String.contains?(&1, "*"))
    custom_order? = category_custom_order?(paths)

    base_entries =
      merged_map
      |> Enum.map(fn {k, v} ->
        name = to_string(k)

        %{
          name: name,
          value: normalize_number(v),
          source_path: Map.get(source_map, name, name)
        }
      end)
      |> sort_category_entries(encounter_order, wildcard_paths?, custom_order?)

    {data, _rotate_indexes} =
      Enum.reduce(base_entries, {[], %{}}, fn entry, {acc, rotate_indexes} ->
        selector = WidgetHelpers.selector_for_path(selectors, entry.source_path)
        parsed_selector = WidgetHelpers.parse_series_color_selector(selector)

        {color, next_rotate_indexes} =
          case parsed_selector do
            %{type: :palette_rotate} ->
              rotate_index = Map.get(rotate_indexes, entry.source_path, 0)
              next = Map.put(rotate_indexes, entry.source_path, rotate_index + 1)
              {WidgetHelpers.resolve_series_color(selector, rotate_index), next}

            _ ->
              {WidgetHelpers.resolve_series_color(selector, 0), rotate_indexes}
          end

        item = %{name: entry.name, value: entry.value, color: color}
        {[item | acc], next_rotate_indexes}
      end)
      |> then(fn {acc, rotate_indexes} -> {Enum.reverse(acc), rotate_indexes} end)

    %{
      id: id,
      chart_type: chart_type,
      data: data
    }
  end

  defp merge_category_formatted_with_order(
         {acc_map, acc_order, source_map},
         formatted,
         source_path
       ) do
    cond do
      is_list(formatted) ->
        formatted
        |> Enum.filter(&is_map/1)
        |> Enum.reduce(
          {acc_map, acc_order, source_map},
          &merge_category_map_with_order(&2, &1, source_path)
        )

      is_map(formatted) ->
        merge_category_map_with_order({acc_map, acc_order, source_map}, formatted, source_path)

      true ->
        {acc_map, acc_order, source_map}
    end
  end

  defp merge_category_map_with_order({acc_map, acc_order, source_map}, map, source_path) do
    Enum.reduce(map, {acc_map, acc_order, source_map}, fn {key, value},
                                                          {map_acc, order_acc, src_acc} ->
      name = to_string(key)
      number = normalize_number(value)
      updated_map = Map.update(map_acc, name, number, fn existing -> existing + number end)
      updated_order = if name in order_acc, do: order_acc, else: order_acc ++ [name]
      updated_source_map = Map.put_new(src_acc, name, source_path)
      {updated_map, updated_order, updated_source_map}
    end)
  end

  defp category_custom_order?(paths) do
    sanitized =
      paths
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case sanitized do
      [] -> false
      list -> length(list) > 1 and Enum.all?(list, &(not String.contains?(&1, "*")))
    end
  end

  defp sort_category_entries(entries, encounter_order, wildcard_paths?, custom_order?) do
    cond do
      wildcard_paths? ->
        Enum.sort_by(entries, fn %{name: name} -> natural_sort_key(name) end)

      custom_order? and encounter_order != [] ->
        index_map = encounter_order |> Enum.with_index() |> Map.new()
        fallback_index = map_size(index_map)

        Enum.sort_by(entries, fn %{name: name} ->
          {Map.get(index_map, name, fallback_index), natural_sort_key(name)}
        end)

      true ->
        Enum.sort_by(entries, fn %{name: name} -> String.downcase(name || "") end)
    end
  end

  defp natural_sort_key(nil), do: [{:str, ""}]

  defp natural_sort_key(name) when is_binary(name) do
    case Regex.scan(~r/\d+|\D+/, name) do
      [] ->
        [{:str, String.downcase(name)}]

      segments ->
        segments
        |> Enum.map(&List.first/1)
        |> Enum.map(&natural_token/1)
    end
  end

  defp natural_sort_key(other), do: other |> to_string() |> natural_sort_key()

  defp natural_token(segment) do
    cond do
      segment == "" ->
        {:str, ""}

      true ->
        case Integer.parse(segment) do
          {int, ""} ->
            {:num, int}

          _ ->
            case Float.parse(segment) do
              {float, ""} -> {:num, float}
              _ -> {:str, String.downcase(segment)}
            end
        end
    end
  end

  defp normalize_number(%Decimal{} = d), do: Decimal.to_float(d)
  defp normalize_number(v) when is_number(v), do: v * 1.0
  defp normalize_number(_), do: 0.0
end
