defmodule TrifleApp.Components.DashboardWidgets.Types.Gauge do
  @moduledoc false
  @behaviour TrifleApp.Components.DashboardWidgets.WidgetType
  alias TrifleApp.Components.DashboardWidgets.{Gauge, GaugeEditor, MetricSeries, Registry}
  def type, do: "gauge"
  def editor_module, do: GaugeEditor
  def dataset(stats, widget), do: Gauge.dataset(stats, widget)
  # Gauges use the existing timeline transport and chart lifecycle.
  def client_payload(id, maps), do: Registry.fetch_dataset(maps, :timeseries, id)
  def normalize_widget(widget), do: MetricSeries.normalize_widget(widget)
end
