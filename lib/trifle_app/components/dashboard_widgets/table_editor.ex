defmodule TrifleApp.Components.DashboardWidgets.TableEditor do
  @moduledoc false

  use Phoenix.Component

  import TrifleApp.Components.PathInput, only: [path_autocomplete_input: 1]

  alias TrifleApp.Components.DashboardWidgets.Helpers

  attr :widget, :map, required: true
  attr :path_options, :list, default: []

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})
    paths = Helpers.table_paths_for_form(widget)
    table_mode = Helpers.normalize_table_mode(Map.get(widget, "table_mode", "html"))

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign(:paths, paths)
      |> assign(:table_mode, table_mode)

    ~H"""
    <div class="space-y-4">
      <div
        id={"widget-#{Map.get(@widget, "id")}-table-paths"}
        phx-hook="CategoryPaths"
        data-widget-id={Map.get(@widget, "id")}
        data-path-input-name="table_paths[]"
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
                  id={"widget-table-path-#{Map.get(@widget, "id")}-#{index}"}
                  name="table_paths[]"
                  value={path}
                  placeholder="payment_methods.*"
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
          Provide a parent path (e.g., <code>payment_methods</code>
          or <code>payment_methods.*</code>). Matching children render in the table with the provided prefix removed so long names stay readable.
        </p>
      </div>

      <div class="space-y-1">
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300">
          Table Mode
        </label>
        <input type="hidden" name="table_mode" value={@table_mode} />
        <div class="inline-flex rounded-md shadow-sm border border-gray-200 dark:border-slate-600 overflow-hidden">
          <%= for {label, value, position} <- table_mode_options() do %>
            <button
              type="button"
              class={table_mode_button_classes(@table_mode == value, position)}
              phx-click="set_table_mode"
              phx-value-widget-id={Map.get(@widget, "id")}
              phx-value-mode={value}
            >
              {label}
            </button>
          <% end %>
        </div>
        <p class="text-xs text-gray-500 dark:text-slate-400">
          HTML mode keeps the Phoenix-rendered table. AG Grid uses the interactive JavaScript data grid for faster scrolling and sorting later on.
        </p>
      </div>
    </div>
    """
  end

  defp table_mode_options do
    [
      {"HTML Table", "html", :first},
      {"AG Grid", "aggrid", :last}
    ]
  end

  defp table_mode_button_classes(selected, position) do
    base =
      "px-4 py-1.5 text-sm font-medium focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 transition min-w-[6rem] text-center"

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
