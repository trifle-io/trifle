defmodule TrifleApp.Components.DashboardWidgets.GaugeEditor do
  use Phoenix.Component
  alias TrifleApp.Components.DashboardWidgets.MetricSeriesEditor
  attr :widget, :map, required: true
  attr :path_options, :list, default: []
  attr :group_path, :string, default: nil

  def editor(assigns) do
    ~H"""
    <div class="space-y-4">
      <MetricSeriesEditor.editor
        widget={@widget}
        path_options={@path_options}
        group_path={@group_path}
        path_help="Displays the first visible resolved series. With a sample count path, this series represents bucket sums; otherwise each bucket is one sample."
      />
      <label class="block text-sm">
        Sample count path (optional; $.path for group-relative counts)
        <input
          type="text"
          name="gauge_count_path"
          value={@widget["gauge_count_path"]}
          placeholder="duration.count"
          class="mt-1 block w-full rounded-md border-slate-300 dark:border-slate-600 dark:bg-slate-800"
        />
      </label>
      <label class="block text-sm">
        Unit
        <input
          type="text"
          name="gauge_unit"
          value={@widget["unit"]}
          placeholder="ms"
          class="mt-1 block w-full rounded-md border-slate-300 dark:border-slate-600 dark:bg-slate-800"
        />
      </label>
      <label class="block text-sm">
        Maximum (blank for automatic)
        <input
          type="number"
          min="0.000001"
          step="any"
          name="gauge_max"
          value={@widget["gauge_max"]}
          class="mt-1 block w-full rounded-md border-slate-300 dark:border-slate-600 dark:bg-slate-800"
        />
      </label>
      <p class="text-xs text-slate-500">
        Compares the latest populated bucket average with the weighted timeframe average. The arc uses a neutral scale, without health thresholds.
      </p>
    </div>
    """
  end
end
