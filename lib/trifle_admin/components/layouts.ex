defmodule TrifleAdmin.Layouts do
  use TrifleAdmin, :html

  embed_templates "layouts/*"

  attr :socket, :any, required: true
  attr :item, :map, required: true

  def sidebar_link(assigns) do
    assigns =
      assigns
      |> assign(:active?, active_nav?(assigns.socket, assigns.item.menu))
      |> assign(:tooltip_expr, compact_tooltip_expr(assigns.item.label))

    ~H"""
    <.link
      navigate={@item.to}
      aria-current={if @active?, do: "page"}
      aria-label={@item.label}
      class={[
        "group rounded-[1.15rem] text-sm font-semibold transition duration-200 ease-out hover:-translate-y-px focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-orange-500/70 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-slate-900",
        sidebar_link_classes(@active?)
      ]}
    >
      <span
        class="flex min-h-[3.1rem] items-center gap-3"
        x-bind:class="compact ? 'justify-center px-2.5' : 'justify-start px-3.5'"
        data-fast-tooltip
        x-bind:data-tooltip={@tooltip_expr}
      >
        <span class={["flex h-9 w-9 shrink-0 items-center justify-center rounded-2xl ring-1 transition", sidebar_icon_shell_classes(@active?)]}>
          <TrifleApp.SidebarIcons.icon
            name={@item.icon}
            class={["h-[1.05rem] w-[1.05rem] shrink-0 transition", sidebar_icon_classes(@active?)]}
          />
        </span>
        <span x-cloak x-show="!compact" x-transition.opacity.duration.150ms class="truncate">
          {@item.label}
        </span>
      </span>
    </.link>
    """
  end

  def nav_items do
    [
      %{menu: :dashboard, label: "Overview", to: ~p"/admin", icon: "sidebar-overview"},
      %{menu: :organizations, label: "Organizations", to: ~p"/admin/organizations", icon: "sidebar-organization"},
      %{menu: :users, label: "Users", to: ~p"/admin/users", icon: "sidebar-users"},
      %{menu: :projects, label: "Projects", to: ~p"/admin/projects", icon: "sidebar-projects"},
      %{menu: :project_clusters, label: "Project Clusters", to: ~p"/admin/project-clusters", icon: "sidebar-project-clusters"},
      %{menu: :databases, label: "Databases", to: ~p"/admin/databases", icon: "sidebar-databases"},
      %{menu: :dashboards, label: "Dashboards", to: ~p"/admin/dashboards", icon: "sidebar-dashboards"},
      %{menu: :monitors, label: "Monitors", to: ~p"/admin/monitors", icon: "sidebar-monitors"},
      %{menu: :billing, label: "Billing", to: ~p"/admin/billing", icon: "sidebar-billing"}
    ]
  end

  def compact_tooltip_expr(text) when is_binary(text) do
    "compact ? #{Phoenix.json_library().encode!(text)} : null"
  end

  def secondary_nav_items do
    [
      %{menu: :exit_admin, label: "Exit Admin", to: ~p"/", icon: "hero-arrow-uturn-left"}
    ]
  end

  def current_nav_label(socket) do
    case Enum.find(nav_items(), &active_nav?(socket, &1.menu)) do
      %{label: label} -> label
      _ -> "Admin"
    end
  end

  defp sidebar_link_classes(true) do
    "bg-[linear-gradient(135deg,rgba(249,115,22,0.18),rgba(255,255,255,0.88))] text-slate-900 ring-1 ring-inset ring-orange-500/20 shadow-[0_16px_34px_-26px_rgba(249,115,22,0.8)] dark:bg-[linear-gradient(135deg,rgba(251,146,60,0.18),rgba(15,23,42,0.92))] dark:text-white dark:ring-orange-300/20"
  end

  defp sidebar_link_classes(false) do
    "text-slate-600 hover:bg-white/95 hover:text-slate-950 hover:shadow-[0_14px_24px_-24px_rgba(15,23,42,0.45)] dark:text-slate-300 dark:hover:bg-white/[0.06] dark:hover:text-white"
  end

  defp sidebar_icon_shell_classes(true) do
    "bg-orange-500/15 text-orange-700 ring-orange-500/20 shadow-inner shadow-white/60 dark:bg-orange-400/14 dark:text-orange-200 dark:ring-orange-300/20 dark:shadow-transparent"
  end

  defp sidebar_icon_shell_classes(false) do
    "bg-white/90 text-slate-500 ring-slate-200/80 group-hover:bg-white group-hover:text-slate-800 dark:bg-slate-900/80 dark:text-slate-400 dark:ring-white/10 dark:group-hover:bg-slate-800 dark:group-hover:text-slate-100"
  end

  defp sidebar_icon_classes(true), do: "text-orange-700 dark:text-orange-200"

  defp sidebar_icon_classes(false) do
    "text-inherit"
  end

  defp active_nav?(%Phoenix.LiveView.Socket{} = socket, menu) do
    view = socket.view

    case {menu, view} do
      {:dashboard, TrifleAdmin.AdminLive} -> true
      {:organizations, TrifleAdmin.OrganizationsLive} -> true
      {:users, TrifleAdmin.UsersLive} -> true
      {:projects, TrifleAdmin.ProjectsLive} -> true
      {:project_clusters, TrifleAdmin.ProjectClustersLive} -> true
      {:databases, TrifleAdmin.DatabasesLive} -> true
      {:dashboards, TrifleAdmin.DashboardsLive} -> true
      {:monitors, TrifleAdmin.MonitorsLive} -> true
      {:billing, TrifleAdmin.BillingLive} -> true
      {:billing, TrifleAdmin.BillingPlansLive} -> true
      _ -> false
    end
  end

  defp active_nav?(_, _), do: false

  def gravatar(email) do
    hash =
      email
      |> String.trim()
      |> String.downcase()
      |> :erlang.md5()
      |> Base.encode16(case: :lower)

    img = "https://www.gravatar.com/avatar/#{hash}?s=150&d=identicon"
    Phoenix.HTML.raw("<img src=\"#{img}\" alt='' class='h-8 w-8 rounded-full'></img>")
  end
end
