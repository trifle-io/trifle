defmodule TrifleApp.Components.DashboardWidgets.SeriesDisplayEditor do
  @moduledoc false

  use Phoenix.Component

  alias TrifleApp.Components.DashboardWidgets.SeriesOrder

  attr :widget, :map, required: true

  def controls(assigns) do
    widget = Map.get(assigns, :widget, %{})

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign(
        :series_sort,
        SeriesOrder.normalize_mode(Map.get(widget, "series_sort"), "natural")
      )
      |> assign(:series_priority_text, SeriesOrder.priority_text(widget))

    ~H"""
    <div class="space-y-4 rounded-xl border border-gray-200 bg-white/40 px-4 py-4 dark:border-slate-700 dark:bg-slate-900/20">
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-[minmax(0,14rem)_minmax(0,1fr)] sm:items-start">
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
            Sorting
          </label>
          <input type="hidden" name="series_sort" value={@series_sort} />
          <div class="inline-flex rounded-md shadow-sm border border-gray-200 dark:border-slate-600 overflow-hidden mt-2">
            <%= for {label, value, position} <- sort_mode_options() do %>
              <button
                type="button"
                class={sort_toggle_classes(@series_sort == value, position)}
                phx-click="set_series_sort"
                phx-value-option={value}
                phx-value-widget-id={Map.get(@widget, "id")}
              >
                {label}
              </button>
            <% end %>
          </div>
          <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
            Natural order keeps numeric suffixes in human order instead of string order.
          </p>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
            Priority
          </label>
          <textarea
            name="series_priority"
            rows="2"
            class="mt-2 block w-full rounded-md border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm focus:border-teal-500 focus:outline-none focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-800 dark:text-white"
            placeholder="state.success,state.failure,state.warning"
          >{@series_priority_text}</textarea>
          <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
            Matching series render first in this order. You can use exact series names or leaf keys, one per line or comma-separated.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp sort_mode_options do
    [
      {"Natural", "natural", :first},
      {"Alphabetical", "alpha", :last}
    ]
  end

  defp sort_toggle_classes(selected, position) do
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
