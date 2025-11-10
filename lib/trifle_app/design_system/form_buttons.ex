defmodule TrifleApp.DesignSystem.FormButtons do
  use Phoenix.Component

  @doc """
  Renders a standardized form action button group.

  ## Examples

      <.form_actions>
        <.primary_button phx-disable-with="Saving...">Save</.primary_button>
        <.secondary_button navigate={~p"/back"}>Cancel</.secondary_button>
      </.form_actions>
      
      <.form_actions align="center">
        <.primary_button>Create</.primary_button>
        <.danger_button phx-click="delete" data-confirm="Are you sure?">Delete</.danger_button>
      </.form_actions>
  """
  attr :align, :string, default: "right", values: ~w(left center right)
  attr :class, :string, default: ""
  attr :spacing, :string, default: "gap-3", values: ~w(gap-2 gap-3 gap-4)

  slot :inner_block, required: true

  def form_actions(assigns) do
    ~H"""
    <div class={[
      "flex",
      align_classes(@align),
      @spacing,
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Primary action button (save, create, submit).
  """
  attr :type, :string, default: "submit"
  attr :class, :string, default: ""

  attr :rest, :global,
    include: ~w(phx-click phx-disable-with phx-value-id data-confirm disabled form)

  slot :inner_block, required: true

  def primary_button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "inline-flex justify-center items-center rounded-lg bg-teal-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:ring-offset-2 dark:focus:ring-offset-slate-800 disabled:opacity-50 disabled:cursor-not-allowed",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Secondary action button (cancel, back).
  """
  attr :type, :string, default: "button"
  attr :class, :string, default: ""
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil

  attr :rest, :global,
    include: ~w(phx-click phx-disable-with phx-value-id data-confirm disabled form)

  slot :inner_block, required: true

  def secondary_button(assigns) do
    ~H"""
    <%= if @navigate || @patch do %>
      <.link
        {if @navigate, do: [navigate: @navigate], else: [patch: @patch]}
        class={[
          "inline-flex justify-center items-center rounded-lg bg-white dark:bg-slate-700 px-4 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:ring-offset-2 dark:focus:ring-offset-slate-800",
          @class
        ]}
      >
        {render_slot(@inner_block)}
      </.link>
    <% else %>
      <button
        type={@type}
        class={[
          "inline-flex justify-center items-center rounded-lg bg-white dark:bg-slate-700 px-4 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:ring-offset-2 dark:focus:ring-offset-slate-800 disabled:opacity-50 disabled:cursor-not-allowed",
          @class
        ]}
        {@rest}
      >
        {render_slot(@inner_block)}
      </button>
    <% end %>
    """
  end

  @doc """
  Danger action button (delete, remove).
  """
  attr :type, :string, default: "button"
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(phx-click phx-disable-with phx-value-id data-confirm disabled)

  slot :inner_block, required: true

  def danger_button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "inline-flex justify-center items-center rounded-lg bg-red-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 dark:focus:ring-offset-slate-800 disabled:opacity-50 disabled:cursor-not-allowed",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Ghost action button (minimal styling).
  """
  attr :type, :string, default: "button"
  attr :class, :string, default: ""
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :rest, :global, include: ~w(phx-click phx-disable-with phx-value-id data-confirm disabled)

  slot :inner_block, required: true

  def ghost_button(assigns) do
    ~H"""
    <%= if @navigate || @patch do %>
      <.link
        {if @navigate, do: [navigate: @navigate], else: [patch: @patch]}
        class={[
          "inline-flex justify-center items-center px-4 py-2 text-sm font-semibold text-gray-700 dark:text-slate-300 hover:text-gray-900 dark:hover:text-white hover:bg-gray-50 dark:hover:bg-slate-700 rounded-lg focus:outline-none focus:ring-2 focus:ring-teal-500 focus:ring-offset-2 dark:focus:ring-offset-slate-800",
          @class
        ]}
      >
        {render_slot(@inner_block)}
      </.link>
    <% else %>
      <button
        type={@type}
        class={[
          "inline-flex justify-center items-center px-4 py-2 text-sm font-semibold text-gray-700 dark:text-slate-300 hover:text-gray-900 dark:hover:text-white hover:bg-gray-50 dark:hover:bg-slate-700 rounded-lg focus:outline-none focus:ring-2 focus:ring-teal-500 focus:ring-offset-2 dark:focus:ring-offset-slate-800 disabled:opacity-50 disabled:cursor-not-allowed",
          @class
        ]}
        {@rest}
      >
        {render_slot(@inner_block)}
      </button>
    <% end %>
    """
  end

  defp align_classes(align) do
    case align do
      "left" -> "justify-start"
      "center" -> "justify-center"
      "right" -> "justify-end"
    end
  end
end
