defmodule TrifleApp.DesignSystem.DataTable do
  use Phoenix.Component

  @doc """
  Renders a data table container with consistent styling.
  """
  attr :class, :string, default: ""
  attr :id, :string, default: nil
  attr :phx_hook, :string, default: nil

  slot :header, required: true
  slot :body, required: true
  slot :footer

  def data_table(assigns) do
    ~H"""
    <div class={["bg-white dark:bg-slate-800 rounded-lg shadow", @class]}>
      {render_slot(@header)}

      <div class="overflow-x-auto overflow-hidden" id={@id} phx-hook={@phx_hook}>
        {render_slot(@body)}
      </div>

      <%= if @footer != [] do %>
        {render_slot(@footer)}
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a table header with title and optional actions.
  """
  attr :title, :string, required: true
  attr :count, :integer, default: nil
  attr :class, :string, default: ""

  slot :actions
  slot :search

  def table_header(assigns) do
    ~H"""
    <div class={[
      "py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 dark:text-white sm:pl-3 border-b border-gray-100 dark:border-slate-700 flex items-center justify-between",
      @class
    ]}>
      <div class="flex items-center gap-2">
        <span>{@title}</span>
        <%= if @count do %>
          <span class="inline-flex items-center rounded-md bg-teal-50 dark:bg-teal-900 px-2 py-1 text-xs font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30">
            {@count}
          </span>
        <% end %>
      </div>

      <div class="flex items-center gap-3">
        {render_slot(@search)}
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a table summary bar/footer with consistent styling.
  """
  attr :class, :string, default: ""

  slot :inner_block, required: true

  def table_summary(assigns) do
    ~H"""
    <div class={[
      "border-t border-gray-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-4 py-3",
      @class
    ]}>
      <div class="flex flex-wrap items-center gap-4 text-xs">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a summary stat item with icon and value.
  """
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :icon_color, :string, default: "text-teal-500"
  attr :clickable, :boolean, default: false
  attr :phx_click, :string, default: nil
  attr :class, :string, default: ""

  slot :icon, required: true

  def summary_stat(assigns) do
    ~H"""
    <div class={["flex items-center gap-1", @class]}>
      <div class={[@icon_color]}>
        {render_slot(@icon)}
      </div>
      <span class="font-medium text-gray-700 dark:text-slate-300">{@label}:</span>
      <%= if @clickable && @phx_click do %>
        <button
          phx-click={@phx_click}
          class="text-red-600 dark:text-red-400 hover:text-red-800 dark:hover:text-red-300 underline"
        >
          {@value}
        </button>
      <% else %>
        <span class="text-gray-900 dark:text-white">{@value}</span>
      <% end %>
    </div>
    """
  end
end
