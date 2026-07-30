defmodule TrifleApp.DesignSystem.ButtonGroup do
  use Phoenix.Component

  @doc """
  Renders a labeled button group with consistent styling.

  Every button has a stable `label` and may provide icon markup as its slot
  content. The group-level `labels` attribute controls how labels behave:

    * `"visible"` (default) — label text is always rendered
    * `"hidden"` — icon-only buttons; the label becomes a JS tooltip
    * `"responsive"` — label text shows from the `md` breakpoint up; below
      it the label becomes a JS tooltip

  An explicit `tooltip` overrides the automatic label tooltip and is shown at
  every breakpoint. The legacy `title` and `data-tooltip` attributes remain
  supported as tooltip aliases, but the component always renders the shared JS
  tooltip rather than a native browser tooltip.

  Tooltips are rendered by the globally delegated fast-tooltip listener, so
  no wrapper hook is needed.

  ## Examples

      <.button_group labels="hidden">
        <:button phx-click="set_type" label="Line" selected={@type == "line"}>
          <.line_chart_icon />
        </:button>
        <:button phx-click="set_type" label="Bar" selected={@type == "bar"}>
          <.bar_chart_icon />
        </:button>
      </.button_group>

      <.button_group label="Options">
        <:button
          phx-click="select"
          phx-value-option="1"
          label="Option 1"
          selected={@current == "1"}
        />
        <:button
          phx-click="select"
          phx-value-option="2"
          label="Option 2"
          selected={@current == "2"}
        />
      </.button_group>
  """
  attr :label, :string, default: nil
  attr :class, :string, default: ""
  attr :size, :string, default: "md", values: ["md", "sm", "lg"]
  attr :labels, :string, default: "visible", values: ["visible", "hidden", "responsive"]

  slot :button, required: true do
    attr :"phx-click", :string
    attr :phx_click, :string
    attr :"phx-target", :any
    attr :phx_target, :any
    attr :phx_value_option, :string
    attr :phx_value_widget_id, :string
    attr :phx_value_granularity, :string
    attr :values, :map
    attr :label, :string, required: true
    attr :tooltip, :string
    attr :tooltip_placement, :string, values: ["top", "right"]
    attr :title, :string
    attr :class, :string
    attr :"aria-label", :string
    attr :"aria-pressed", :string
    attr :"data-tooltip", :string
    attr :"data-tooltip-media", :string
    attr :"data-tooltip-placement", :string
    attr :"data-filter-bar-action", :string
    attr :"data-filter-bar-granularity", :string
    attr :"data-series-display-mode-button", :string
    attr :selected, :boolean
    attr :disabled, :boolean
  end

  def button_group(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <label
        :if={@label}
        class="absolute -top-2 left-2 inline-block filter-field-label px-1 text-xs font-medium text-gray-900 dark:text-white z-10"
      >
        {@label}
      </label>
      <div
        class="inline-flex rounded-md bg-white ring-1 ring-black/10 backdrop-blur-xl dark:bg-slate-800/80 dark:ring-white/10"
        role="group"
        aria-label={@label}
      >
        <%= for {button, index} <- Enum.with_index(@button) do %>
          <% position =
            cond do
              length(@button) == 1 -> :only
              index == 0 -> :first
              index == length(@button) - 1 -> :last
              true -> :middle
            end %>

          <button
            type="button"
            {button_attributes(button)}
            class={button_classes(button, position, @size)}
            aria-label={button_aria_label(button)}
            aria-pressed={button_aria_pressed(button)}
            data-tooltip={button_tooltip(button, @labels)}
            data-tooltip-media={button_tooltip_media(button, @labels)}
            data-tooltip-placement={button_tooltip_placement(button)}
            data-series-display-mode-button={button[:"data-series-display-mode-button"]}
          >
            <span class={button_content_classes(@size)}>
              <%= if button[:inner_block] do %>
                {render_slot(button)}
              <% end %>
              <span :if={@labels != "hidden"} class={button_label_classes(@size, @labels)}>
                {button[:label]}
              </span>
            </span>
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  defp button_tooltip(button, labels) do
    cond do
      button[:tooltip] -> button[:tooltip]
      button[:"data-tooltip"] -> button[:"data-tooltip"]
      button[:title] -> button[:title]
      labels in ["hidden", "responsive"] -> button[:label]
      true -> nil
    end
  end

  defp button_tooltip_media(button, labels) do
    cond do
      button[:"data-tooltip-media"] -> button[:"data-tooltip-media"]
      explicit_tooltip?(button) -> nil
      labels == "responsive" -> "(max-width: 767px)"
      true -> nil
    end
  end

  defp explicit_tooltip?(button),
    do: !!(button[:tooltip] || button[:"data-tooltip"] || button[:title])

  defp button_tooltip_placement(button),
    do: button[:tooltip_placement] || button[:"data-tooltip-placement"]

  defp button_aria_label(button), do: button[:"aria-label"] || button[:label]

  defp button_aria_pressed(button) do
    case button[:"aria-pressed"] do
      nil ->
        if Map.has_key?(button, :selected), do: to_string(!!button[:selected])

      aria_pressed ->
        aria_pressed
    end
  end

  defp button_content_classes("lg"), do: "flex flex-col items-center gap-1.5"
  defp button_content_classes(_size), do: "inline-flex items-center gap-1.5"

  defp button_label_classes(size, labels) do
    [
      if(labels == "responsive", do: "hidden md:inline"),
      if(size == "lg", do: "text-xs font-medium")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp button_attributes(button) do
    base_attrs = []

    base_attrs
    |> add_attr_if_present("phx-click", button[:"phx-click"] || button[:phx_click])
    |> add_attr_if_present("phx-target", button[:"phx-target"] || button[:phx_target])
    |> add_attr_if_present("phx-value-option", button[:phx_value_option])
    |> add_attr_if_present("phx-value-widget-id", button[:phx_value_widget_id])
    |> add_attr_if_present("phx-value-granularity", button[:phx_value_granularity])
    |> add_attr_if_present("data-filter-bar-action", button[:"data-filter-bar-action"])
    |> add_attr_if_present(
      "data-filter-bar-granularity",
      button[:"data-filter-bar-granularity"]
    )
    |> add_attr_if_present("disabled", button[:disabled])
    |> add_value_attrs(button[:values])
  end

  defp add_value_attrs(attrs, nil), do: attrs

  defp add_value_attrs(attrs, values) when is_map(values) do
    Enum.reduce(values, attrs, fn {key, value}, acc ->
      add_attr_if_present(acc, "phx-value-#{key}", value)
    end)
  end

  defp add_attr_if_present(attrs, _key, nil), do: attrs
  defp add_attr_if_present(attrs, _key, false), do: attrs
  defp add_attr_if_present(attrs, key, value), do: [{String.to_atom(key), value} | attrs]

  defp button_classes(button, position, size) do
    size_classes =
      case size do
        "sm" -> "px-2.5 h-8"
        "lg" -> "px-2.5 md:px-4 py-2.5 justify-center"
        _ -> "px-3 py-2 h-9"
      end

    base_classes =
      "relative inline-flex items-center #{size_classes} text-sm font-medium transition-colors focus-visible:outline-none focus-visible:bg-white active:bg-white dark:focus-visible:bg-slate-800 dark:active:bg-slate-800"

    position_classes =
      case position do
        :only -> "rounded-md"
        :first -> "rounded-l-md"
        :middle -> ""
        :last -> "rounded-r-md"
      end

    state_classes =
      if Map.get(button, :selected, false) do
        "bg-white dark:bg-slate-800 text-teal-500 dark:text-teal-300 font-semibold border-b-2 border-b-teal-500 dark:border-b-teal-400"
      else
        "bg-white dark:bg-slate-800/80 text-gray-700 dark:text-slate-300 hover:bg-gray-100 dark:hover:bg-slate-700"
      end

    separator_classes =
      case position do
        :first -> ""
        :only -> ""
        _ -> "border-l border-gray-200 dark:border-slate-700"
      end

    disabled_classes =
      if Map.get(button, :disabled, false) do
        "opacity-50 cursor-not-allowed"
      else
        ""
      end

    custom_classes = button[:class] || ""

    "#{base_classes} #{position_classes} #{state_classes} #{separator_classes} #{disabled_classes} #{custom_classes}"
  end
end
