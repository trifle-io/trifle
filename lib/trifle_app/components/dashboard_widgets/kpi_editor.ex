defmodule TrifleApp.Components.DashboardWidgets.KpiEditor do
  @moduledoc false

  use Phoenix.Component

  import TrifleApp.Components.PathInput, only: [path_autocomplete_input: 1]

  alias TrifleApp.Components.DashboardWidgets.Helpers

  attr :widget, :map, required: true
  attr :path_options, :list, default: []

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
      |> assign(:diff_checked, !!Map.get(widget, "diff"))
      |> assign(:timeseries_checked, !!Map.get(widget, "timeseries"))
      |> assign(:goal_progress_checked, !!Map.get(widget, "goal_progress"))
      |> assign(:goal_invert_checked, !!Map.get(widget, "goal_invert"))

    ~H"""
    <input type="hidden" name="kpi_subtype" value={@subtype} />

    <div class="space-y-4">
      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
          Display Mode
        </label>
        <div class="inline-flex rounded-md shadow-sm border border-gray-200 dark:border-slate-600 overflow-hidden">
          <button
            type="button"
            class={subtype_button_classes(@subtype == "number", "rounded-l-md")}
            phx-click="change_kpi_subtype"
            phx-value-widget-id={@widget_id}
            phx-value-kpi-subtype="number"
          >
            Number
          </button>
          <button
            type="button"
            class={
              subtype_button_classes(
                @subtype == "split",
                "border-x border-gray-200 dark:border-slate-600"
              )
            }
            phx-click="change_kpi_subtype"
            phx-value-widget-id={@widget_id}
            phx-value-kpi-subtype="split"
          >
            Split
          </button>
          <button
            type="button"
            class={subtype_button_classes(@subtype == "goal", "rounded-r-md")}
            phx-click="change_kpi_subtype"
            phx-value-widget-id={@widget_id}
            phx-value-kpi-subtype="goal"
          >
            Goal
          </button>
        </div>
        <p class="mt-2 text-xs text-gray-500 dark:text-slate-400">
          Number shows a single aggregate. Split compares the current timeframe to the previous half. Goal lets you track progress toward a target.
        </p>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div class="sm:col-span-2">
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
            Path
          </label>
          <.path_autocomplete_input
            id="widget-kpi-path"
            name="kpi_path"
            value={Map.get(@widget, "path", "")}
            placeholder="e.g. sales.total"
            path_options={@path_options}
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
            Function
          </label>
          <input type="hidden" name="kpi_function" value={@function} />
          <div class="inline-flex rounded-md shadow-sm border border-gray-200 dark:border-slate-600 overflow-hidden mt-2">
            <%= for {label, value, position} <- kpi_function_options() do %>
              <button
                type="button"
                class={kpi_toggle_classes(@function == value, position)}
                phx-click="set_kpi_function"
                phx-value-widget-id={@widget_id}
                phx-value-function={value}
              >
                {label}
              </button>
            <% end %>
          </div>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
            Widget size
          </label>
          <input type="hidden" name="kpi_size" value={@size} />
          <div class="inline-flex rounded-md shadow-sm border border-gray-200 dark:border-slate-600 overflow-hidden mt-2">
            <%= for {label, value, position} <- kpi_size_options() do %>
              <button
                type="button"
                class={kpi_toggle_classes(@size == value, position)}
                phx-click="set_kpi_size"
                phx-value-widget-id={@widget_id}
                phx-value-size={value}
              >
                {label}
              </button>
            <% end %>
          </div>
        </div>

        <%= if @subtype == "goal" do %>
          <div class="sm:col-span-2">
            <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
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
      </div>
    </div>

    <%= case @subtype do %>
      <% "split" -> %>
        <div class="space-y-2">
          <p class="text-sm text-gray-700 dark:text-slate-300">
            Split timeframe by half is enabled for this subtype.
          </p>
          <div class="flex flex-wrap items-center gap-4">
            <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
              <input type="checkbox" name="kpi_diff" checked={@diff_checked} />
              Difference between splits
            </label>
            <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
              <input type="checkbox" name="kpi_timeseries" checked={@timeseries_checked} />
              Show timeseries
            </label>
          </div>
          <p class="text-xs text-gray-500 dark:text-slate-400">
            Shows percent change between halves: (Now − Prev) / |Prev| × 100. Hidden when Prev is missing or zero.
          </p>
        </div>
      <% "goal" -> %>
        <div class="space-y-2">
          <div class="flex flex-wrap items-center gap-4">
            <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
              <input type="checkbox" name="kpi_goal_progress" checked={@goal_progress_checked} />
              Show progress bar
            </label>
            <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
              <input type="checkbox" name="kpi_goal_invert" checked={@goal_invert_checked} />
              Invert goal (lower is better)
            </label>
          </div>
          <p class="text-xs text-gray-500 dark:text-slate-400">
            Progress bar illustrates progress toward the target.
          </p>
          <p class="text-xs text-gray-500 dark:text-slate-400">
            When inverted, staying at or below the target is considered success; exceeding it turns the progress indicator red.
          </p>
        </div>
      <% _ -> %>
        <div class="flex items-center gap-4">
          <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
            <input type="checkbox" name="kpi_timeseries" checked={@timeseries_checked} />
            Show timeseries
          </label>
        </div>
    <% end %>
    """
  end

  defp subtype_button_classes(selected, extra_class) do
    base =
      "px-4 py-1.5 text-sm font-medium focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 transition min-w-[4.5rem]"

    state_classes =
      if selected do
        "bg-teal-600 text-white hover:bg-teal-500"
      else
        "bg-white text-gray-700 hover:bg-gray-50 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
      end

    Enum.join([base, state_classes, extra_class], " ")
  end

  defp kpi_function_options do
    [
      {"Mean", "mean", :first},
      {"Sum", "sum", :middle},
      {"Max", "max", :middle},
      {"Min", "min", :last}
    ]
  end

  defp kpi_size_options do
    [
      {"S", "s", :first},
      {"M", "m", :middle},
      {"L", "l", :last}
    ]
  end

  defp kpi_toggle_classes(selected, position) do
    base =
      "px-4 py-1.5 text-sm font-medium focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 transition min-w-[3.5rem] text-center"

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
