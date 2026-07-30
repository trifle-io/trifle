defmodule TrifleApp.Components.DashboardWidgets.ListEditor do
  @moduledoc false

  use Phoenix.Component

  alias TrifleApp.Components.DashboardWidgets.MetricSeriesEditor

  attr :widget, :map, required: true
  attr :path_options, :list, default: []
  attr :group_path, :string, default: nil

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign(:limit, Map.get(widget, "limit") || Map.get(widget, :limit))
      |> assign(:sort, Map.get(widget, "sort") || "desc")
      |> assign(:label_strategy, Map.get(widget, "label_strategy") || "short")

    ~H"""
    <div class="grid grid-cols-1 gap-4 xl:grid-cols-3">
      <div class="xl:col-span-2">
        <MetricSeriesEditor.editor
          widget={@widget}
          path_options={@path_options}
          group_path={@group_path}
          path_placeholder="keys.*"
          path_help="List widgets behave like category widgets."
        />
      </div>

      <div class="space-y-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
            Max Items
          </label>
          <input
            type="number"
            min="1"
            name="list_limit"
            value={@limit}
            class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
            placeholder="Unlimited"
          />
          <p class="mt-2 text-xs text-gray-500 dark:text-slate-400">
            Leave blank to show all items.
          </p>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
            Sort Order
          </label>
          <select
            name="list_sort"
            class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
          >
            <%= for {label, value} <- sort_options() do %>
              <option value={value} selected={@sort == value}>{label}</option>
            <% end %>
          </select>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
            Label Style
          </label>
          <select
            name="list_label_strategy"
            class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
          >
            <%= for {label, value} <- label_strategy_options() do %>
              <option value={value} selected={@label_strategy == value}>{label}</option>
            <% end %>
          </select>
          <p class="mt-2 text-xs text-gray-500 dark:text-slate-400">
            Show the full path or just the final segment.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp sort_options do
    [
      {"Value (desc)", "desc"},
      {"Value (asc)", "asc"},
      {"Name (A-Z)", "alpha"},
      {"Name (Z-A)", "alpha_desc"}
    ]
  end

  defp label_strategy_options do
    [
      {"Short label (last segment)", "short"},
      {"Full path", "full_path"}
    ]
  end
end
