defmodule TrifleApp.Components.DashboardWidgets.CategoryEditor do
  @moduledoc false

  use Phoenix.Component

  import TrifleApp.Components.DashboardWidgets.PathInput, only: [path_autocomplete_input: 1]

  alias TrifleApp.Components.DashboardWidgets.Helpers

  attr :widget, :map, required: true
  attr :path_options, :list, default: []

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})
    paths = Helpers.category_paths_for_form(widget)

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign(:paths, paths)
      |> assign(:chart_type, Map.get(widget, "chart_type", "bar"))

    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
      <div class="sm:col-span-2">
        <div
          id={"widget-#{Map.get(@widget, "id")}-category-paths"}
          phx-hook="CategoryPaths"
          data-widget-id={Map.get(@widget, "id")}
          class="space-y-3"
        >
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300">
            Paths
          </label>
          <div class="space-y-2">
            <%= for {path, index} <- Enum.with_index(@paths) do %>
              <div class="flex items-center gap-2">
                <div class="flex-1 min-w-0">
                  <.path_autocomplete_input
                    id={"widget-cat-path-#{Map.get(@widget, "id")}-#{index}"}
                    name="cat_paths[]"
                    value={path}
                    placeholder="metrics.category"
                    path_options={@path_options}
                    input_class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
                  />
                </div>
                <button
                  type="button"
                  data-action="remove"
                  data-index={index}
                  class="inline-flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-md bg-slate-200 text-slate-700 hover:bg-slate-300 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-slate-700 dark:text-slate-200 dark:hover:bg-slate-600"
                  aria-label="Remove path"
                  disabled={length(@paths) == 1}
                >
                  &minus;
                </button>
              </div>
            <% end %>
          </div>
          <button
            type="button"
            data-action="add"
            class="inline-flex items-center gap-1 rounded-md bg-teal-500 px-3 py-2 text-sm font-medium text-white hover:bg-teal-600 dark:bg-teal-600 dark:hover:bg-teal-500"
          >
            <span aria-hidden="true">+</span>
            <span class="sr-only">Add path</span>
          </button>
          <p class="text-xs text-gray-500 dark:text-slate-400">
            Use <code>*</code>
            to include nested keys (for example <code>breakdown.*</code>). Parent paths automatically expand when matching children exist.
          </p>
        </div>
      </div>

      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
          Chart Type
        </label>
        <div class="grid grid-cols-1 sm:max-w-xs mt-2">
          <select
            name="cat_chart_type"
            class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
          >
            <option value="bar" selected={@chart_type == "bar"}>Bar</option>
            <option value="pie" selected={@chart_type == "pie"}>Pie</option>
            <option value="donut" selected={@chart_type == "donut"}>Donut</option>
          </select>
          <svg
            viewBox="0 0 16 16"
            fill="currentColor"
            data-slot="icon"
            aria-hidden="true"
            class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4"
          >
            <path
              d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
              clip-rule="evenodd"
              fill-rule="evenodd"
            />
          </svg>
        </div>
      </div>
    </div>
    """
  end
end
