defmodule TrifleApp.Components.ProjectNav do
  use Phoenix.Component
  use TrifleApp, :verified_routes

  attr :project, Trifle.Organizations.Project, required: true
  attr :current, :atom, required: true

  def project_nav(assigns) do
    ~H"""
    <div class="border-b border-gray-200 dark:border-slate-700">
      <nav class="-mb-px flex space-x-4 sm:space-x-8" aria-label="Project tabs">
        <.nav_link
          id={:transponders}
          current={@current}
          label="Transponders"
          to={~p"/projects/#{@project.id}"}
          icon={:transponders}
        />
        <.nav_link
          id={:tokens}
          current={@current}
          label="Tokens"
          to={~p"/projects/#{@project.id}/tokens"}
          icon={:tokens}
        />
        <.nav_link
          id={:settings}
          current={@current}
          label="Settings"
          to={~p"/projects/#{@project.id}/settings"}
          icon={:settings}
        />
        <.nav_link
          id={:billing}
          current={@current}
          label="Billing"
          to={~p"/projects/#{@project.id}/billing"}
          icon={:billing}
        />
      </nav>
    </div>
    """
  end

  attr :id, :atom, required: true
  attr :current, :atom, required: true
  attr :label, :string, required: true
  attr :to, :string, required: true
  attr :icon, :atom, required: true

  defp nav_link(assigns) do
    assigns = assign(assigns, :active?, assigns.id == assigns.current)

    ~H"""
    <.link
      navigate={@to}
      aria-current={if @active?, do: "page"}
      class={[
        "group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium transition",
        if(@active?,
          do: "border-teal-500 text-teal-600 dark:text-teal-300",
          else:
            "border-transparent text-gray-500 dark:text-slate-400 hover:border-gray-300 dark:hover:border-slate-500 hover:text-gray-700 dark:hover:text-slate-300"
        )
      ]}
    >
      <%= case @icon do %>
        <% :transponders -> %>
          <svg
            class={icon_classes(@active?)}
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M21 7.5l-2.25-1.313M21 7.5v2.25m0-2.25l-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3l2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75l2.25-1.313M12 21.75V19.5m0 2.25l-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25"
            />
          </svg>
        <% :tokens -> %>
          <svg
            class={icon_classes(@active?)}
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M15.75 5.25a3 3 0 013 3m3 0a6 6 0 01-7.029 5.912c-.563-.097-1.159.026-1.563.43L10.5 17.25H8.25v2.25H6v2.25H2.25v-2.818c0-.597.237-1.17.659-1.591l6.499-6.499c.404-.404.527-1 .43-1.563A6 6 0 1121.75 8.25z"
            />
          </svg>
        <% :settings -> %>
          <svg
            class={icon_classes(@active?)}
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M11.42 15.17L17.25 21A2.652 2.652 0 0021 17.25l-5.877-5.877M11.42 15.17l2.496-3.03c.317-.384.74-.626 1.208-.766M11.42 15.17l-4.655 5.653a2.548 2.548 0 11-3.586-3.586l6.837-5.63m5.108-.233c.55-.164 1.163-.188 1.743-.14a4.5 4.5 0 004.486-6.336l-3.276 3.277a3.004 3.004 0 01-2.25-2.25l3.276-3.276a4.5 4.5 0 00-6.336 4.486c.091 1.076-.071 2.264-.904 2.95l-.102.085m-1.745 1.437L5.909 7.5H4.5L2.25 3.75l1.5-1.5L7.5 4.5v1.409l4.26 4.26m-1.745 1.437l1.745-1.437m6.615 8.206L15.75 15.75M4.867 19.125h.008v.008h-.008v-.008z"
            />
          </svg>
        <% :billing -> %>
          <svg
            class={icon_classes(@active?)}
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M2.25 8.25h19.5M3.75 6h16.5A1.5 1.5 0 0121.75 7.5v9A1.5 1.5 0 0120.25 18H3.75a1.5 1.5 0 01-1.5-1.5v-9A1.5 1.5 0 013.75 6zm12.75 7.5h2.25"
            />
          </svg>
      <% end %>
      <span class="hidden sm:block">{@label}</span>
    </.link>
    """
  end

  defp icon_classes(true),
    do: "text-teal-400 group-hover:text-teal-500 -ml-0.5 mr-2 h-5 w-5"

  defp icon_classes(false),
    do:
      "text-gray-400 dark:text-slate-400 group-hover:text-gray-500 dark:group-hover:text-slate-300 -ml-0.5 mr-2 h-5 w-5"
end
