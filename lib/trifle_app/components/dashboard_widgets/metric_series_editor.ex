defmodule TrifleApp.Components.DashboardWidgets.MetricSeriesEditor do
  @moduledoc false

  use Phoenix.Component

  import TrifleApp.Components.PathInput, only: [path_autocomplete_input: 1]

  alias TrifleApp.Components.DashboardWidgets.{MetricSeries, SeriesColorSelector}

  attr :widget, :map, required: true
  attr :path_options, :list, default: []
  attr :path_placeholder, :string, default: "metrics.total"
  attr :path_help, :string, default: nil
  attr :title, :string, default: "Series"

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})
    rows = MetricSeries.rows_for_form(widget, Map.get(assigns, :path_options, []))
    widget_id = widget_id(widget)

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign(:rows, rows)
      |> assign(:widget_id, widget_id)

    ~H"""
    <div
      id={"widget-#{@widget_id}-series"}
      phx-hook="WidgetSeriesRows"
      data-widget-id={@widget_id}
      class="space-y-3"
    >
      <div class="space-y-1">
        <h3 class="text-sm font-medium text-gray-900 dark:text-slate-100">
          {@title}
        </h3>
        <p class="text-xs text-gray-500 dark:text-slate-400">
          Compose path queries and formulas in evaluation order.
        </p>
      </div>

      <div id={"widget-#{@widget_id}-series-rows"} class="space-y-2">
        <%= for row <- @rows do %>
          <div
            id={"widget-series-row-#{@widget_id}-#{row["index"]}"}
            data-series-row
            data-index={row["index"]}
            class={row_shell_classes()}
          >
            <div class="grid gap-3 xl:grid-cols-[auto_minmax(0,1.6fr)_14rem_12rem_auto] xl:items-center">
              <label class="inline-flex">
                <input
                  type="hidden"
                  name={input_name("widget_series_visible", row["index"])}
                  value="false"
                />
                <input
                  type="checkbox"
                  name={input_name("widget_series_visible", row["index"])}
                  value="true"
                  data-role="series-visible"
                  checked={MetricSeries.visible?(row)}
                  class="peer sr-only"
                />
                <span class={visibility_toggle_classes()}>
                  <span class="sr-only">Toggle series visibility</span>
                  {row["row_letter"]}
                </span>
              </label>

              <div class="min-w-0">
                <div class={series_input_shell_classes()}>
                  <label class={kind_icon_classes(MetricSeries.path_row?(row))}>
                    <input
                      type="radio"
                      name={input_name("widget_series_kind", row["index"])}
                      value="path"
                      aria-label="Path series"
                      data-role="series-kind"
                      checked={MetricSeries.path_row?(row)}
                      class="sr-only"
                    />
                    <span class="sr-only">Path series</span>
                    <.path_icon />
                  </label>
                  <label class={kind_icon_classes(MetricSeries.expression_row?(row))}>
                    <input
                      type="radio"
                      name={input_name("widget_series_kind", row["index"])}
                      value="expression"
                      aria-label="Expression series"
                      data-role="series-kind"
                      checked={MetricSeries.expression_row?(row)}
                      class="sr-only"
                    />
                    <span class="sr-only">Expression series</span>
                    <.formula_icon />
                  </label>
                  <div class={shell_divider_classes()}></div>

                  <div class="min-w-0 flex-1">
                    <%= if MetricSeries.path_row?(row) do %>
                      <.path_autocomplete_input
                        id={"widget-series-path-#{@widget_id}-#{row["index"]}"}
                        name={input_name("widget_series_path", row["index"])}
                        value={row["path"]}
                        placeholder={@path_placeholder}
                        path_options={@path_options}
                        annotated={true}
                        preview_class={path_preview_classes()}
                        wrapper_class="relative z-20"
                        input_class={joined_input_classes()}
                      />
                      <input
                        type="hidden"
                        name={input_name("widget_series_expression", row["index"])}
                        value=""
                      />
                    <% else %>
                      <input
                        type="text"
                        name={input_name("widget_series_expression", row["index"])}
                        value={row["expression"]}
                        data-role="series-expression"
                        class={joined_input_classes()}
                        placeholder="a / b"
                        spellcheck="false"
                      />
                      <input
                        type="hidden"
                        name={input_name("widget_series_path", row["index"])}
                        value=""
                      />
                    <% end %>
                  </div>
                </div>
              </div>

              <input
                type="text"
                name={input_name("widget_series_label", row["index"])}
                value={row["label"]}
                data-role="series-label"
                class={input_classes()}
                placeholder="Alias"
              />

              <SeriesColorSelector.input
                id_prefix={"widget-series-color-#{@widget_id}"}
                name="widget_series_color_selector"
                index={row["index"]}
                selector={row["selector"]}
                class="w-full"
              />

              <button
                type="button"
                data-action="remove"
                data-index={row["index"]}
                class={remove_button_classes()}
                aria-label="Remove series"
                disabled={length(@rows) == 1}
              >
                <.remove_icon />
              </button>
            </div>
          </div>
        <% end %>
      </div>

      <button
        type="button"
        data-action="add_query"
        class="inline-flex items-center gap-2 rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
      >
        <span class="text-base leading-none">+</span> Add Series
      </button>

      <p class="text-xs text-gray-500 dark:text-slate-400">
        {@path_help ||
          "Use * to expand dynamic keys such as breakdown.*. Formula rows reference previous rows as a, b, c and use the same syntax as transponders. Hidden source rows can feed visible expression rows."}
      </p>
    </div>
    """
  end

  defp input_name(field, index), do: "#{field}[#{index}]"

  defp widget_id(widget) when is_map(widget) do
    widget
    |> Map.get(:id, Map.get(widget, "id", ""))
    |> to_string()
  end

  defp widget_id(_), do: ""

  defp row_shell_classes do
    "rounded-lg border border-gray-200 bg-white px-3 py-3 dark:border-slate-700 dark:bg-slate-800"
  end

  defp visibility_toggle_classes do
    Enum.join(
      [
        "inline-flex h-10 w-10 items-center justify-center rounded-md border border-gray-300 bg-white text-sm font-semibold lowercase text-gray-500 shadow-sm hover:bg-gray-50",
        "peer-checked:border-teal-500 peer-checked:bg-teal-50 peer-checked:text-teal-700",
        "dark:border-slate-600 dark:bg-slate-800 dark:text-slate-300 dark:hover:bg-slate-700",
        "dark:peer-checked:border-teal-400 dark:peer-checked:bg-slate-700 dark:peer-checked:text-teal-300"
      ],
      " "
    )
  end

  defp remove_button_classes do
    "inline-flex h-10 w-10 items-center justify-center rounded-md border border-gray-300 bg-white text-gray-400 shadow-sm hover:bg-gray-50 hover:text-red-600 disabled:cursor-not-allowed disabled:opacity-40 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-300 dark:hover:bg-slate-700 dark:hover:text-red-400"
  end

  defp input_classes do
    "block h-10 w-full rounded-md border border-gray-300 bg-white px-3 text-sm text-gray-900 focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white"
  end

  defp series_input_shell_classes do
    "flex h-10 min-w-0 items-center rounded-md border border-gray-300 bg-white transition-colors focus-within:border-teal-500 focus-within:ring-1 focus-within:ring-teal-500 dark:border-slate-600 dark:bg-slate-700"
  end

  defp shell_divider_classes do
    "ml-2.5 h-5 w-px bg-gray-200 dark:bg-slate-600"
  end

  defp joined_input_classes do
    "block h-full w-full !rounded-none !border-0 !bg-transparent px-3 py-2 text-sm text-gray-900 !shadow-none placeholder:text-gray-400 focus:!border-0 focus:!outline-none focus:!ring-0 focus:!shadow-none dark:text-white dark:placeholder:text-slate-400"
  end

  defp path_preview_classes do
    "flex items-center overflow-hidden whitespace-nowrap px-3 py-2 text-sm text-gray-900 dark:text-white"
  end

  defp kind_icon_classes(active?) do
    base =
      "inline-flex shrink-0 items-center justify-center cursor-pointer transition-colors first:pl-3 pl-1.5"

    color =
      if active?,
        do: "text-teal-600 dark:text-teal-400",
        else: "text-gray-400 hover:text-gray-600 dark:text-slate-500 dark:hover:text-slate-300"

    "#{base} #{color}"
  end

  defp path_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      class="h-5 w-5"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M2.25 18 9 11.25l4.306 4.306a11.95 11.95 0 0 1 5.814-5.518l2.74-1.22m0 0-5.94-2.281m5.94 2.28-2.28 5.941"
      />
    </svg>
    """
  end

  defp formula_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      class="h-5 w-5"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M4.745 3A23.933 23.933 0 0 0 3 12c0 3.183.62 6.22 1.745 9M19.5 3c.967 2.78 1.5 5.817 1.5 9s-.533 6.22-1.5 9M8.25 8.885l1.444-.89a.75.75 0 0 1 1.105.402l2.402 7.206a.75.75 0 0 0 1.104.401l1.445-.889m-8.25.75.213.09a1.687 1.687 0 0 0 2.062-.617l4.45-6.676a1.688 1.688 0 0 1 2.062-.618l.213.09"
      />
    </svg>
    """
  end

  attr :class, :string, default: "h-5 w-5"

  defp remove_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      class={@class}
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="m9.75 9.75 4.5 4.5m0-4.5-4.5 4.5M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
      />
    </svg>
    """
  end
end
