defmodule TrifleApp.DesignSystem.ButtonGroup do
  use Phoenix.Component

  @doc """
  Renders a labeled button group with consistent styling.

  ## Examples

      <.button_group label="Controls">
        <:button phx-click="action1" title="Action 1">
          <.icon name="hero-arrow-left" />
        </:button>
        <:button phx-click="action2" title="Action 2">
          <.icon name="hero-refresh" />
        </:button>
      </.button_group>
      
      <.button_group label="Options">
        <:button phx-click="select" phx-value-option="1" selected={@current == "1"}>
          Option 1
        </:button>
        <:button phx-click="select" phx-value-option="2" selected={@current == "2"}>
          Option 2
        </:button>
      </.button_group>
  """
  attr :label, :string, default: nil
  attr :class, :string, default: ""
  attr :size, :string, default: "md", values: ["md", "sm", "lg"]

  slot :button, required: true do
    attr :"phx-click", :string
    attr :phx_click, :string
    attr :"phx-target", :any
    attr :phx_target, :any
    attr :phx_value_option, :string
    attr :phx_value_widget_id, :string
    attr :phx_value_granularity, :string
    attr :values, :map
    attr :title, :string
    attr :class, :string
    attr :"aria-label", :string
    attr :"aria-pressed", :string
    attr :"data-tooltip", :string
    attr :"data-filter-bar-action", :string
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
            title={button[:title]}
            aria-label={button[:"aria-label"]}
            aria-pressed={button[:"aria-pressed"]}
            data-tooltip={button[:"data-tooltip"]}
            data-series-display-mode-button={button[:"data-series-display-mode-button"]}
          >
            {render_slot(button)}
          </button>
        <% end %>
      </div>
    </div>
    """
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
        "lg" -> "px-4 py-2.5 justify-center"
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
