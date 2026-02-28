defmodule TrifleApp.Components.DashboardWidgets.Types.Distribution do
  @moduledoc false

  @behaviour TrifleApp.Components.DashboardWidgets.WidgetType

  alias TrifleApp.Components.DashboardWidgets.{Distribution, DistributionEditor}
  alias TrifleApp.Components.DashboardWidgets.Types.NormalizeDistribution

  @impl true
  def type, do: "distribution"

  @impl true
  def editor_module, do: DistributionEditor

  @impl true
  def dataset(series, widget), do: Distribution.dataset(series, normalize_widget(widget))

  @impl true
  def client_payload(widget_id, dataset_maps), do: fetch(dataset_maps, :distribution, widget_id)

  @impl true
  def normalize_widget(widget), do: NormalizeDistribution.normalize(widget, "distribution")

  defp fetch(dataset_maps, key, id) do
    dataset_maps
    |> Map.get(key, %{})
    |> Map.get(id)
  end
end
