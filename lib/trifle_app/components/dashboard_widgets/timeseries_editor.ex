defmodule TrifleApp.Components.DashboardWidgets.TimeseriesEditor do
  @moduledoc false

  use Phoenix.Component

  import TrifleApp.Components.PathInput, only: [path_autocomplete_input: 1]

  alias TrifleApp.Components.DashboardWidgets.Helpers
  alias TrifleApp.Components.DashboardWidgets.SeriesColorSelector

  attr :widget, :map, required: true
  attr :path_options, :list, default: []

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})
    rows = Helpers.chart_path_rows(widget, "timeseries")

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign(:rows, rows)
      |> assign(:chart_type, Map.get(widget, "chart_type", "line"))
      |> assign(:stacked, !!Map.get(widget, "stacked"))
      |> assign(:normalized, !!Map.get(widget, "normalized"))
      |> assign(:legend, !!Map.get(widget, "legend"))

    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
      <div class="sm:col-span-2">
        <div
          id={"widget-#{Map.get(@widget, "id")}-timeseries-paths"}
          phx-hook="TimeseriesPaths"
          data-widget-id={Map.get(@widget, "id")}
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
                    id={"widget-ts-path-#{Map.get(@widget, "id")}-#{row.index}"}
                    name="ts_paths[]"
                    value={row.path_input}
                    placeholder="metrics.sales"
                    path_options={@path_options}
                    input_class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
                  />
                </div>
                <div>
                  <SeriesColorSelector.input
                    id_prefix={"widget-ts-color-#{Map.get(@widget, "id")}"}
                    name="ts_color_selector"
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
            Use <code>*</code>
            to include nested keys (for example <code>breakdown.*</code>). Parent paths automatically expand when matching children exist.
          </p>
        </div>
      </div>

      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
          Y-axis label
        </label>
        <input
          type="text"
          name="ts_y_label"
          value={Map.get(@widget, "y_label", "")}
          class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
          placeholder="e.g., Revenue ($), Orders, Errors (%)"
        />
      </div>

      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
          Chart Type
        </label>
        <input type="hidden" name="ts_chart_type" value={@chart_type} />
        <div class="inline-flex rounded-md shadow-sm border border-gray-200 dark:border-slate-600 overflow-hidden mt-2">
          <%= for {label, value, position} <- chart_type_options_ts() do %>
            <button
              type="button"
              class={chart_toggle_classes(@chart_type == value, position)}
              phx-click="set_ts_chart_type"
              phx-value-widget-id={Map.get(@widget, "id")}
              phx-value-chart-type={value}
            >
              {label}
            </button>
          <% end %>
        </div>
      </div>

      <div class="flex items-center gap-4 sm:col-span-2">
        <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
          <input type="checkbox" name="ts_stacked" checked={@stacked} /> Stacked
        </label>
        <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
          <input type="checkbox" name="ts_normalized" checked={@normalized} /> Normalized
        </label>
        <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
          <input type="checkbox" name="ts_legend" checked={@legend} /> Show legend
        </label>
      </div>
    </div>
    """
  end

  defp chart_type_options_ts do
    [
      {"Line", "line", :first},
      {"Area", "area", :middle},
      {"Dots", "dots", :middle},
      {"Bar", "bar", :last}
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

  defp wildcard_hint(:explicit, _expanded_path), do: "Wildcard path"
  defp wildcard_hint(:auto, expanded_path), do: "Auto-expanded to #{expanded_path}"
  defp wildcard_hint(:single, _expanded_path), do: "Single series path"
  defp wildcard_hint(_, _expanded_path), do: "Path pending"
end
