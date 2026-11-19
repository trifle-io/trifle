defmodule TrifleApp.Components.DashboardWidgets.Types.TraceOverview do
  @moduledoc "Internal, read-only widget used by the trace overview experiment."
  @behaviour TrifleApp.Components.DashboardWidgets.WidgetType
  alias TrifleApp.Components.DashboardWidgets.Registry

  def type, do: "trace_overview"
  def editor_module, do: nil
  def dataset(_, _), do: nil
  def client_payload(id, maps), do: Registry.fetch_dataset(maps, :timeseries, id)
  def normalize_widget(widget), do: widget
end
