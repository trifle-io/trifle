defmodule TrifleApp.Components.DashboardWidgets.TableEditor do
  @moduledoc false

  use Phoenix.Component

  alias TrifleApp.Components.DashboardWidgets.MetricSeriesEditor

  attr :widget, :map, required: true
  attr :path_options, :list, default: []
  attr :group_path, :string, default: nil

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})

    assigns =
      assigns
      |> assign(:widget, widget)

    ~H"""
    <div class="grid grid-cols-1 gap-4 xl:grid-cols-3">
      <div class="xl:col-span-2">
        <MetricSeriesEditor.editor
          widget={@widget}
          path_options={@path_options}
          group_path={@group_path}
          path_placeholder="metrics.table.*"
          path_help="Path rows become table rows; timestamps are the columns. Expression rows let you derive additional rows from prior rows."
        />
      </div>
    </div>
    """
  end
end
