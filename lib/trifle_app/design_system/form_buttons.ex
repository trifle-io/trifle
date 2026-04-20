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
        "inline-flex justify-center items-center rounded-lg bg-teal-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2 dark:focus-visible:ring-offset-slate-800 disabled:opacity-50 disabled:cursor-not-allowed",
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
          "inline-flex justify-center items-center rounded-lg bg-white dark:bg-slate-700 px-4 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2 dark:focus-visible:ring-offset-slate-800",
          @class
        ]}
      >
        {render_slot(@inner_block)}
      </.link>
    <% else %>
      <button
        type={@type}
        class={[
          "inline-flex justify-center items-center rounded-lg bg-white dark:bg-slate-700 px-4 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2 dark:focus-visible:ring-offset-slate-800 disabled:opacity-50 disabled:cursor-not-allowed",
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

  Defaults to the muted danger-zone treatment. Use `variant="solid"` only when the
  destructive action is the primary action in a confirmation step.
  """
  attr :type, :string, default: "button"
  attr :class, :string, default: ""
  attr :variant, :string, default: "soft", values: ~w(soft solid)

  attr :rest, :global,
    include:
      ~w(phx-click phx-disable-with phx-target phx-value-id phx-value-group_id data-confirm disabled title aria-label)

  slot :inner_block, required: true

  def danger_button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        danger_button_classes(@variant),
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
          "inline-flex justify-center items-center px-4 py-2 text-sm font-semibold text-gray-700 dark:text-slate-300 hover:text-gray-900 dark:hover:text-white hover:bg-gray-50 dark:hover:bg-slate-700 rounded-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2 dark:focus-visible:ring-offset-slate-800",
          @class
        ]}
      >
        {render_slot(@inner_block)}
      </.link>
    <% else %>
      <button
        type={@type}
        class={[
          "inline-flex justify-center items-center px-4 py-2 text-sm font-semibold text-gray-700 dark:text-slate-300 hover:text-gray-900 dark:hover:text-white hover:bg-gray-50 dark:hover:bg-slate-700 rounded-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2 dark:focus-visible:ring-offset-slate-800 disabled:opacity-50 disabled:cursor-not-allowed",
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

  defp danger_button_classes("solid") do
    "inline-flex items-center justify-center rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-red-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600 dark:shadow-none disabled:cursor-not-allowed disabled:opacity-50"
  end

  defp danger_button_classes(_variant) do
    "inline-flex items-center justify-center rounded-md bg-red-50 px-3 py-2 text-sm font-semibold text-red-700 ring-1 ring-inset ring-red-600/20 transition hover:bg-red-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600 dark:bg-red-900 dark:text-red-200 dark:ring-red-500/30 dark:hover:bg-red-800 disabled:cursor-not-allowed disabled:opacity-50"
  end
end
