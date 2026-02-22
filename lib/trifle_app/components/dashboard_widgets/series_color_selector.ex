defmodule TrifleApp.Components.DashboardWidgets.SeriesColorSelector do
  @moduledoc false

  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias TrifleApp.Components.DashboardWidgets.Helpers
  alias TrifleApp.DesignSystem.ChartColors

  attr :name, :string, required: true
  attr :index, :integer, required: true
  attr :selector, :string, default: nil
  attr :id_prefix, :string, default: "series-color-selector"
  attr :class, :string, default: ""

  def input(assigns) do
    selector = Helpers.normalize_series_color_selector(Map.get(assigns, :selector))
    parsed = Helpers.parse_series_color_selector(selector)
    palettes = ChartColors.palette_options()
    preview_colors = selected_preview_colors(parsed, palettes)
    selected_label = selected_label(parsed, palettes)
    selected_custom_color = selected_custom_color(parsed)
    details_id = "#{assigns.id_prefix}-#{assigns.index}-details"

    assigns =
      assigns
      |> assign(:selector, selector)
      |> assign(:parsed, parsed)
      |> assign(:palettes, palettes)
      |> assign(:preview_colors, preview_colors)
      |> assign(:selected_label, selected_label)
      |> assign(:selected_custom_color, selected_custom_color)
      |> assign(:details_id, details_id)
      |> assign(:radio_name, "#{assigns.name}[#{assigns.index}]")

    ~H"""
    <div class={["relative", @class]}>
      <details
        id={@details_id}
        phx-click-away={JS.remove_attribute("open", to: "##{@details_id}")}
        class="group relative w-full [&_summary::-webkit-details-marker]:hidden"
      >
        <summary class="flex h-10 cursor-pointer list-none items-center justify-between gap-2 rounded-md border border-gray-300 bg-white px-2.5 text-sm text-gray-700 hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-100 dark:hover:bg-slate-600">
          <div class="min-w-0">
            <p class="truncate text-sm font-medium text-gray-800 dark:text-slate-100">
              {@selected_label}
            </p>
          </div>
          <div class="flex flex-shrink-0 items-center gap-1">
            <%= for color <- @preview_colors do %>
              <span
                class="inline-flex h-4 w-4 rounded-sm border border-white/70 shadow-sm dark:border-slate-900/40"
                style={"background-color: #{color}"}
              >
              </span>
            <% end %>
            <span class="ml-1 text-xs text-gray-500 transition group-open:rotate-180 dark:text-slate-300">
              ⌄
            </span>
          </div>
        </summary>

        <div class="absolute right-0 z-40 mt-2 inline-block w-max max-w-[85vw] rounded-lg border border-slate-200 bg-white p-2.5 shadow-xl dark:border-slate-700 dark:bg-slate-800">
          <div class="space-y-2">
            <p class="text-[11px] font-semibold uppercase tracking-wide text-gray-500 dark:text-slate-400">
              Palette & Color
            </p>

            <div class="max-h-72 w-max max-w-full space-y-1.5 overflow-y-auto pr-1">
              <%= for palette <- @palettes do %>
                <% rotate_value = "#{palette.id}.*" %>
                <% rotate_option_id = option_id(@id_prefix, @index, "rotate", palette.id, nil) %>
                <% palette_selected? = selected_palette?(@selector, palette.id) %>
                <div class={[
                  "grid w-max grid-cols-[5.75rem_auto] items-center gap-1.5 rounded-md border px-1.5 py-1 transition",
                  if(palette_selected?,
                    do: "border-teal-300 bg-teal-50/60 dark:border-teal-700 dark:bg-teal-950/20",
                    else: "border-slate-200 dark:border-slate-700"
                  )
                ]}>
                  <label for={rotate_option_id} class="block cursor-pointer">
                    <input
                      id={rotate_option_id}
                      type="radio"
                      name={@radio_name}
                      value={rotate_value}
                      checked={@selector == rotate_value}
                      class="peer sr-only"
                    />
                    <span class="inline-flex min-h-6 w-full items-center rounded-md border border-transparent px-1.5 py-1 text-xs font-medium text-gray-700 transition hover:bg-slate-100 peer-checked:border-teal-300 peer-checked:bg-teal-100/70 peer-checked:text-teal-900 dark:text-slate-200 dark:hover:bg-slate-700 dark:peer-checked:border-teal-700 dark:peer-checked:bg-teal-900/40 dark:peer-checked:text-teal-100">
                      {palette.label}
                    </span>
                  </label>

                  <div class="grid w-fit grid-cols-7 gap-1">
                    <%= for {color, color_index} <- Enum.with_index(palette.colors) do %>
                      <% single_value = "#{palette.id}.#{color_index}" %>
                      <% single_option_id =
                        option_id(@id_prefix, @index, "single", palette.id, color_index) %>
                      <label for={single_option_id} class="block cursor-pointer">
                        <input
                          id={single_option_id}
                          type="radio"
                          name={@radio_name}
                          value={single_value}
                          checked={@selector == single_value}
                          class="peer sr-only"
                        />
                        <span
                          class="relative block h-4 w-4 rounded-sm border border-transparent shadow-sm transition hover:scale-[1.04] peer-checked:border-white peer-checked:ring-2 peer-checked:ring-teal-500 dark:peer-checked:ring-teal-400"
                          style={"background-color: #{color}"}
                        >
                        </span>
                      </label>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%= if @selected_custom_color do %>
                <% custom_value = "custom.#{@selected_custom_color}" %>
                <% custom_id = option_id(@id_prefix, @index, "custom", "custom", nil) %>
                <div class="grid w-max grid-cols-[5.75rem_auto] items-center gap-1.5 rounded-md border border-slate-200 px-1.5 py-1 dark:border-slate-700">
                  <span class="inline-flex min-h-6 w-full items-center rounded-md px-1.5 py-1 text-xs font-medium text-gray-700 dark:text-slate-200">
                    Custom
                  </span>
                  <div class="grid w-fit grid-cols-7 gap-1">
                    <label for={custom_id} class="block cursor-pointer">
                      <input
                        id={custom_id}
                        type="radio"
                        name={@radio_name}
                        value={custom_value}
                        checked={@selector == custom_value}
                        class="peer sr-only"
                      />
                      <span
                        class="relative block h-4 w-4 rounded-sm border border-transparent shadow-sm transition hover:scale-[1.04] peer-checked:border-white peer-checked:ring-2 peer-checked:ring-teal-500 dark:peer-checked:ring-teal-400"
                        style={"background-color: #{@selected_custom_color}"}
                      >
                      </span>
                    </label>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </details>
    </div>
    """
  end

  defp selected_label(%{type: :palette_rotate, palette_id: palette_id}, palettes) do
    palette_label(palette_id, palettes)
  end

  defp selected_label(%{type: :single_palette, palette_id: palette_id, index: index}, palettes) do
    "#{palette_label(palette_id, palettes)} ##{index}"
  end

  defp selected_label(%{type: :single_custom, color: color}, _palettes), do: "Custom #{color}"

  defp selected_preview_colors(%{type: :palette_rotate, palette_id: palette_id}, palettes) do
    palette_colors(palette_id, palettes)
    |> Enum.take(3)
    |> fallback_preview()
  end

  defp selected_preview_colors(
         %{type: :single_palette, palette_id: palette_id, index: index},
         _palettes
       ) do
    case ChartColors.color_at(palette_id, index) do
      nil -> [ChartColors.primary()]
      color -> [color]
    end
  end

  defp selected_preview_colors(%{type: :single_custom, color: color}, _palettes), do: [color]

  defp selected_custom_color(%{type: :single_custom, color: color}), do: color
  defp selected_custom_color(_), do: nil

  defp palette_label(palette_id, palettes) do
    palettes
    |> Enum.find(fn palette -> palette.id == palette_id end)
    |> case do
      %{label: label} -> label
      _ -> "Default"
    end
  end

  defp palette_colors(palette_id, palettes) do
    palettes
    |> Enum.find(fn palette -> palette.id == palette_id end)
    |> case do
      %{colors: colors} -> colors
      _ -> ChartColors.palette()
    end
  end

  defp fallback_preview(colors) do
    case colors do
      [] -> [ChartColors.primary()]
      list -> list
    end
  end

  defp selected_palette?(selector, palette_id) do
    case Helpers.parse_series_color_selector(selector) do
      %{palette_id: id} -> id == palette_id
      _ -> false
    end
  end

  defp option_id(id_prefix, index, section, palette_id, color_index) do
    base = "#{id_prefix}-#{index}-#{section}-#{palette_id}"

    case color_index do
      nil -> base
      value -> "#{base}-#{value}"
    end
  end
end
