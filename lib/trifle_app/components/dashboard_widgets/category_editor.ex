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
        <input type="hidden" name="cat_chart_type" value={@chart_type} />
        <div class="inline-flex rounded-md shadow-sm border border-gray-200 dark:border-slate-600 overflow-hidden mt-2">
          <%= for {label, value, position} <- chart_type_options_cat() do %>
            <button
              type="button"
              class={chart_toggle_classes(@chart_type == value, position)}
              phx-click="set_cat_chart_type"
              phx-value-widget-id={Map.get(@widget, "id")}
              phx-value-chart-type={value}
            >
              {label}
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp chart_type_options_cat do
    [
      {"Bar", "bar", :first},
      {"Pie", "pie", :middle},
      {"Donut", "donut", :last}
    ]
  end

  defp chart_toggle_classes(selected, position) do
    base =
      "px-4 py-1.5 text-sm font-medium focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 transition min-w-[4.5rem] text-center"

    corners =
      case position do
        :first -> "rounded-l-md"
        :last -> "rounded-r-md"
        _ -> "border-x border-gray-200 dark:border-slate-600"
      end

    state =
      if selected do
        "bg-teal-600 text-white hover:bg-teal-500"
      else
        "bg-white text-gray-700 hover:bg-gray-50 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
      end

    Enum.join([base, corners, state], " ")
  end
end
