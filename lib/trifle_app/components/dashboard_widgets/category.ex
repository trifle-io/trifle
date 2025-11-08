defmodule TrifleApp.Components.DashboardWidgets.Category do
  @moduledoc false

  alias Trifle.Stats.Series
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

    {merged_map, encounter_order} =
      Enum.reduce(paths, {%{}, []}, fn path, acc ->
        formatted = Series.format_category(series_struct, path, slice_count)
        merge_category_formatted_with_order(acc, formatted)
      end)

    wildcard_paths? = Enum.any?(paths, &String.contains?(&1, "*"))
    custom_order? = category_custom_order?(paths)

    data =
      merged_map
      |> Enum.map(fn {k, v} -> %{name: to_string(k), value: normalize_number(v)} end)
      |> sort_category_entries(encounter_order, wildcard_paths?, custom_order?)

    %{
      id: id,
      chart_type: chart_type,
      data: data
    }
  end

  defp merge_category_formatted_with_order({acc_map, acc_order}, formatted) do
    cond do
      is_list(formatted) ->
        formatted
        |> Enum.filter(&is_map/1)
        |> Enum.reduce({acc_map, acc_order}, &merge_category_map_with_order(&2, &1))

      is_map(formatted) ->
        merge_category_map_with_order({acc_map, acc_order}, formatted)

      true ->
        {acc_map, acc_order}
    end
  end

  defp merge_category_map_with_order({acc_map, acc_order}, map) do
    Enum.reduce(map, {acc_map, acc_order}, fn {key, value}, {map_acc, order_acc} ->
      name = to_string(key)
      number = normalize_number(value)
      updated_map = Map.update(map_acc, name, number, fn existing -> existing + number end)
      updated_order = if name in order_acc, do: order_acc, else: order_acc ++ [name]
      {updated_map, updated_order}
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
