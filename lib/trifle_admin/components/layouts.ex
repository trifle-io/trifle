defmodule TrifleAdmin.Layouts do
  use TrifleAdmin, :html

  embed_templates "layouts/*"

  alias TrifleWeb.SidebarHelpers

  attr :socket, :any, required: true
  attr :item, :map, required: true

  def sidebar_link(assigns) do
    assigns =
      assigns
      |> assign(:active?, active_nav?(assigns.socket, assigns.item.menu))
      |> assign(:tooltip_expr, SidebarHelpers.compact_tooltip_expr(assigns.item.label))
      |> assign(
        :link_attrs,
        if(Map.get(assigns.item, :use_href, false),
          do: [href: assigns.item.to],
          else: [navigate: assigns.item.to]
        ) ++
          [
            {"data-fast-tooltip", true},
            {"x-bind:data-tooltip", SidebarHelpers.compact_tooltip_expr(assigns.item.label)}
          ]
      )

    ~H"""
    <.link
      {@link_attrs}
      aria-current={if @active?, do: "page"}
      aria-label={@item.label}
      class={[
        "sidebar-nav-link group relative block w-full rounded-[1.15rem] text-sm font-semibold transition duration-200 ease-out focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-orange-500/70 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-slate-900",
        SidebarHelpers.sidebar_link_classes(@active?, :orange)
      ]}
    >
      <span
        :if={!@active?}
        class={[
          "pointer-events-none absolute left-0.5 top-1/2 h-7 w-0.5 -translate-y-1/2 rounded-full opacity-0 transition-opacity duration-200 ease-out group-hover:opacity-100",
          SidebarHelpers.sidebar_hover_line_classes(:orange)
        ]}
      />
      <span
        :if={@active?}
        class={[
          "pointer-events-none absolute left-0.5 top-1/2 h-7 w-0.5 -translate-y-1/2 rounded-full",
          SidebarHelpers.sidebar_active_line_classes(:orange)
        ]}
      />
      <span
        class="flex items-center gap-3"
        x-bind:class="compact ? 'mx-auto h-10 w-10 justify-center px-0' : 'min-h-[3.1rem] w-full justify-start px-3.5'"
      >
        <span class={[
          "flex h-9 w-9 shrink-0 items-center justify-center rounded-2xl transition",
          SidebarHelpers.sidebar_icon_shell_classes(@active?, :orange)
        ]}>
          <TrifleApp.SidebarIcons.icon
            name={@item.icon}
            class={[
              "h-[1.05rem] w-[1.05rem] shrink-0 transition",
              SidebarHelpers.sidebar_icon_classes(@active?, :orange)
            ]}
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
      %{
        menu: :organizations,
        label: "Organizations",
        to: ~p"/admin/organizations",
        icon: "sidebar-organization"
      },
      %{menu: :users, label: "Users", to: ~p"/admin/users", icon: "sidebar-users"},
      %{menu: :projects, label: "Projects", to: ~p"/admin/projects", icon: "sidebar-projects"},
      %{
        menu: :project_clusters,
        label: "Project Clusters",
        to: ~p"/admin/project-clusters",
        icon: "sidebar-project-clusters"
      },
      %{
        menu: :databases,
        label: "Databases",
        to: ~p"/admin/databases",
        icon: "sidebar-databases"
      },
      %{
        menu: :dashboards,
        label: "Dashboards",
        to: ~p"/admin/dashboards",
        icon: "sidebar-dashboards"
      },
      %{menu: :monitors, label: "Monitors", to: ~p"/admin/monitors", icon: "sidebar-monitors"},
      %{menu: :billing, label: "Billing", to: ~p"/admin/billing", icon: "sidebar-billing"}
    ]
  end

  def secondary_nav_items do
    [
      %{
        menu: :exit_admin,
        label: "Exit Admin",
        to: ~p"/",
        icon: "hero-arrow-uturn-left",
        use_href: true
      }
    ]
  end

  def current_nav_label(socket) do
    case Enum.find(nav_items(), &active_nav?(socket, &1.menu)) do
      %{label: label} -> label
      _ -> "Admin"
    end
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

    attrs =
      Phoenix.HTML.attributes_escape(
        src: "https://www.gravatar.com/avatar/#{hash}?s=150&d=identicon",
        class: "h-8 w-8 rounded-full",
        alt: ""
      )
      |> Phoenix.HTML.safe_to_string()

    Phoenix.HTML.raw("<img#{attrs} />")
  end
end
