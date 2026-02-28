defmodule TrifleApp.Components.DashboardWidgets.Types.Timeseries do
  @moduledoc false

  @behaviour TrifleApp.Components.DashboardWidgets.WidgetType

  alias TrifleApp.Components.DashboardWidgets.Registry
  alias TrifleApp.Components.DashboardWidgets.{Timeseries, TimeseriesEditor}

  @impl true
  def type, do: "timeseries"

  @impl true
  def editor_module, do: TimeseriesEditor

  @impl true
  def dataset(series, widget), do: Timeseries.dataset(series, widget)

  @impl true
  def client_payload(widget_id, dataset_maps),
    do: Registry.fetch_dataset(dataset_maps, :timeseries, widget_id)

  @impl true
  def normalize_widget(widget), do: widget
end
