defmodule TrifleApp.Components.DashboardWidgets.CategoryEditor do
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
      |> assign(:chart_type, Map.get(widget, "chart_type", "bar"))

    ~H"""
    <div class="grid grid-cols-1 gap-4 xl:grid-cols-3">
      <div class="space-y-4 xl:col-span-2">
        <MetricSeriesEditor.editor
          widget={@widget}
          path_options={@path_options}
          group_path={@group_path}
          path_placeholder="metrics.category.*"
          path_help="Use * to group dynamic category keys."
        />

        <SeriesDisplayEditor.controls widget={@widget} />
      </div>

      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
          Chart Type
        </label>
        <input type="hidden" name="cat_chart_type" value={@chart_type} />
        <.button_group size="sm">
          <:button
            :for={{label, value} <- chart_type_options_cat()}
            phx-click="set_cat_chart_type"
            values={%{"widget-id" => Map.get(@widget, "id"), "chart-type" => value}}
            selected={@chart_type == value}
            title={label}
            aria-label={label}
          >
            <.chart_type_icon type={value} />
          </:button>
        </.button_group>
      </div>
    </div>
    """
  end

  defp chart_type_options_cat do
    [
      {"Bar", "bar"},
      {"Pie", "pie"},
      {"Donut", "donut"}
    ]
  end

  attr :type, :string, required: true

  defp chart_type_icon(%{type: "bar"} = assigns), do: ~H"<EditorIcons.bar_chart_icon />"
  defp chart_type_icon(%{type: "pie"} = assigns), do: ~H"<EditorIcons.pie_chart_icon />"
  defp chart_type_icon(%{type: "donut"} = assigns), do: ~H"<EditorIcons.donut_chart_icon />"
end
