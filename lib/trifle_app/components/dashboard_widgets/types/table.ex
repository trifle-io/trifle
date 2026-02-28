defmodule TrifleApp.Components.DashboardWidgets.Types.Table do
  @moduledoc false

  @behaviour TrifleApp.Components.DashboardWidgets.WidgetType

  alias TrifleApp.Components.DataTable
  alias TrifleApp.Components.DashboardWidgets.{Table, TableEditor}
  alias TrifleApp.DesignSystem.ChartColors

  @impl true
  def type, do: "table"

  @impl true
  def editor_module, do: TableEditor

  @impl true
  def dataset(series, widget), do: Table.dataset(series, widget)

  @impl true
  def client_payload(widget_id, dataset_maps) do
    dataset = fetch(dataset_maps, :table, widget_id)

    case dataset do
      %{} = table_dataset ->
        aggrid_payload = DataTable.to_aggrid_payload(table_dataset)

        if is_nil(aggrid_payload) do
          nil
        else
          Map.merge(aggrid_payload, %{
            color_paths:
              Map.get(table_dataset, :color_paths) || Map.get(table_dataset, "color_paths") || [],
            color_palette: ChartColors.palette()
          })
        end

      _ ->
        nil
    end
  end

  @impl true
  def normalize_widget(widget), do: widget

  defp fetch(dataset_maps, key, id) do
    dataset_maps
    |> Map.get(key, %{})
    |> Map.get(id)
  end
end
