defmodule TrifleApp.Components.DashboardWidgets.GroupEditor do
  @moduledoc false

  use Phoenix.Component

  alias TrifleApp.Components.DashboardWidgets.{Helpers, SeriesColorSelector}

  attr :widget, :map, required: true
  attr :path_options, :list, default: []

  def editor(assigns) do
    assigns =
      assigns
      |> assign(
        :header_color_selector,
        Helpers.group_header_color_selector_for_form(Map.get(assigns, :widget, %{}))
      )

    ~H"""
    <div class="space-y-4">
      <div class="rounded-lg border border-dashed border-slate-300 bg-slate-50/80 px-4 py-4 text-sm text-slate-600 dark:border-slate-600 dark:bg-slate-900/40 dark:text-slate-300">
        Widget groups organize related widgets into a nested grid. Drag widgets into the group on the dashboard to control layout and, later, hover sync scope.
      </div>

      <div class="sm:max-w-xs">
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
          Header background
        </label>
        <SeriesColorSelector.input
          id_prefix={"group-header-color-#{Map.get(@widget, "id", "new")}"}
          name="group_header_color_selector"
          index={0}
          indexed_name={false}
          selector={@header_color_selector}
          allow_palette_rotate={false}
          default_label="Default"
          default_preview_colors={[Helpers.default_group_header_background_preview()]}
          class="mt-2"
        />
      </div>
    </div>
    """
  end
end
