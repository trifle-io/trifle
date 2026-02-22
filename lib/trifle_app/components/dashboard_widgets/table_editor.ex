defmodule TrifleApp.Components.DashboardWidgets.TableEditor do
  @moduledoc false

  use Phoenix.Component

  import TrifleApp.Components.PathInput, only: [path_autocomplete_input: 1]

  alias TrifleApp.Components.DashboardWidgets.Helpers
  alias TrifleApp.Components.DashboardWidgets.SeriesColorSelector

  attr :widget, :map, required: true
  attr :path_options, :list, default: []

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})
    rows = Helpers.chart_path_rows(widget, "table")

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign(:rows, rows)

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
          <%= for row <- @rows do %>
            <div class="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_12rem_auto] gap-2 lg:items-start">
              <div class="min-w-0">
                <.path_autocomplete_input
                  id={"widget-table-path-#{Map.get(@widget, "id")}-#{row.index}"}
                  name="table_paths[]"
                  value={row.path_input}
                  placeholder="payment_methods.*"
                  path_options={@path_options}
                  input_class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
                />
              </div>
              <div>
                <SeriesColorSelector.input
                  id_prefix={"widget-table-color-#{Map.get(@widget, "id")}"}
                  name="table_color_selector"
                  index={row.index}
                  selector={row.selector}
                />
                <p class="mt-1 text-[11px] text-gray-500 dark:text-slate-400">
                  {wildcard_hint(row.wildcard, row.expanded_path)}
                </p>
              </div>
              <button
                type="button"
                data-action="remove"
                data-index={row.index}
                class="inline-flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-md bg-slate-200 text-slate-700 hover:bg-slate-300 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-slate-700 dark:text-slate-200 dark:hover:bg-slate-600"
                aria-label="Remove path"
                disabled={length(@rows) == 1}
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
    </div>
    """
  end

  defp wildcard_hint(:explicit, _expanded_path), do: "Wildcard path"
  defp wildcard_hint(:auto, expanded_path), do: "Auto-expanded to #{expanded_path}"
  defp wildcard_hint(:single, _expanded_path), do: "Single series path"
  defp wildcard_hint(_, _expanded_path), do: "Path pending"
end
