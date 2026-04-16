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
  attr :input_data_role, :string, default: nil
  attr :indexed_name, :boolean, default: true
  attr :allow_palette_rotate, :boolean, default: true
  attr :default_label, :string, default: nil
  attr :default_preview_colors, :list, default: []

  def input(assigns) do
    selector = normalize_selector(Map.get(assigns, :selector), assigns)
    parsed = if is_binary(selector), do: Helpers.parse_series_color_selector(selector), else: nil
    palettes = ChartColors.palette_options()
    preview_colors = selected_preview_colors(parsed, assigns.default_preview_colors, palettes)
    selected_label = selected_label(parsed, assigns.default_label, palettes)
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
      |> assign(:radio_name, radio_name(assigns))

    ~H"""
    <div class={["relative", @class]}>
      <details
        id={@details_id}
        phx-click-away={JS.remove_attribute("open", to: "##{@details_id}")}
        class="group relative w-full [&_summary::-webkit-details-marker]:hidden"
      >
        <summary class="flex h-10 cursor-pointer list-none items-center justify-between gap-2 rounded-md border border-gray-300 bg-white px-2.5 text-sm text-gray-700 shadow-sm hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100 dark:hover:bg-slate-700">
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
            <span class="ml-1 inline-flex h-4 w-4 items-center justify-center transition-transform duration-150 group-open:rotate-180">
              <svg
                viewBox="0 0 16 16"
                fill="currentColor"
                aria-hidden="true"
                class="h-4 w-4 text-gray-500 dark:text-slate-300"
              >
                <path
                  d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
                  clip-rule="evenodd"
                  fill-rule="evenodd"
                />
              </svg>
            </span>
          </div>
        </summary>

        <div class="absolute right-0 z-40 mt-2 inline-block min-w-full w-max max-w-[85vw] rounded-lg bg-white p-2.5 shadow-lg ring-1 ring-black/5 dark:bg-slate-800 dark:ring-white/10">
          <div class="space-y-2">
            <p class="text-[11px] font-semibold uppercase tracking-wide text-gray-500 dark:text-slate-400">
              Palette & Color
            </p>

            <div class="max-h-72 w-max max-w-full space-y-1.5 overflow-y-auto pr-1">
              <%= if @default_label do %>
                <% default_option_id = option_id(@id_prefix, @index, "default", "default", nil) %>
                <% default_selected? = is_nil(@selector) %>
                <div class={[
                  "grid w-max grid-cols-[5.75rem_auto] items-center gap-1.5 rounded-md border px-1.5 py-1 transition",
                  if(default_selected?,
                    do: "border-teal-300 bg-teal-50/60 dark:border-teal-700 dark:bg-teal-950/20",
                    else: "border-slate-200 dark:border-slate-700"
                  )
                ]}>
                  <label for={default_option_id} class="block cursor-pointer">
                    <input
                      id={default_option_id}
                      type="radio"
                      name={@radio_name}
                      value=""
                      checked={default_selected?}
                      data-role={@input_data_role}
                      class="peer sr-only"
                    />
                    <span class="inline-flex min-h-6 w-full items-center rounded-md border border-transparent px-1.5 py-1 text-xs font-medium text-gray-700 transition hover:bg-slate-100 peer-checked:border-teal-300 peer-checked:bg-teal-100/70 peer-checked:text-teal-900 dark:text-slate-200 dark:hover:bg-slate-700 dark:peer-checked:border-teal-700 dark:peer-checked:bg-teal-900/40 dark:peer-checked:text-teal-100">
                      {@default_label}
                    </span>
                  </label>

                  <div class="flex w-fit items-center gap-1">
                    <%= for color <- default_preview_colors(@default_preview_colors) do %>
                      <span
                        class="inline-flex h-4 w-4 rounded-sm border border-white/70 shadow-sm dark:border-slate-900/40"
                        style={"background-color: #{color}"}
                      >
                      </span>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%= for palette <- @palettes do %>
                <% rotate_value = "#{palette.id}.*" %>
                <% rotate_option_id = option_id(@id_prefix, @index, "rotate", palette.id, nil) %>
                <% palette_selected? = selected_palette?(@parsed, palette.id) %>
                <div class={[
                  "grid w-max grid-cols-[5.75rem_auto] items-center gap-1.5 rounded-md border px-1.5 py-1 transition",
                  if(palette_selected?,
                    do: "border-teal-300 bg-teal-50/60 dark:border-teal-700 dark:bg-teal-950/20",
                    else: "border-slate-200 dark:border-slate-700"
                  )
                ]}>
                  <%= if @allow_palette_rotate do %>
                    <label for={rotate_option_id} class="block cursor-pointer">
                      <input
                        id={rotate_option_id}
                        type="radio"
                        name={@radio_name}
                        value={rotate_value}
                        checked={@selector == rotate_value}
                        data-role={@input_data_role}
                        class="peer sr-only"
                      />
                      <span class="inline-flex min-h-6 w-full items-center rounded-md border border-transparent px-1.5 py-1 text-xs font-medium text-gray-700 transition hover:bg-slate-100 peer-checked:border-teal-300 peer-checked:bg-teal-100/70 peer-checked:text-teal-900 dark:text-slate-200 dark:hover:bg-slate-700 dark:peer-checked:border-teal-700 dark:peer-checked:bg-teal-900/40 dark:peer-checked:text-teal-100">
                        {palette.label}
                      </span>
                    </label>
                  <% else %>
                    <span class="inline-flex min-h-6 w-full items-center rounded-md px-1.5 py-1 text-xs font-medium text-gray-700 dark:text-slate-200">
                      {palette.label}
                    </span>
                  <% end %>

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
                          data-role={@input_data_role}
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
                        data-role={@input_data_role}
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

  defp selected_label(nil, default_label, _palettes) when is_binary(default_label),
    do: default_label

  defp selected_label(%{type: :palette_rotate, palette_id: palette_id}, _default_label, palettes) do
    palette_label(palette_id, palettes)
  end

  defp selected_label(
         %{type: :single_palette, palette_id: palette_id, index: index},
         _default_label,
         palettes
       ) do
    "#{palette_label(palette_id, palettes)} ##{index}"
  end

  defp selected_label(%{type: :single_custom, color: color}, _default_label, _palettes),
    do: "Custom #{color}"

  defp selected_preview_colors(nil, preview_colors, _palettes) do
    default_preview_colors(preview_colors)
  end

  defp selected_preview_colors(
         %{type: :palette_rotate, palette_id: palette_id},
         _preview_colors,
         palettes
       ) do
    palette_colors(palette_id, palettes)
    |> Enum.take(3)
    |> fallback_preview()
  end

  defp selected_preview_colors(
         %{type: :single_palette, palette_id: palette_id, index: index},
         _preview_colors,
         _palettes
       ) do
    case ChartColors.color_at(palette_id, index) do
      nil -> [ChartColors.primary()]
      color -> [color]
    end
  end

  defp selected_preview_colors(%{type: :single_custom, color: color}, _preview_colors, _palettes),
    do: [color]

  defp selected_custom_color(%{type: :single_custom, color: color}), do: color
  defp selected_custom_color(_), do: nil

  defp normalize_selector(selector, %{allow_palette_rotate: false, default_label: default_label})
       when is_binary(default_label) do
    case selector |> to_string() |> String.trim() do
      "" -> nil
      value -> Helpers.normalize_surface_color_selector(value)
    end
  end

  defp normalize_selector(selector, %{allow_palette_rotate: false}) do
    Helpers.normalize_surface_color_selector(selector) ||
      Helpers.normalize_series_color_selector(selector)
  end

  defp normalize_selector(selector, _assigns),
    do: Helpers.normalize_series_color_selector(selector)

  defp radio_name(%{indexed_name: true, name: name, index: index}), do: "#{name}[#{index}]"
  defp radio_name(%{name: name}), do: name

  defp default_preview_colors(colors) do
    case colors do
      [] -> [ChartColors.primary()]
      list -> list
    end
  end

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

  defp selected_palette?(%{palette_id: id}, palette_id), do: id == palette_id
  defp selected_palette?(_parsed, _palette_id), do: false

  defp option_id(id_prefix, index, section, palette_id, color_index) do
    base = "#{id_prefix}-#{index}-#{section}-#{palette_id}"

    case color_index do
      nil -> base
      value -> "#{base}-#{value}"
    end
  end
end
