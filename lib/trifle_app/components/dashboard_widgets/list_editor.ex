defmodule TrifleApp.Components.DashboardWidgets.ListEditor do
  @moduledoc false

  use Phoenix.Component

  import TrifleApp.Components.PathInput, only: [path_autocomplete_input: 1]

  alias TrifleApp.Components.DashboardWidgets.Helpers
  alias TrifleApp.Components.DashboardWidgets.SeriesColorSelector

  attr :widget, :map, required: true
  attr :path_options, :list, default: []

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})
    path = Map.get(widget, "path") || Map.get(widget, :path) || ""
    normalized_path = path |> to_string() |> String.trim()

    selectors =
      widget
      |> Map.get("series_color_selectors", %{})
      |> Helpers.normalize_series_color_selectors_map()

    color_selector = Helpers.selector_for_path(selectors, normalized_path)

    path_wildcard =
      cond do
        normalized_path == "" -> :unknown
        String.contains?(normalized_path, "*") -> :wildcard
        true -> :single
      end

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign(:path, path)
      |> assign(:limit, Map.get(widget, "limit") || Map.get(widget, :limit))
      |> assign(:sort, Map.get(widget, "sort") || "desc")
      |> assign(:label_strategy, Map.get(widget, "label_strategy") || "short")
      |> assign(:color_selector, color_selector)
      |> assign(:path_wildcard, path_wildcard)

    ~H"""
    <div class="space-y-5">
      <div class="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_12rem] gap-2 lg:items-start">
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300">
            Path
          </label>
          <.path_autocomplete_input
            id={"widget-list-path-#{Map.get(@widget, "id")}"}
            name="list_path"
            value={@path}
            placeholder="keys.*"
            path_options={@path_options}
            input_class="mt-1 block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
          />
          <p class="mt-2 text-xs text-gray-500 dark:text-slate-400">
            Provide a map path (e.g. <code>keys</code> or <code>metrics.by_country</code>).
            Child keys are automatically detected and summed for the selected timeframe.
          </p>
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300">
            Color
          </label>
          <SeriesColorSelector.input
            id_prefix={"widget-list-color-#{Map.get(@widget, "id")}"}
            name="list_color_selector"
            index={0}
            selector={@color_selector}
          />
          <p class="mt-1 text-[11px] text-gray-500 dark:text-slate-400">
            {wildcard_hint(@path_wildcard)}
          </p>
        </div>
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300">
            Max Items
          </label>
          <input
            type="number"
            min="1"
            name="list_limit"
            value={@limit}
            class="mt-1 block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
            placeholder="Unlimited"
          />
          <p class="mt-2 text-xs text-gray-500 dark:text-slate-400">
            Leave blank to show all items. Set a value to limit visible rows.
          </p>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300">
            Sort Order
          </label>
          <select
            name="list_sort"
            class="mt-1 block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
          >
            <%= for {label, value} <- sort_options() do %>
              <option value={value} selected={@sort == value}>{label}</option>
            <% end %>
          </select>
        </div>
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300">
            Label Style
          </label>
          <select
            name="list_label_strategy"
            class="mt-1 block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
          >
            <%= for {label, value} <- label_strategy_options() do %>
              <option value={value} selected={@label_strategy == value}>{label}</option>
            <% end %>
          </select>
          <p class="mt-2 text-xs text-gray-500 dark:text-slate-400">
            Choose whether to display the full path or just the final segment (default).
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

  defp wildcard_hint(:wildcard), do: "Wildcard path"
  defp wildcard_hint(:single), do: "Single series path"
  defp wildcard_hint(_), do: "Path pending"
end
