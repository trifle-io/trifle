defmodule TrifleApp.DesignSystem.IconButton do
  @moduledoc "Consistent icon-only actions for widgets and panels."
  use Phoenix.Component

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :size, :string, default: "sm", values: ~w(sm md)
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(disabled)

  def icon_button(assigns) do
    ~H"""
    <button
      type="button"
      aria-label={@label}
      title={@label}
      class={[
        "inline-flex items-center p-1 rounded group/action focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500",
        @class
      ]}
      {@rest}
    >
      <TrifleApp.SidebarIcons.icon
        name={@icon}
        class={[
          if(@size == "md", do: "h-6 w-6", else: "h-4 w-4"),
          "text-gray-600 dark:text-slate-300 transition-colors group-hover/action:text-gray-800 dark:group-hover/action:text-slate-100"
        ]}
      />
    </button>
    """
  end
end
