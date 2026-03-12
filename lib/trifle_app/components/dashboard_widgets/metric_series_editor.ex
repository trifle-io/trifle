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

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign(:rows, rows)

    ~H"""
    <div
      id={"widget-#{Map.get(@widget, "id")}-series"}
      phx-hook="WidgetSeriesRows"
      data-widget-id={Map.get(@widget, "id")}
      class="space-y-3"
    >
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div class="space-y-1">
          <h3 class="text-sm font-medium text-gray-900 dark:text-slate-100">
            {@title}
          </h3>
          <p class="text-xs text-gray-500 dark:text-slate-400">
            Compose path queries and formulas in evaluation order.
          </p>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <button
            type="button"
            data-action="add_query"
            class="inline-flex items-center gap-2 rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
          >
            <span class="text-base leading-none">+</span> Add Path
          </button>
          <button
            type="button"
            data-action="add_formula"
            class="inline-flex items-center gap-2 rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
          >
            <span class="text-xs font-semibold uppercase tracking-wide">fx</span> Add Formula
          </button>
        </div>
      </div>

      <div id={"widget-#{Map.get(@widget, "id")}-series-rows"} class="space-y-2">
        <%= for row <- @rows do %>
          <div
            id={"widget-series-row-#{Map.get(@widget, "id")}-#{row["index"]}"}
            data-series-row
            data-index={row["index"]}
            class={row_shell_classes()}
          >
            <div class="grid gap-3 xl:grid-cols-[auto_auto_minmax(0,1.5fr)_14rem_12rem_auto] xl:items-center">
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
                <span class={visibility_toggle_classes(:hidden)}>
                  <span class="sr-only">
                    Toggle series visibility
                  </span>
                  <.eye_slash_icon />
                </span>
                <span class={visibility_toggle_classes(:visible)}>
                  <span class="sr-only">
                    Toggle series visibility
                  </span>
                  <.eye_icon />
                </span>
              </label>

              <div class="flex min-w-0 items-center gap-2">
                <div class={row_badge_classes()}>
                  {String.upcase(row["row_letter"])}
                </div>

                <div class="inline-flex rounded-md border border-gray-300 bg-white p-0.5 shadow-sm dark:border-slate-600 dark:bg-slate-800">
                  <label class="cursor-pointer">
                    <input
                      type="radio"
                      name={input_name("widget_series_kind", row["index"])}
                      value="path"
                      data-role="series-kind"
                      checked={MetricSeries.path_row?(row)}
                      class="peer sr-only"
                    />
                    <span class={kind_segment_classes(:first)}>Path</span>
                  </label>
                  <label class="cursor-pointer">
                    <input
                      type="radio"
                      name={input_name("widget_series_kind", row["index"])}
                      value="expression"
                      data-role="series-kind"
                      checked={MetricSeries.expression_row?(row)}
                      class="peer sr-only"
                    />
                    <span class={kind_segment_classes(:last)}>Formula</span>
                  </label>
                </div>
              </div>

              <div class="min-w-0">
                <%= if MetricSeries.path_row?(row) do %>
                  <.path_autocomplete_input
                    id={"widget-series-path-#{Map.get(@widget, "id")}-#{row["index"]}"}
                    name={input_name("widget_series_path", row["index"])}
                    value={row["path"]}
                    placeholder={@path_placeholder}
                    path_options={@path_options}
                    input_class={input_classes()}
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
                    class={input_classes()}
                    placeholder="a / b"
                    spellcheck="false"
                  />
                  <input type="hidden" name={input_name("widget_series_path", row["index"])} value="" />
                <% end %>
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
                id_prefix={"widget-series-color-#{Map.get(@widget, "id")}"}
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

      <p class="text-xs text-gray-500 dark:text-slate-400">
        Formula rows use the same syntax as transponders and can reference previous rows as a, b,
        c, and so on.
      </p>

      <%= if @path_help do %>
        <p class="text-xs text-gray-500 dark:text-slate-400">
          {@path_help}
        </p>
      <% end %>
    </div>
    """
  end

  defp input_name(field, index), do: "#{field}[#{index}]"

  defp row_shell_classes do
    "rounded-lg border border-gray-200 bg-white px-3 py-3 dark:border-slate-700 dark:bg-slate-800"
  end

  defp row_badge_classes do
    "inline-flex h-8 min-w-[2rem] items-center justify-center rounded-md bg-gray-100 px-2 text-sm font-semibold text-gray-700 dark:bg-slate-700 dark:text-slate-100"
  end

  defp visibility_toggle_classes(state) do
    visibility =
      case state do
        :visible -> "hidden peer-checked:inline-flex"
        _ -> "inline-flex peer-checked:hidden"
      end

    Enum.join(
      [
        "h-10 w-10 items-center justify-center rounded-md border border-gray-300 bg-white text-gray-400 shadow-sm hover:bg-gray-50",
        "peer-checked:border-teal-500 peer-checked:bg-teal-50 peer-checked:text-teal-600",
        "dark:border-slate-600 dark:bg-slate-800 dark:text-slate-300 dark:hover:bg-slate-700",
        "dark:peer-checked:border-teal-400 dark:peer-checked:bg-slate-700 dark:peer-checked:text-teal-300",
        visibility
      ],
      " "
    )
  end

  defp remove_button_classes do
    "inline-flex h-10 w-10 items-center justify-center rounded-md border border-gray-300 bg-white text-gray-400 shadow-sm hover:bg-gray-50 hover:text-red-600 disabled:cursor-not-allowed disabled:opacity-40 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-300 dark:hover:bg-slate-700 dark:hover:text-red-400"
  end

  defp input_classes do
    "block h-10 w-full rounded-md border border-gray-300 bg-white px-3 text-sm text-gray-900 shadow-sm focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white"
  end

  defp kind_segment_classes(position) do
    base =
      "inline-flex items-center rounded-md px-3 py-2 text-xs font-medium transition"

    corners =
      case position do
        :first -> "rounded-r-none"
        :last -> "rounded-l-none"
        _ -> ""
      end

    state =
      "text-gray-600 hover:bg-gray-50 peer-checked:bg-gray-900 peer-checked:text-white dark:text-slate-300 dark:hover:bg-slate-700 dark:peer-checked:bg-slate-100 dark:peer-checked:text-slate-900"

    Enum.join([base, corners, state], " ")
  end

  attr :class, :string, default: "h-5 w-5"

  defp eye_icon(assigns) do
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
        d="M2.036 12.322a1.012 1.012 0 0 1 0-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178Z"
      />
      <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" />
    </svg>
    """
  end

  attr :class, :string, default: "h-5 w-5"

  defp eye_slash_icon(assigns) do
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
        d="M3.98 8.223A10.477 10.477 0 0 0 1.934 12C3.226 16.338 7.244 19.5 12 19.5c.993 0 1.953-.138 2.863-.395M6.228 6.228A10.451 10.451 0 0 1 12 4.5c4.756 0 8.773 3.162 10.065 7.498a10.522 10.522 0 0 1-4.293 5.774M6.228 6.228 3 3m3.228 3.228 3.65 3.65m7.894 7.894L21 21m-3.228-3.228-3.65-3.65m0 0a3 3 0 1 0-4.243-4.243m4.242 4.242L9.88 9.88"
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
