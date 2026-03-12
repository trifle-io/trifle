defmodule TrifleApp.Components.DashboardWidgets.TableEditor do
  @moduledoc false

  use Phoenix.Component

  alias TrifleApp.Components.DashboardWidgets.MetricSeriesEditor

  attr :widget, :map, required: true
  attr :path_options, :list, default: []

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})

    assigns =
      assigns
      |> assign(:widget, widget)

    ~H"""
    <MetricSeriesEditor.editor
      widget={@widget}
      path_options={@path_options}
      path_placeholder="metrics.table.*"
      path_help="Path rows become table rows; timestamps are the columns. Expression rows let you derive additional rows from prior rows."
    />
    """
  end
end
