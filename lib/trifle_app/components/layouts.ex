defmodule TrifleApp.Layouts do
  use TrifleApp, :html

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
        "sidebar-nav-link group relative block w-full rounded-[1.15rem] text-sm font-semibold transition duration-200 ease-out focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500/70 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-slate-900",
        SidebarHelpers.sidebar_link_classes(@active?, :teal)
      ]}
    >
      <span
        :if={@active?}
        class="pointer-events-none absolute left-2 top-1/2 hidden h-8 w-1 -translate-y-1/2 rounded-full bg-teal-500 shadow-[0_0_16px_rgba(20,184,166,0.35)] dark:bg-teal-300 dark:shadow-[0_0_18px_rgba(94,234,212,0.28)]"
        x-bind:class="compact ? 'hidden' : 'block'"
      />
      <span
        class="flex items-center gap-3"
        x-bind:class="compact ? 'mx-auto h-10 w-10 justify-center px-0' : 'min-h-[3.1rem] w-full justify-start px-3.5'"
      >
        <span class={[
          "flex h-9 w-9 shrink-0 items-center justify-center rounded-2xl ring-1 transition",
          SidebarHelpers.sidebar_icon_shell_classes(@active?, :teal)
        ]}>
          <TrifleApp.SidebarIcons.icon
            name={@item.icon}
            class={[
              "h-[1.05rem] w-[1.05rem] shrink-0 transition",
              SidebarHelpers.sidebar_icon_classes(@active?, :teal)
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
      %{menu: :home, label: "Home", to: ~p"/", icon: "sidebar-home"},
      %{menu: :dashboards, label: "Dashboards", to: ~p"/dashboards", icon: "sidebar-dashboards"},
      %{menu: :monitors, label: "Monitors", to: ~p"/monitors", icon: "sidebar-monitors"},
      %{menu: :explore, label: "Explore", to: ~p"/explore", icon: "sidebar-explore"},
      Trifle.Config.projects_enabled?() &&
        %{menu: :projects, label: "Projects", to: ~p"/projects", icon: "sidebar-projects"},
      %{menu: :databases, label: "Databases", to: ~p"/dbs", icon: "sidebar-databases"},
      %{menu: :chat, label: "Trifle AI", to: ~p"/chat", icon: "sidebar-ai"}
    ]
    |> Enum.filter(& &1)
  end

  def secondary_nav_items(current_user, current_membership) do
    [
      current_membership && organization_item(),
      current_user && current_user.is_admin && admin_console_item()
    ]
    |> Enum.filter(& &1)
  end

  def current_nav_label(socket) do
    current_user = Map.get(socket.assigns, :current_user)
    current_membership = Map.get(socket.assigns, :current_membership)

    case Enum.find(
           sidebar_nav_items(current_user, current_membership),
           &active_nav?(socket, &1.menu)
         ) do
      %{label: label} -> label
      _ -> "Workspace"
    end
  end

  defp organization_item do
    %{
      menu: :organization,
      label: "Organization",
      to: ~p"/organization/profile",
      icon: "sidebar-organization"
    }
  end

  defp admin_console_item do
    %{
      menu: :admin_console,
      label: "Admin Console",
      to: "/admin",
      icon: "sidebar-admin",
      use_href: true
    }
  end

  defp sidebar_nav_items(current_user, current_membership) do
    nav_items() ++ secondary_nav_items(current_user, current_membership)
  end

  defp active_nav?(%Phoenix.LiveView.Socket{} = socket, menu) do
    view = socket.view

    case {menu, view} do
      {:home, TrifleApp.HomeLive} ->
        true

      {:dashboards, TrifleApp.AppLive} ->
        true

      {:dashboards, TrifleApp.DashboardsLive} ->
        true

      {:dashboards, TrifleApp.DashboardLive} ->
        true

      {:monitors, TrifleApp.MonitorsLive} ->
        true

      {:monitors, TrifleApp.MonitorLive} ->
        true

      {:explore, TrifleApp.ExploreLive} ->
        true

      {:projects, TrifleApp.ProjectsLive} ->
        true

      {:projects, TrifleApp.ProjectSettingsLive} ->
        true

      {:projects, TrifleApp.ProjectTranspondersLive} ->
        true

      {:projects, TrifleApp.ProjectBillingLive} ->
        true

      {:databases, TrifleApp.DatabasesLive} ->
        true

      {:databases, TrifleApp.DatabaseTranspondersLive} ->
        true

      {:databases, TrifleApp.DatabaseSettingsLive} ->
        true

      {:databases, TrifleApp.DatabaseRedirectLive} ->
        true

      {:chat, TrifleApp.ChatLive} ->
        true

      {:organization, TrifleApp.OrganizationRedirectLive} ->
        true

      {:organization, TrifleApp.OrganizationProfileLive} ->
        true

      {:organization, TrifleApp.OrganizationUsersLive} ->
        true

      {:organization, TrifleApp.OrganizationSSOLive} ->
        true

      {:organization, TrifleApp.OrganizationDeliveryLive} ->
        true

      {:organization, TrifleApp.OrganizationTokensLive} ->
        true

      {:organization, TrifleApp.OrganizationBillingLive} ->
        true

      {:dashboards, _} ->
        Map.get(socket.assigns, :nav_section) == :dashboards

      {:monitors, _} ->
        Map.get(socket.assigns, :nav_section) == :monitors

      {:home, _} ->
        Map.get(socket.assigns, :nav_section) == :home

      {:projects, _} ->
        Map.get(socket.assigns, :nav_section) == :projects

      {:databases, _} ->
        Map.get(socket.assigns, :nav_section) == :databases

      {:explore, _} ->
        Map.get(socket.assigns, :nav_section) == :explore

      {:chat, _} ->
        Map.get(socket.assigns, :nav_section) == :chat

      {:organization, _} ->
        Map.get(socket.assigns, :nav_section) == :organization

      _ ->
        false
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
