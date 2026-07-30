defmodule TrifleApp.Components.DashboardWidgets.KpiEditor do
  @moduledoc false

  use Phoenix.Component

  import TrifleApp.DesignSystem.ButtonGroup

  alias TrifleApp.Components.DashboardWidgets.Helpers
  alias TrifleApp.Components.DashboardWidgets.MetricSeriesEditor

  attr :widget, :map, required: true
  attr :path_options, :list, default: []
  attr :group_path, :string, default: nil

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})
    subtype = Helpers.normalize_kpi_subtype(Map.get(widget, "subtype"), widget)

    function =
      widget
      |> Map.get("function", "mean")
      |> to_string()
      |> case do
        "avg" -> "mean"
        other -> other
      end

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign(:widget_id, Map.get(widget, "id"))
      |> assign(:subtype, subtype)
      |> assign(:function, function)
      |> assign(:size, Map.get(widget, "size", "m"))
      |> assign(:unit, Map.get(widget, "unit", ""))
      |> assign(:diff_checked, !!Map.get(widget, "diff"))
      |> assign(:timeseries_checked, !!Map.get(widget, "timeseries"))
      |> assign(:goal_progress_checked, !!Map.get(widget, "goal_progress"))
      |> assign(:goal_invert_checked, !!Map.get(widget, "goal_invert"))

    ~H"""
    <input type="hidden" name="kpi_subtype" value={@subtype} />

    <div class="grid grid-cols-1 gap-4 xl:grid-cols-3">
      <div class="space-y-4 xl:col-span-2">
        <MetricSeriesEditor.editor
          widget={@widget}
          path_options={@path_options}
          group_path={@group_path}
          path_placeholder="metrics.total"
          path_help="KPI widgets display the first visible resolved series."
        />
      </div>

      <div class="space-y-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
            Function
          </label>
          <input type="hidden" name="kpi_function" value={@function} />
          <.button_group size="sm">
            <:button
              :for={{label, value} <- kpi_function_options()}
              phx-click="set_kpi_function"
              values={%{"widget-id" => @widget_id, "function" => value}}
              selected={@function == value}
              label={label}
            />
          </.button_group>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
            Display Mode
          </label>
          <.button_group size="sm">
            <:button
              :for={{label, value, help} <- kpi_subtype_options()}
              phx-click="change_kpi_subtype"
              values={%{"widget-id" => @widget_id, "kpi-subtype" => value}}
              selected={@subtype == value}
              label={label}
              tooltip={help}
            />
          </.button_group>
          <p class="mt-2 text-xs text-gray-500 dark:text-slate-400">
            {kpi_subtype_help(@subtype)}
          </p>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
            Widget size
          </label>
          <input type="hidden" name="kpi_size" value={@size} />
          <.button_group size="sm">
            <:button
              :for={{label, value, help} <- kpi_size_options()}
              phx-click="set_kpi_size"
              values={%{"widget-id" => @widget_id, "size" => value}}
              selected={@size == value}
              label={label}
              tooltip={help}
            />
          </.button_group>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
            Unit
          </label>
          <input
            type="text"
            name="kpi_unit"
            value={@unit}
            class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
            placeholder="e.g. minutes, requests, $"
          />
        </div>

        <%= if @subtype == "goal" do %>
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
              Target value
            </label>
            <input
              type="text"
              name="kpi_goal_target"
              value={Map.get(@widget, "goal_target", "")}
              class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
              placeholder="e.g. 1200"
            />
          </div>
        <% end %>

        <%= case @subtype do %>
          <% "split" -> %>
            <div class="space-y-2">
              <p class="text-sm text-gray-700 dark:text-slate-300">
                Split timeframe by half is enabled for this subtype.
              </p>
              <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
                <label
                  class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300"
                  title="Shows percent change between halves: (Now − Prev) / |Prev| × 100. Hidden when Prev is missing or zero."
                >
                  <input type="checkbox" name="kpi_diff" checked={@diff_checked} />
                  Difference between splits
                </label>
                <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
                  <input type="checkbox" name="kpi_timeseries" checked={@timeseries_checked} />
                  Show timeseries
                </label>
              </div>
            </div>
          <% "goal" -> %>
            <div class="space-y-2">
              <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
                <label
                  class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300"
                  title="Progress bar illustrates progress toward the target."
                >
                  <input type="checkbox" name="kpi_goal_progress" checked={@goal_progress_checked} />
                  Show progress bar
                </label>
                <label
                  class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300"
                  title="When inverted, staying at or below the target is considered success; exceeding it turns the progress indicator red."
                >
                  <input type="checkbox" name="kpi_goal_invert" checked={@goal_invert_checked} />
                  Invert goal (lower is better)
                </label>
              </div>
            </div>
          <% _ -> %>
            <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
              <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
                <input type="checkbox" name="kpi_timeseries" checked={@timeseries_checked} />
                Show timeseries
              </label>
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp kpi_function_options do
    [
      {"Mean", "mean"},
      {"Sum", "sum"},
      {"Max", "max"},
      {"Min", "min"},
      {"Oldest", "oldest"},
      {"Latest", "latest"}
    ]
  end

  defp kpi_subtype_options do
    [
      {"Number", "number", "Shows a single aggregate value."},
      {"Split", "split", "Compares the current timeframe to the previous half."},
      {"Goal", "goal", "Tracks progress toward a target value."}
    ]
  end

  defp kpi_subtype_help("split"), do: "Split compares the current timeframe to the previous half."
  defp kpi_subtype_help("goal"), do: "Goal lets you track progress toward a target."
  defp kpi_subtype_help(_), do: "Number shows a single aggregate."

  defp kpi_size_options do
    [
      {"S", "s", "Small"},
      {"M", "m", "Medium"},
      {"L", "l", "Large"}
    ]
  end
end
