defmodule TrifleApp.Components.DashboardWidgets.ExpandedChart do
  @moduledoc "Shared expanded chart and sortable series summary for read-only widgets."
  use TrifleApp, :html

  alias TrifleApp.DesignSystem.ChartColors

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :type, :string, default: "timeseries"
  attr :chart, :map, default: nil

  def content(assigns) do
    ~H"""
    <div
      id={@id}
      class="h-[80vh] flex flex-col gap-6 overflow-y-auto"
      phx-hook="ExpandedWidgetView"
      data-type={@type}
      data-title={@title}
      data-colors={ChartColors.json_palette()}
      data-chart={if @chart, do: Jason.encode!(@chart)}
    >
      <div class="flex-1 min-h-[500px]">
        <div class="h-full w-full rounded-lg border border-gray-200/80 dark:border-slate-700/60 bg-white dark:bg-slate-900/40 p-4">
          <div id={@id <> "-chart"} data-role="chart" phx-update="ignore" class="h-full w-full"></div>
        </div>
      </div>
      <div class="flex-1 min-h-[300px] rounded-lg border border-gray-200/80 dark:border-slate-700/60 bg-white dark:bg-slate-900/60 overflow-auto">
        <div
          id={@id <> "-summary"}
          data-role="table-root"
          phx-update="ignore"
          class="h-full w-full overflow-auto"
        >
        </div>
      </div>
    </div>
    """
  end
end
