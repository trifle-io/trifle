defmodule TrifleApp.Components.DashboardWidgets.Category do
  @moduledoc false

  alias Trifle.Stats.Series
  alias TrifleApp.Components.DashboardWidgets.MetricSeriesEvaluator
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

    base_entries =
      series_struct
      |> MetricSeriesEvaluator.resolve_category_rows(item, slice_count)
      |> MetricSeriesEvaluator.category_entries()
      |> Enum.reduce({%{}, []}, fn entry, {acc_map, encounter_order} ->
        updated_map =
          Map.update(acc_map, entry.name, entry, fn existing ->
            %{existing | value: normalize_number(existing.value) + normalize_number(entry.value)}
          end)

        updated_order =
          if entry.name in encounter_order, do: encounter_order, else: encounter_order ++ [entry.name]

        {updated_map, updated_order}
      end)
      |> then(fn {acc_map, encounter_order} ->
        acc_map
        |> Map.values()
        |> Enum.sort_by(fn entry ->
          {Enum.find_index(encounter_order, &(&1 == entry.name)) || 1_000_000, natural_sort_key(entry.name)}
        end)
      end)

    data =
      Enum.map(base_entries, fn entry ->
        %{name: entry.name, value: normalize_number(entry.value), color: entry.color}
      end)

    %{
      id: id,
      chart_type: chart_type,
      data: data
    }
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
