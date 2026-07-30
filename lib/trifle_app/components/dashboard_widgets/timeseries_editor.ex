defmodule TrifleApp.Components.DashboardWidgets.TimeseriesEditor do
  @moduledoc false

  use Phoenix.Component

  import TrifleApp.DesignSystem.ButtonGroup

  alias TrifleApp.Components.DashboardWidgets.EditorIcons
  alias TrifleApp.Components.DashboardWidgets.MetricSeriesEditor
  alias TrifleApp.Components.DashboardWidgets.SeriesDisplayEditor

  attr :widget, :map, required: true
  attr :path_options, :list, default: []
  attr :group_path, :string, default: nil

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
      |> assign(:annotations_enabled, annotations_enabled?(widget))

    ~H"""
    <div class="grid grid-cols-1 gap-4 xl:grid-cols-3">
      <div class="space-y-4 xl:col-span-2">
        <MetricSeriesEditor.editor
          widget={@widget}
          path_options={@path_options}
          group_path={@group_path}
          path_placeholder="metrics.sales"
          path_help="Use * to expand dynamic keys such as breakdown.*."
        />

        <SeriesDisplayEditor.controls widget={@widget} />
      </div>

      <div class="space-y-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
            Y-axis unit
          </label>
          <input
            type="text"
            name="ts_y_label"
            value={Map.get(@widget, "y_label", "")}
            class="block w-full rounded-md border-gray-300 bg-white text-gray-900 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-800 dark:text-white sm:text-sm"
            placeholder="e.g., $, Orders, Errors (%)"
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
            Chart Type
          </label>
          <input type="hidden" name="ts_chart_type" value={@chart_type} />
          <.button_group size="sm" labels="hidden">
            <:button
              :for={{label, value} <- chart_type_options_ts()}
              phx-click="set_ts_chart_type"
              values={%{"widget-id" => Map.get(@widget, "id"), "chart-type" => value}}
              selected={@chart_type == value}
              label={label}
            >
              <.chart_type_icon type={value} />
            </:button>
          </.button_group>
        </div>

        <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
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
          <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
            <input type="hidden" name="ts_annotations_enabled" value="false" />
            <input
              type="checkbox"
              name="ts_annotations_enabled"
              value="true"
              checked={@annotations_enabled}
            /> Annotations
          </label>
        </div>
      </div>
    </div>
    """
  end

  defp annotations_enabled?(widget) do
    case Map.get(widget, "annotations_enabled", true) do
      false -> false
      "false" -> false
      "0" -> false
      0 -> false
      _ -> true
    end
  end

  defp chart_type_options_ts do
    [
      {"Line", "line"},
      {"Area", "area"},
      {"Dots", "dots"},
      {"Bar", "bar"}
    ]
  end

  attr :type, :string, required: true

  defp chart_type_icon(%{type: "line"} = assigns), do: ~H"<EditorIcons.line_chart_icon />"
  defp chart_type_icon(%{type: "area"} = assigns), do: ~H"<EditorIcons.area_chart_icon />"
  defp chart_type_icon(%{type: "dots"} = assigns), do: ~H"<EditorIcons.scatter_chart_icon />"
  defp chart_type_icon(%{type: "bar"} = assigns), do: ~H"<EditorIcons.bar_chart_icon />"
end
