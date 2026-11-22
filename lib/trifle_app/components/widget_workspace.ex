defmodule TrifleApp.Components.WidgetWorkspace do
  @moduledoc "In-page widget expansion below the page's FilterBar."
  use TrifleApp, :html

  alias TrifleApp.DesignSystem.IconButton

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :type, :string, default: nil
  attr :close_event, :string, default: "close_expanded_widget"
  attr :return_focus, :string, default: "#smart_timeframe"

  slot :heading
  slot :status
  slot :controls
  slot :notice
  slot :actions
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <section
      id={@id}
      aria-labelledby={"#{@id}-title"}
      class="mb-6 flex min-w-0 shrink-0 flex-col gap-4 rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-700 dark:bg-slate-800/70 sm:p-6"
      phx-mounted={JS.focus(to: "##{@id}-title")}
      phx-remove={JS.focus(to: @return_focus)}
      x-data
      x-on:keydown.escape.stop="$el.querySelector('[data-workspace-close]').click()"
    >
      <header class="flex flex-wrap items-center gap-3">
        <div class="flex min-w-0 flex-1 flex-wrap items-center gap-x-3 gap-y-1">
          <h2
            id={"#{@id}-title"}
            tabindex="-1"
            class="min-w-0 truncate text-base font-semibold text-gray-900 dark:text-white"
            title={@title}
          >
            {if @heading == [], do: @title, else: render_slot(@heading)}
          </h2>
          <span
            :if={@type}
            class="inline-flex items-center rounded-full bg-teal-100/70 dark:bg-teal-900/40 px-3 py-0.5 text-xs font-medium text-teal-700 dark:text-teal-200"
          >
            {String.capitalize(@type)}
          </span>
          {render_slot(@status)}
        </div>
        <div :if={@controls != []} class="order-last w-full sm:order-none sm:w-auto">
          {render_slot(@controls)}
        </div>
        <IconButton.icon_button
          id={"close-#{@id}"}
          icon="hero-x-mark"
          label="Close widget"
          size="md"
          class="shrink-0 !p-2 hover:bg-slate-200 dark:hover:bg-slate-700"
          phx-click={@close_event}
          data-workspace-close
        />
      </header>
      {render_slot(@notice)}
      <div class="h-[max(28rem,65dvh)] min-w-0">
        {render_slot(@inner_block)}
      </div>
      <footer :if={@actions != []} class="flex flex-wrap items-end justify-between gap-3">
        {render_slot(@actions)}
      </footer>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :expanded, :boolean, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def background(assigns) do
    ~H"""
    <div
      id={@id}
      class={if @expanded, do: "invisible h-0 shrink-0 overflow-hidden", else: @class}
      inert={@expanded}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end
end
