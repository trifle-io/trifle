defmodule TrifleApp.Components.DashboardWidgets.Types.Category do
  @moduledoc false

  @behaviour TrifleApp.Components.DashboardWidgets.WidgetType

  alias TrifleApp.Components.DashboardWidgets.{Category, CategoryEditor}

  @impl true
  def type, do: "category"

  @impl true
  def editor_module, do: CategoryEditor

  @impl true
  def dataset(series, widget), do: Category.dataset(series, widget)

  @impl true
  def client_payload(widget_id, dataset_maps), do: fetch(dataset_maps, :category, widget_id)

  @impl true
  def normalize_widget(widget), do: widget

  defp fetch(dataset_maps, key, id) do
    dataset_maps
    |> Map.get(key, %{})
    |> Map.get(id)
  end
end
