defmodule TrifleApp.Components.DashboardWidgets.Types.Heatmap do
  @moduledoc false

  @behaviour TrifleApp.Components.DashboardWidgets.WidgetType

  alias TrifleApp.Components.DashboardWidgets.{Distribution, DistributionEditor}
  alias TrifleApp.Components.DashboardWidgets.Types.NormalizeDistribution

  @impl true
  def type, do: "heatmap"

  @impl true
  def editor_module, do: DistributionEditor

  @impl true
  def dataset(series, widget), do: Distribution.dataset(series, normalize_widget(widget))

  @impl true
  def client_payload(widget_id, dataset_maps) do
    case fetch(dataset_maps, :distribution, widget_id) do
      %{} = payload -> Map.put_new(payload, :widget_type, "heatmap")
      _ -> nil
    end
  end

  @impl true
  def normalize_widget(widget), do: NormalizeDistribution.normalize(widget, "heatmap")

  defp fetch(dataset_maps, key, id) do
    dataset_maps
    |> Map.get(key, %{})
    |> Map.get(id)
  end
end
