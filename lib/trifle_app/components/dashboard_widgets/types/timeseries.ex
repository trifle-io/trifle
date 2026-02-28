defmodule TrifleApp.Components.DashboardWidgets.Types.Timeseries do
  @moduledoc false

  @behaviour TrifleApp.Components.DashboardWidgets.WidgetType

  alias TrifleApp.Components.DashboardWidgets.{Timeseries, TimeseriesEditor}

  @impl true
  def type, do: "timeseries"

  @impl true
  def editor_module, do: TimeseriesEditor

  @impl true
  def dataset(series, widget), do: Timeseries.dataset(series, widget)

  @impl true
  def client_payload(widget_id, dataset_maps), do: fetch(dataset_maps, :timeseries, widget_id)

  @impl true
  def normalize_widget(widget), do: widget

  defp fetch(dataset_maps, key, id) do
    dataset_maps
    |> Map.get(key, %{})
    |> Map.get(id)
  end
end
