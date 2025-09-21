defmodule TrifleApp.DesignSystem.TabNavigation do
  use Phoenix.Component

  @doc """
  Renders a tab navigation with consistent styling.

  ## Examples

      <.tab_navigation>
        <:tab href="/explore" active={true}>
          <:icon>
            <svg>...</svg>
          </:icon>
          <:label>Explore</:label>
        </:tab>
        <:tab href="/transponders" active={false}>
          <:icon>
            <svg>...</svg>
          </:icon>
          <:label>Transponders</:label>
        </:tab>
      </.tab_navigation>
  """
  attr :class, :string, default: ""

  slot :tab, required: true do
    attr :href, :string
    attr :navigate, :string
    attr :active, :boolean
    attr :align, :string, values: ["left", "right"]

    slot :icon, doc: "Icon for tab"
    slot :label, doc: "Label for tab"
  end

  def tab_navigation(assigns) do
    ~H"""
    <div class={["mb-6 border-b border-gray-200 dark:border-slate-700", @class]}>
      <nav class="-mb-px space-x-8" aria-label="Tabs">
        <%= for tab <- @tab do %>
          <.link
            {tab_link_attrs(tab)}
            class={tab_classes(tab)}
            aria-current={if Map.get(tab, :active, false), do: "page"}
          >
            <%= for icon <- tab[:icon] || [] do %>
              <div class={tab_icon_classes(tab)}>
                {render_slot(icon)}
              </div>
            <% end %>
            <%= for label <- tab[:label] || [] do %>
              <span class="hidden sm:block">
                {render_slot(label)}
              </span>
            <% end %>
          </.link>
        <% end %>
      </nav>
    </div>
    """
  end

  defp tab_link_attrs(tab) do
    cond do
      tab[:navigate] -> [navigate: tab[:navigate]]
      tab[:href] -> [href: tab[:href]]
      true -> []
    end
  end

  defp tab_classes(tab) do
    base_classes = "group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium"

    active_classes =
      if Map.get(tab, :active, false) do
        "border-teal-500 text-teal-600 dark:text-teal-400"
      else
        "border-transparent text-gray-500 dark:text-slate-400 hover:border-gray-300 dark:hover:border-slate-500 hover:text-gray-700 dark:hover:text-slate-300"
      end

    align_classes =
      case Map.get(tab, :align, "left") do
        "right" -> "float-right"
        _ -> ""
      end

    "#{base_classes} #{active_classes} #{align_classes}"
  end

  defp tab_icon_classes(tab) do
    base_classes = "-ml-0.5 mr-2 h-5 w-5"

    if Map.get(tab, :active, false) do
      "text-teal-400 group-hover:text-teal-500 #{base_classes}"
    else
      "text-gray-400 dark:text-slate-400 group-hover:text-gray-500 dark:group-hover:text-slate-300 #{base_classes}"
    end
  end
end
