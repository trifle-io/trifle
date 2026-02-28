defmodule TrifleApp.Components.DashboardWidgets.Types.Text do
  @moduledoc false

  @behaviour TrifleApp.Components.DashboardWidgets.WidgetType

  alias TrifleApp.Components.DashboardWidgets.Registry
  alias TrifleApp.Components.DashboardWidgets.{Text, TextEditor}

  @impl true
  def type, do: "text"

  @impl true
  def editor_module, do: TextEditor

  @impl true
  def dataset(_series, widget), do: Text.widget(widget)

  @impl true
  def client_payload(widget_id, dataset_maps),
    do: Registry.fetch_dataset(dataset_maps, :text, widget_id)

  @impl true
  def normalize_widget(widget), do: widget
end
