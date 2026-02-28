defmodule TrifleApp.Components.DashboardWidgets.Types.List do
  @moduledoc false

  @behaviour TrifleApp.Components.DashboardWidgets.WidgetType

  alias TrifleApp.Components.DashboardWidgets.{List, ListEditor}
  alias TrifleApp.Components.DashboardWidgets.Registry

  @impl true
  def type, do: "list"

  @impl true
  def editor_module, do: ListEditor

  @impl true
  def dataset(series, widget), do: List.dataset(series, widget)

  @impl true
  def client_payload(widget_id, dataset_maps),
    do: Registry.fetch_dataset(dataset_maps, :list, widget_id)

  @impl true
  def normalize_widget(widget), do: widget
end
