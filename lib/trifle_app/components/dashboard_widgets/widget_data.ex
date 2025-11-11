defmodule TrifleApp.Components.DashboardWidgets.WidgetData do
  @moduledoc false

  alias TrifleApp.Components.DashboardWidgets.{
    Category,
    Kpi,
    List,
    Table,
    Text,
    Timeseries,
    WidgetView
  }

  @type dataset_group :: %{
          kpi_values: list(),
          kpi_visuals: list(),
          timeseries: list(),
          category: list(),
          text: list(),
          table: list(),
          list: list()
        }

  @spec datasets(Trifle.Stats.Series.t() | nil, list()) :: dataset_group()
  def datasets(stats, grid_items) do
    {kpi_values, kpi_visuals} = Kpi.datasets(stats, grid_items)

    %{
      kpi_values: kpi_values,
      kpi_visuals: kpi_visuals,
      timeseries: Timeseries.datasets(stats, grid_items),
      category: Category.datasets(stats, grid_items),
      text: Text.widgets(grid_items),
      table: Table.datasets(stats, grid_items),
      list: List.datasets(stats, grid_items)
    }
  end

  @spec datasets_from_dashboard(Trifle.Stats.Series.t() | nil, map()) :: dataset_group()
  def datasets_from_dashboard(stats, dashboard) do
    grid_items = WidgetView.grid_items(dashboard)
    datasets(stats, grid_items)
  end

  @spec dataset_maps(dataset_group()) :: %{
          kpi_values: map(),
          kpi_visuals: map(),
          timeseries: map(),
          category: map(),
          text: map(),
          table: map(),
          list: map()
        }
  def dataset_maps(%{
        kpi_values: kpi_values,
        kpi_visuals: kpi_visuals,
        timeseries: timeseries,
        category: category,
        text: text,
        table: table,
        list: list
      }) do
    %{
      kpi_values: to_map(kpi_values),
      kpi_visuals: to_map(kpi_visuals),
      timeseries: to_map(timeseries),
      category: to_map(category),
      text: to_map(text),
      table: to_map(table),
      list: to_map(list)
    }
  end

  def dataset_maps(_other),
    do:
      dataset_maps(%{
        kpi_values: [],
        kpi_visuals: [],
        timeseries: [],
        category: [],
        text: [],
        table: [],
        list: []
      })

  defp to_map(list) when is_list(list) do
    list
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(%{}, fn item, acc ->
      case normalize_id(item) do
        nil -> acc
        id -> Map.put(acc, id, item)
      end
    end)
  end

  defp to_map(_other), do: %{}

  defp normalize_id(%{id: id}), do: normalize_id(id)
  defp normalize_id(%{"id" => id}), do: normalize_id(id)
  defp normalize_id(id) when is_binary(id), do: id
  defp normalize_id(id) when is_atom(id), do: Atom.to_string(id)
  defp normalize_id(id) when is_integer(id), do: Integer.to_string(id)
  defp normalize_id(id) when is_float(id), do: :erlang.float_to_binary(id, decimals: 0)
  defp normalize_id(nil), do: nil
  defp normalize_id(other), do: to_string(other)
end
