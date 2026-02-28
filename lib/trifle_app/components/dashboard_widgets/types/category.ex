defmodule TrifleApp.Components.DashboardWidgets.Types.Category do
  @moduledoc false

  @behaviour TrifleApp.Components.DashboardWidgets.WidgetType

  alias TrifleApp.Components.DashboardWidgets.{Category, CategoryEditor}
  alias TrifleApp.Components.DashboardWidgets.Registry

  @impl true
  def type, do: "category"

  @impl true
  def editor_module, do: CategoryEditor

  @impl true
  def dataset(series, widget), do: Category.dataset(series, widget)

  @impl true
  def client_payload(widget_id, dataset_maps),
    do: Registry.fetch_dataset(dataset_maps, :category, widget_id)

  @impl true
  def normalize_widget(widget), do: widget
end
