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
  attr :label, :string, required: true
  attr :class, :string, default: ""
  
  slot :button, required: true do
    attr :"phx-click", :string
    attr :phx_click, :string
    attr :phx_value_option, :string
    attr :phx_value_granularity, :string
    attr :title, :string
    attr :selected, :boolean
    attr :disabled, :boolean
  end

  def button_group(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <label class="absolute -top-2 left-2 inline-block bg-white dark:bg-slate-800 px-1 text-xs font-medium text-gray-900 dark:text-white z-10">
        {@label}
      </label>
      <div class="inline-flex rounded-md shadow-sm border border-gray-300 dark:border-slate-600 focus-within:border-teal-500 focus-within:ring-1 focus-within:ring-teal-500" role="group">
        <%= for {button, index} <- Enum.with_index(@button) do %>
          <% position = cond do
            length(@button) == 1 -> :only
            index == 0 -> :first
            index == length(@button) - 1 -> :last
            true -> :middle
          end %>
          
          <button
            type="button"
            {button_attributes(button)}
            class={button_classes(button, position)}
            title={button[:title]}
          >
            <%= render_slot(button) %>
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
    |> add_attr_if_present("phx-value-option", button[:phx_value_option])
    |> add_attr_if_present("phx-value-granularity", button[:phx_value_granularity])
    |> add_attr_if_present("disabled", button[:disabled])
  end

  defp add_attr_if_present(attrs, _key, nil), do: attrs
  defp add_attr_if_present(attrs, _key, false), do: attrs
  defp add_attr_if_present(attrs, key, value), do: [{String.to_atom(key), value} | attrs]

  defp button_classes(button, position) do
    base_classes = "relative inline-flex items-center px-3 py-2 text-sm font-medium focus:z-10 focus:outline-none h-9"

    position_classes = case position do
      :only -> "rounded-md"
      :first -> "rounded-l-md"
      :middle -> ""
      :last -> "rounded-r-md"
    end

    state_classes = if Map.get(button, :selected, false) do
      "bg-white dark:bg-slate-700 text-teal-500 dark:text-teal-400 border-b-2 border-b-teal-500 font-semibold hover:shadow-[inset_0_-8px_16px_-8px_rgba(20,184,166,0.2)]"
    else
      "bg-white dark:bg-slate-700 text-gray-700 dark:text-slate-300 border-b-2 border-b-transparent hover:border-b-gray-300 dark:hover:border-b-slate-400 hover:shadow-[inset_0_-8px_16px_-8px_rgba(107,114,128,0.15)] dark:hover:shadow-[inset_0_-8px_16px_-8px_rgba(148,163,184,0.15)]"
    end

    separator_classes = case position do
      :first -> ""
      :only -> ""
      _ -> "border-l border-gray-300 dark:border-slate-600"
    end

    disabled_classes = if Map.get(button, :disabled, false) do
      "opacity-50 cursor-not-allowed"
    else
      ""
    end

    "#{base_classes} #{position_classes} #{state_classes} #{separator_classes} #{disabled_classes}"
  end
end