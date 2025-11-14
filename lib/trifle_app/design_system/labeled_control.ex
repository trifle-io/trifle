defmodule TrifleApp.DesignSystem.LabeledControl do
  use Phoenix.Component

  @doc """
  Renders a labeled control container with consistent styling.

  ## Examples

      <.labeled_control label="Timeframe">
        <input type="text" ... />
      </.labeled_control>
      
      <.labeled_control label="Controls">
        <.button_group>
          ...buttons...
        </.button_group>
      </.labeled_control>
  """
  attr :label, :string, required: true
  attr :class, :string, default: ""

  slot :inner_block, required: true

  def labeled_control(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <label class="absolute -top-2 left-2 inline-block filter-field-label px-1 text-xs font-medium text-gray-900 dark:text-white z-20">
        {@label}
      </label>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a labeled input field with consistent styling.
  """
  attr :label, :string, required: true
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, default: ""
  attr :type, :string, default: "text"
  attr :class, :string, default: ""
  attr :input_class, :string, default: nil
  attr :rest, :global, include: ~w(phx-change phx-keydown phx-key phx-focus phx-blur phx-hook)

  slot :suffix
  slot :badge

  def labeled_input(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <label
        for={@id}
        class="absolute -top-2 left-2 inline-block filter-field-label px-1 text-xs font-medium text-gray-900 dark:text-white z-20"
      >
        {@label}
      </label>
      <div class="relative">
        <input
          type={@type}
          name={@name}
          id={@id}
          value={@value}
          placeholder={@placeholder}
          class={[
            "block w-full rounded-md border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm",
            @input_class,
            if(@badge != [] || @suffix != [], do: "pr-20", else: "")
          ]}
          {@rest}
        />

        <%= if @badge != [] do %>
          <div class="absolute inset-y-0 right-8 flex items-center">
            {render_slot(@badge)}
          </div>
        <% end %>

        <%= if @suffix != [] do %>
          <div class="absolute inset-y-0 right-0 flex items-center pr-3">
            {render_slot(@suffix)}
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
