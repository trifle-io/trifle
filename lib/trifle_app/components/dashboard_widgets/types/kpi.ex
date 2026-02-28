defmodule TrifleApp.Components.DashboardWidgets.Types.Kpi do
  @moduledoc false

  @behaviour TrifleApp.Components.DashboardWidgets.WidgetType

  alias TrifleApp.Components.DashboardWidgets.{Kpi, KpiEditor}

  @impl true
  def type, do: "kpi"

  @impl true
  def editor_module, do: KpiEditor

  @impl true
  def dataset(series, widget) do
    case Kpi.dataset(series, widget) do
      {value, visual} -> %{value: value, visual: visual}
      nil -> nil
    end
  end

  @impl true
  def client_payload(widget_id, dataset_maps) do
    value = fetch(dataset_maps, :kpi_values, widget_id)
    visual = fetch(dataset_maps, :kpi_visuals, widget_id)

    if is_nil(value) and is_nil(visual) do
      nil
    else
      %{value: value, visual: visual}
    end
  end

  @impl true
  def normalize_widget(widget), do: widget

  defp fetch(dataset_maps, key, id) do
    dataset_maps
    |> Map.get(key, %{})
    |> Map.get(id)
  end
end
