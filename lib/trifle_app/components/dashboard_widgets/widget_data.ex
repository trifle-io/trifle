defmodule TrifleApp.Components.DashboardWidgets.WidgetData do
  @moduledoc false

  alias TrifleApp.Components.DashboardWidgets.{
    Category,
    Distribution,
    Kpi,
    List,
    Registry,
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
          list: list(),
          distribution: list()
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
      list: List.datasets(stats, grid_items),
      distribution: Distribution.datasets(stats, grid_items)
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
          list: map(),
          distribution: map()
        }
  def dataset_maps(%{
        kpi_values: kpi_values,
        kpi_visuals: kpi_visuals,
        timeseries: timeseries,
        category: category,
        text: text,
        table: table,
        list: list,
        distribution: distribution
      }) do
    %{
      kpi_values: to_map(kpi_values),
      kpi_visuals: to_map(kpi_visuals),
      timeseries: to_map(timeseries),
      category: to_map(category),
      text: to_map(text),
      table: to_map(table),
      list: to_map(list),
      distribution: to_map(distribution)
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
        list: [],
        distribution: []
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
  defp normalize_id(nil), do: nil
  defp normalize_id(id) when is_binary(id), do: id
  defp normalize_id(id) when is_atom(id), do: Atom.to_string(id)
  defp normalize_id(id) when is_integer(id), do: Integer.to_string(id)
  defp normalize_id(id) when is_float(id), do: :erlang.float_to_binary(id, decimals: 0)
  defp normalize_id(other), do: to_string(other)

  @spec widget_payloads_from_dataset_maps(list(), map()) :: map()
  def widget_payloads_from_dataset_maps(grid_items, dataset_maps)
      when is_list(grid_items) and is_map(dataset_maps) do
    reserved_widget_ids = reserved_widget_ids(grid_items)

    grid_items
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {widget, index}, acc ->
      widget_id =
        widget
        |> widget_id()
        |> fallback_widget_id(index, reserved_widget_ids, acc)

      widget_type = Registry.widget_type(widget)

      envelope = %{
        id: widget_id,
        type: widget_type,
        title: widget_title(widget),
        payload: Registry.client_payload(widget_type, widget_id, dataset_maps)
      }

      Map.put(acc, widget_id, envelope)
    end)
  end

  def widget_payloads_from_dataset_maps(_grid_items, _dataset_maps), do: %{}

  @spec widget_payloads(Trifle.Stats.Series.t() | nil, list()) :: map()
  def widget_payloads(stats, grid_items) do
    dataset_maps =
      stats
      |> datasets(grid_items)
      |> dataset_maps()

    widget_payloads_from_dataset_maps(grid_items, dataset_maps)
  end

  defp widget_id(widget) when is_map(widget) do
    widget
    |> Map.get("id")
    |> case do
      nil -> Map.get(widget, :id)
      value -> value
    end
    |> case do
      nil -> Map.get(widget, "uuid")
      value -> value
    end
    |> case do
      nil -> Map.get(widget, :uuid)
      value -> value
    end
    |> normalize_id()
  end

  defp widget_id(_widget), do: nil

  defp fallback_widget_id(id, _index, _reserved_widget_ids, _acc) when is_binary(id) and id != "",
    do: id

  defp fallback_widget_id(_id, index, reserved_widget_ids, acc),
    do: unique_generated_widget_id(index, 0, reserved_widget_ids, acc)

  defp unique_generated_widget_id(index, suffix, reserved_widget_ids, acc) do
    candidate =
      case suffix do
        0 -> "__generated-widget-#{index}"
        n -> "__generated-widget-#{index}-#{n}"
      end

    if MapSet.member?(reserved_widget_ids, candidate) or Map.has_key?(acc, candidate) do
      unique_generated_widget_id(index, suffix + 1, reserved_widget_ids, acc)
    else
      candidate
    end
  end

  defp reserved_widget_ids(grid_items) do
    grid_items
    |> Enum.map(&widget_id/1)
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> MapSet.new()
  end

  defp widget_title(widget) when is_map(widget) do
    widget
    |> Map.get("title", Map.get(widget, :title, ""))
    |> to_string()
  end

  defp widget_title(_widget), do: ""
end
