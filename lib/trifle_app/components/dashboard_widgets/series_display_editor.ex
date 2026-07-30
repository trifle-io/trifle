defmodule TrifleApp.Components.DashboardWidgets.SeriesDisplayEditor do
  @moduledoc false

  use Phoenix.Component

  import TrifleApp.DesignSystem.ButtonGroup

  alias TrifleApp.Components.DashboardWidgets.{SeriesAliases, SeriesOrder}

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
      |> assign(:series_priority_last_text, SeriesOrder.priority_last_text(widget))
      |> assign(:series_aliases_text, SeriesAliases.aliases_text(widget))
      |> assign(:series_aliases_error, SeriesAliases.aliases_error(widget))
      |> assign(:series_alias_rows, SeriesAliases.visual_rows(widget))
      |> assign(:series_priority_rows, SeriesOrder.priority_visual_rows(widget))
      |> assign(:series_display_mode, initial_display_mode(widget))
      |> assign(:advanced_attrs, advanced_attrs(widget))
      |> assign(:editor_dom_id, editor_dom_id(widget))

    ~H"""
    <details
      id={@editor_dom_id}
      phx-hook="SeriesDisplayEditor"
      data-series-display-editor
      {@advanced_attrs}
      class="rounded-xl border border-gray-200 bg-white/40 dark:border-slate-700 dark:bg-slate-900/20"
    >
      <summary class="cursor-pointer select-none px-4 py-3 text-sm font-medium text-gray-900 dark:text-slate-100">
        Advanced
      </summary>

      <div class="space-y-4 border-t border-gray-200 px-4 py-4 dark:border-slate-700">
        <input
          type="hidden"
          name="series_display_mode"
          value={@series_display_mode}
          data-role="series-display-mode"
        />

        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 class="text-sm font-medium text-gray-900 dark:text-slate-100">
              Aliases and Priority
            </h3>
            <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
              Aliases are applied before sorting and priority.
            </p>
          </div>

          <.button_group size="sm">
            <:button
              data-series-display-mode-button="visual"
              aria-pressed={to_string(@series_display_mode == "visual")}
              selected={@series_display_mode == "visual"}
              label="Visual"
            />
            <:button
              data-series-display-mode-button="raw"
              aria-pressed={to_string(@series_display_mode == "raw")}
              selected={@series_display_mode == "raw"}
              label="Raw"
            />
          </.button_group>
        </div>

        <div data-series-display-mode-panel="visual" hidden={@series_display_mode != "visual"}>
          <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
            <.aliases_visual_editor rows={@series_alias_rows} />
            <.priority_visual_editor rows={@series_priority_rows} />
          </div>
        </div>

        <div data-series-display-mode-panel="raw" hidden={@series_display_mode != "raw"}>
          <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
                Aliases
              </label>
              <textarea
                name="series_aliases"
                rows="5"
                data-role="series-aliases-raw"
                class={[
                  "block w-full rounded-md bg-white px-3 py-2 font-mono text-sm text-gray-900 shadow-sm focus:outline-none focus:ring-teal-500 dark:bg-slate-800 dark:text-white",
                  if(@series_aliases_error,
                    do: "border-rose-300 focus:border-rose-500 dark:border-rose-500",
                    else: "border-gray-300 focus:border-teal-500 dark:border-slate-600"
                  )
                ]}
                placeholder={~s({"US": "United States", "DE": "Germany"})}
              >{@series_aliases_text}</textarea>
              <p
                data-role="series-aliases-raw-error"
                hidden={is_nil(@series_aliases_error)}
                class="mt-1 text-xs text-rose-600 dark:text-rose-300"
              >
                {@series_aliases_error}
              </p>
              <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                JSON object for wildcard values.
              </p>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
                Priority First
              </label>
              <textarea
                name="series_priority"
                rows="5"
                data-role="series-priority-raw"
                class="block w-full rounded-md border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm focus:border-teal-500 focus:outline-none focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-800 dark:text-white"
                placeholder="United States,Germany"
              >{@series_priority_text}</textarea>
              <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                Matching series render first in this order after aliases are applied.
              </p>

              <label class="mt-4 block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
                Priority Last
              </label>
              <textarea
                name="series_priority_last"
                rows="5"
                data-role="series-priority-last-raw"
                class="block w-full rounded-md border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm focus:border-teal-500 focus:outline-none focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-800 dark:text-white"
                placeholder="Other,Unknown"
              >{@series_priority_last_text}</textarea>
              <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                Matching series render last in this order.
              </p>
            </div>
          </div>
        </div>

        <div class="border-t border-gray-200 pt-4 dark:border-slate-700">
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
            Sorting
          </label>
          <input type="hidden" name="series_sort" value={@series_sort} />
          <.button_group size="sm">
            <:button
              :for={{label, value} <- sort_mode_options()}
              phx-click="set_series_sort"
              phx_value_option={value}
              values={%{"widget-id" => Map.get(@widget, "id")}}
              selected={@series_sort == value}
              label={label}
            />
          </.button_group>
          <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
            Natural order keeps numeric suffixes in human order instead of string order.
          </p>
        </div>
      </div>
    </details>
    """
  end

  attr :rows, :list, required: true

  defp aliases_visual_editor(assigns) do
    ~H"""
    <div>
      <div class="mb-2 flex items-center justify-between gap-3">
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300">
          Aliases
        </label>
        <span class="text-xs text-gray-500 dark:text-slate-400">Wildcard value to display name</span>
      </div>

      <div
        data-role="series-aliases-list"
        class="overflow-hidden rounded-md border border-gray-200 bg-white dark:border-slate-700 dark:bg-slate-900/30"
      >
        <div class="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)_2.5rem] border-b border-gray-200 bg-gray-50 px-3 py-2 text-xs font-medium text-gray-500 dark:border-slate-700 dark:bg-slate-800/70 dark:text-slate-400">
          <span>Raw value</span>
          <span>Alias</span>
          <span class="sr-only">Actions</span>
        </div>

        <%= for row <- @rows do %>
          <.alias_visual_row row={row} />
        <% end %>
      </div>

      <template data-role="series-alias-row-template">
        <.alias_visual_row row={%{"index" => "__INDEX__", "key" => "", "value" => ""}} />
      </template>

      <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
        Use the wildcard capture, such as US, not the full path.
      </p>
    </div>
    """
  end

  attr :row, :map, required: true

  defp alias_visual_row(assigns) do
    ~H"""
    <div
      id={"series-alias-row-#{@row["index"]}"}
      data-alias-row
      data-index={@row["index"]}
      data-empty-row={row_empty?(@row, ["key", "value"])}
      class="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)_2.5rem] items-center gap-2 border-b border-gray-100 px-3 py-2 last:border-b-0 dark:border-slate-800"
    >
      <input
        type="text"
        name={"series_alias_key[#{@row["index"]}]"}
        value={@row["key"]}
        data-role="series-alias-key"
        class={visual_input_classes()}
        placeholder="US"
        spellcheck="false"
      />
      <input
        type="text"
        name={"series_alias_value[#{@row["index"]}]"}
        value={@row["value"]}
        data-role="series-alias-value"
        class={visual_input_classes()}
        placeholder="United States"
      />
      <button
        type="button"
        data-action="alias-remove"
        class={row_icon_button_classes()}
        aria-label="Remove alias"
      >
        <.remove_icon />
      </button>
    </div>
    """
  end

  attr :rows, :map, required: true

  defp priority_visual_editor(assigns) do
    ~H"""
    <div>
      <div class="mb-2 flex items-center justify-between gap-3">
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300">
          Priority
        </label>
        <span class="text-xs text-gray-500 dark:text-slate-400">Applied after aliases</span>
      </div>

      <div
        data-role="series-priority-list"
        class="overflow-hidden rounded-md border border-gray-200 bg-white dark:border-slate-700 dark:bg-slate-900/30"
      >
        <div class="grid grid-cols-[2rem_minmax(0,1fr)_auto] border-b border-gray-200 bg-gray-50 px-3 py-2 text-xs font-medium text-gray-500 dark:border-slate-700 dark:bg-slate-800/70 dark:text-slate-400">
          <span aria-hidden="true"></span>
          <span class="col-span-2">Series name</span>
        </div>

        <%= for row <- @rows.first do %>
          <.priority_visual_row row={row} />
        <% end %>

        <div
          data-priority-divider
          class="grid grid-cols-[2rem_minmax(0,1fr)_auto] items-center gap-2 border-b border-gray-100 bg-gray-50 px-3 py-2 text-xs font-medium text-gray-500 dark:border-slate-800 dark:bg-slate-800/50 dark:text-slate-400"
        >
          <span
            class="inline-flex h-8 w-8 items-center justify-center text-gray-400 dark:text-slate-500"
            aria-hidden="true"
          >
            --
          </span>
          <span>All other series</span>
          <span class="sr-only">Locked divider</span>
        </div>

        <%= for row <- @rows.last do %>
          <.priority_visual_row row={row} />
        <% end %>
      </div>

      <template data-role="series-priority-row-template">
        <.priority_visual_row row={%{"index" => "__INDEX__", "value" => "", "group" => "first"}} />
      </template>

      <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
        Drag rows above the divider to pin first, or below it to pin last.
      </p>
    </div>
    """
  end

  attr :row, :map, required: true

  defp priority_visual_row(assigns) do
    ~H"""
    <div
      id={"series-priority-row-#{@row["index"]}"}
      data-priority-row
      data-index={@row["index"]}
      data-empty-row={row_empty?(@row, ["value"])}
      data-priority-group={Map.get(@row, "group", "first")}
      class="grid grid-cols-[2rem_minmax(0,1fr)_auto] items-center gap-2 border-b border-gray-100 px-3 py-2 last:border-b-0 dark:border-slate-800"
    >
      <span
        data-priority-drag-handle
        class="inline-flex h-9 w-8 cursor-grab items-center justify-center rounded-md text-xs font-semibold text-gray-400 hover:bg-gray-50 hover:text-gray-600 dark:text-slate-500 dark:hover:bg-slate-800 dark:hover:text-slate-300"
        aria-hidden="true"
      >
        ::
      </span>
      <input
        type="text"
        name={"series_priority_item[#{@row["index"]}]"}
        value={@row["value"]}
        data-role="series-priority-value"
        class={visual_input_classes()}
        placeholder="United States"
        spellcheck="false"
      />
      <input
        type="hidden"
        name={"series_priority_group[#{@row["index"]}]"}
        value={Map.get(@row, "group", "first")}
        data-role="series-priority-group"
      />
      <button
        type="button"
        data-action="priority-remove"
        class={row_icon_button_classes()}
        aria-label="Remove priority"
      >
        <.remove_icon />
      </button>
    </div>
    """
  end

  defp sort_mode_options do
    [
      {"Natural", "natural"},
      {"Alphabetical", "alpha"}
    ]
  end

  defp visual_input_classes do
    "block h-9 w-full rounded-md border border-gray-300 bg-white px-2 text-sm text-gray-900 shadow-sm focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-800 dark:text-white"
  end

  defp row_icon_button_classes do
    "inline-flex h-9 w-9 items-center justify-center rounded-md border border-gray-300 bg-white text-gray-400 shadow-sm hover:bg-gray-50 hover:text-red-600 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-300 dark:hover:bg-slate-700 dark:hover:text-red-400"
  end

  defp row_empty?(row, fields) when is_map(row) do
    Enum.all?(fields, fn field ->
      row
      |> Map.get(field, "")
      |> to_string()
      |> String.trim()
      |> Kernel.==("")
    end)
  end

  defp initial_display_mode(widget) do
    case Map.get(widget, SeriesAliases.display_mode_key()) do
      "raw" -> "raw"
      "visual" -> "visual"
      _ -> if SeriesAliases.aliases_error(widget), do: "raw", else: "visual"
    end
  end

  defp advanced_attrs(widget) do
    if SeriesAliases.aliases_error(widget), do: %{open: true}, else: %{}
  end

  defp editor_dom_id(widget) do
    id =
      widget
      |> Map.get("id", Map.get(widget, :id, "series-display"))
      |> to_string()
      |> String.replace(~r/[^A-Za-z0-9_-]/, "-")

    "series-display-editor-#{id}"
  end

  defp remove_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 20 20"
      fill="currentColor"
      aria-hidden="true"
      class="h-4 w-4"
      data-row-remove-icon
    >
      <path
        fill-rule="evenodd"
        d="M4.293 4.293a1 1 0 0 1 1.414 0L10 8.586l4.293-4.293a1 1 0 1 1 1.414 1.414L11.414 10l4.293 4.293a1 1 0 0 1-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 0 1-1.414-1.414L8.586 10 4.293 5.707a1 1 0 0 1 0-1.414Z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end
end
