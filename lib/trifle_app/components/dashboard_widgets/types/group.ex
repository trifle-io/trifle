defmodule TrifleApp.Components.DashboardWidgets.Types.Group do
  @moduledoc false

  @behaviour TrifleApp.Components.DashboardWidgets.WidgetType

  alias TrifleApp.Components.DashboardWidgets.{GroupEditor, LayoutTree}

  @impl true
  def type, do: "group"

  @impl true
  def editor_module, do: GroupEditor

  @impl true
  def dataset(_series, _widget), do: nil

  @impl true
  def client_payload(_widget_id, _dataset_maps), do: nil

  @impl true
  def normalize_widget(widget) when is_map(widget) do
    LayoutTree.normalize_group_item(widget)
  end
end
