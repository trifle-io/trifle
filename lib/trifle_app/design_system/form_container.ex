defmodule TrifleApp.DesignSystem.FormContainer do
  use Phoenix.Component

  @doc """
  Renders a standardized form container with consistent layout and styling.

  ## Examples

      <.form_container for={@form} phx-submit="save">
        <:header title="Create User" subtitle="Add a new user to the system" />
        
        <.form_field field={@form[:name]} label="Name" required />
        <.form_field field={@form[:email]} type="email" label="Email" required />
        
        <:actions>
          <.primary_button phx-disable-with="Creating...">Create User</.primary_button>
          <.secondary_button navigate={~p"/users"}>Cancel</.secondary_button>
        </:actions>
      </.form_container>
      
      <!-- Grid layout for admin forms -->
      <.form_container for={@form} phx-submit="save" layout="grid">
        <.form_field field={@form[:name]} label="Database Name" required />
        <.form_field field={@form[:driver]} type="select" label="Driver" options={@drivers} />
      </.form_container>
  """
  attr :for, :any, required: true
  attr :layout, :string, default: "simple", values: ~w(simple grid slide_over)
  attr :class, :string, default: ""

  attr :rest, :global,
    include: ~w(id phx-submit phx-change phx-update action method phx-trigger-action)

  slot :header do
    attr :title, :string
    attr :subtitle, :string
  end

  slot :inner_block, required: true
  slot :actions

  def form_container(assigns) do
    ~H"""
    <.form for={@for} class={[container_classes(@layout), @class]} {@rest}>
      <!-- Header -->
      <%= for header <- @header do %>
        <div class={header_classes(@layout)}>
          <%= if header[:title] do %>
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
              {header[:title]}
            </h2>
          <% end %>
          <%= if header[:subtitle] do %>
            <p class="mt-1 text-sm text-gray-500 dark:text-slate-400">
              {header[:subtitle]}
            </p>
          <% end %>
        </div>
      <% end %>
      
    <!-- Form Fields -->
      <div class={fields_classes(@layout)}>
        {render_slot(@inner_block)}
      </div>
      
    <!-- Actions -->
      <%= if @actions != [] do %>
        <div class={actions_classes(@layout)}>
          <%= for action <- @actions do %>
            {render_slot(action)}
          <% end %>
        </div>
      <% end %>
    </.form>
    """
  end

  @doc """
  Renders a form section with optional title and description.
  """
  attr :title, :string, default: nil
  attr :description, :string, default: nil
  attr :class, :string, default: ""

  slot :inner_block, required: true

  def form_section(assigns) do
    ~H"""
    <div class={["space-y-6", @class]}>
      <%= if @title || @description do %>
        <div>
          <%= if @title do %>
            <h3 class="text-base font-semibold text-gray-900 dark:text-white">
              {@title}
            </h3>
          <% end %>
          <%= if @description do %>
            <p class="mt-1 text-sm text-gray-500 dark:text-slate-400">
              {@description}
            </p>
          <% end %>
        </div>
      <% end %>

      <div class="space-y-4">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp container_classes(layout) do
    case layout do
      "simple" ->
        "space-y-6"

      "grid" ->
        "space-y-6"

      "slide_over" ->
        "flex h-full flex-col overflow-y-scroll bg-white dark:bg-slate-800 shadow-xl"
    end
  end

  defp header_classes(layout) do
    case layout do
      "simple" -> "border-b border-gray-200 dark:border-slate-700 pb-4"
      "grid" -> "border-b border-gray-200 dark:border-slate-700 pb-4"
      "slide_over" -> "bg-gray-50 dark:bg-slate-700 px-4 py-6 sm:px-6"
    end
  end

  defp fields_classes(layout) do
    case layout do
      "simple" -> "space-y-4"
      "grid" -> "space-y-6 sm:space-y-8"
      "slide_over" -> "flex-1 px-4 py-6 sm:px-6 space-y-4"
    end
  end

  defp actions_classes(layout) do
    case layout do
      "simple" ->
        "border-t border-gray-200 dark:border-slate-700 pt-4"

      "grid" ->
        "border-t border-gray-200 dark:border-slate-700 pt-6"

      "slide_over" ->
        "flex-shrink-0 border-t border-gray-200 dark:border-slate-700 px-4 py-5 sm:px-6"
    end
  end
end
