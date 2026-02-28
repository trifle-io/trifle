defmodule TrifleApp.Components.DashboardWidgets.Types.Text do
  @moduledoc false

  @behaviour TrifleApp.Components.DashboardWidgets.WidgetType

  alias TrifleApp.Components.DashboardWidgets.{Text, TextEditor}

  @impl true
  def type, do: "text"

  @impl true
  def editor_module, do: TextEditor

  @impl true
  def dataset(_series, widget), do: Text.widget(widget)

  @impl true
  def client_payload(widget_id, dataset_maps), do: fetch(dataset_maps, :text, widget_id)

  @impl true
  def normalize_widget(widget), do: widget

  defp fetch(dataset_maps, key, id) do
    dataset_maps
    |> Map.get(key, %{})
    |> Map.get(id)
  end
end
