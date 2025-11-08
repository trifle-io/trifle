defmodule TrifleApp.Components.DashboardWidgets.KpiEditor do
  @moduledoc false

  use Phoenix.Component

  import TrifleApp.Components.DashboardWidgets.PathInput, only: [path_autocomplete_input: 1]

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
            phx-value-widget_id={@widget_id}
            phx-value-kpi_subtype="number"
          >
            Number
          </button>
          <button
            type="button"
            class={subtype_button_classes(@subtype == "split", "border-x border-gray-200 dark:border-slate-600")}
            phx-click="change_kpi_subtype"
            phx-value-widget_id={@widget_id}
            phx-value-kpi_subtype="split"
          >
            Split
          </button>
          <button
            type="button"
            class={subtype_button_classes(@subtype == "goal", "rounded-r-md")}
            phx-click="change_kpi_subtype"
            phx-value-widget_id={@widget_id}
            phx-value-kpi_subtype="goal"
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
        <div class="grid grid-cols-1 sm:max-w-xs mt-2">
          <select
            name="kpi_function"
            class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
          >
            <option value="max" selected={@function == "max"}>max</option>
            <option value="min" selected={@function == "min"}>min</option>
            <option value="mean" selected={@function == "mean"}>mean</option>
            <option value="sum" selected={@function == "sum"}>sum</option>
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

      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
          Widget size
        </label>
        <div class="grid grid-cols-1 sm:max-w-xs mt-2">
          <select
            name="kpi_size"
            class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
          >
            <option value="s" selected={@size == "s"}>Small</option>
            <option value="m" selected={@size == "m"}>Medium</option>
            <option value="l" selected={@size == "l"}>Large</option>
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
end
