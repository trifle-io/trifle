defmodule TrifleApp.Components.DashboardWidgets.GroupEditor do
  @moduledoc false

  use Phoenix.Component

  attr :widget, :map, required: true
  attr :path_options, :list, default: []

  def editor(assigns) do
    ~H"""
    <div class="rounded-lg border border-dashed border-slate-300 bg-slate-50/80 px-4 py-4 text-sm text-slate-600 dark:border-slate-600 dark:bg-slate-900/40 dark:text-slate-300">
      Widget groups organize related widgets into a nested grid. Drag widgets into the group on the dashboard to control layout and, later, hover sync scope.
    </div>
    """
  end
end
