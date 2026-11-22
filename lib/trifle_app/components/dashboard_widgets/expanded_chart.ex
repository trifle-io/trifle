defmodule TrifleApp.Components.DashboardWidgets.ExpandedChart do
  @moduledoc "Shared expanded chart and sortable series summary for read-only widgets."
  use TrifleApp, :html

  alias TrifleApp.DesignSystem.ChartColors

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :type, :string, default: "timeseries"
  attr :chart, :map, default: nil
  attr :visual, :map, default: nil
  attr :text, :map, default: nil

  def content(assigns) do
    ~H"""
    <div
      id={@id}
      class="flex h-full min-h-0 min-w-0 flex-col gap-4"
      phx-hook="ExpandedWidgetView"
      data-type={@type}
      data-title={@title}
      data-colors={ChartColors.json_palette()}
      data-chart={if @chart, do: Jason.encode!(@chart)}
      data-visual={if @visual, do: Jason.encode!(@visual)}
      data-text={if @text, do: Jason.encode!(@text)}
    >
      <div class="min-h-0 flex-[3]">
        <div class="h-full w-full rounded-lg border border-gray-200/80 dark:border-slate-700/60 bg-white dark:bg-slate-900/40 p-4">
          <div id={@id <> "-chart"} data-role="chart" phx-update="ignore" class="h-full w-full"></div>
        </div>
      </div>
      <div class="min-h-0 flex-[2] overflow-hidden rounded-lg border border-gray-200/80 bg-white dark:border-slate-700/60 dark:bg-slate-900/60">
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
