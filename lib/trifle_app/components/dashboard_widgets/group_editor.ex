defmodule TrifleApp.Components.DashboardWidgets.GroupEditor do
  @moduledoc false

  use Phoenix.Component

  import TrifleApp.Components.PathInput, only: [path_autocomplete_input: 1]

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
      |> assign(
        :group_path,
        Map.get(assigns.widget, "group_path", Map.get(assigns.widget, :group_path, ""))
        |> to_string()
      )

    ~H"""
    <div class="space-y-4">
      <div class="rounded-lg border border-dashed border-slate-300 bg-slate-50/80 px-4 py-4 text-sm text-slate-600 dark:border-slate-600 dark:bg-slate-900/40 dark:text-slate-300">
        Widget groups organize related widgets into a nested grid. Drag widgets into the group on the dashboard to control layout and, later, hover sync scope.
      </div>

      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
          Group path
        </label>
        <.path_autocomplete_input
          id={"group-path-#{Map.get(@widget, "id", "new")}"}
          name="group_path"
          value={@group_path}
          placeholder="jobs.*"
          path_options={@path_options}
          annotated={true}
          input_data_role="group-path"
          input_class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
          preview_class="rounded-md px-3 py-2 text-sm font-mono text-gray-900 dark:text-white"
        />
        <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
          Regular paths prefix child series. A terminal .* repeats this group for each matching path.
        </p>
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
          allow_palette_rotate={true}
          default_label="Default"
          default_preview_colors={[Helpers.default_group_header_background_preview()]}
          class="mt-2"
        />
      </div>
    </div>
    """
  end
end
