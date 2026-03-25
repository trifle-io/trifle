defmodule TrifleApp.Components.DashboardWidgets.TimeseriesEditor do
  @moduledoc false

  use Phoenix.Component

  alias TrifleApp.Components.DashboardWidgets.MetricSeriesEditor
  alias TrifleApp.Components.DashboardWidgets.SeriesDisplayEditor

  attr :widget, :map, required: true
  attr :path_options, :list, default: []

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign(:chart_type, Map.get(widget, "chart_type", "line"))
      |> assign(:stacked, !!Map.get(widget, "stacked"))
      |> assign(:normalized, !!Map.get(widget, "normalized"))
      |> assign(:legend, !!Map.get(widget, "legend"))
      |> assign(:hovered_only, !!Map.get(widget, "hovered_only"))

    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
      <div class="sm:col-span-2">
        <MetricSeriesEditor.editor
          widget={@widget}
          path_options={@path_options}
          path_placeholder="metrics.sales"
          path_help="Use * to expand dynamic keys such as breakdown.*. Hidden source rows can feed visible expression rows."
        />
      </div>

      <div class="sm:col-span-2">
        <SeriesDisplayEditor.controls widget={@widget} />
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
        <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
          <input type="hidden" name="ts_hovered_only" value="false" />
          <input type="checkbox" name="ts_hovered_only" value="true" checked={@hovered_only} />
          Show only hovered series
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
end
