defmodule TrifleApp.Layouts do
  use TrifleApp, :html

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
        "group rounded-[1.15rem] text-sm font-semibold transition duration-200 ease-out hover:-translate-y-px focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500/70 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-slate-900",
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

  def compact_tooltip_expr(text) when is_binary(text) do
    "compact ? #{Phoenix.json_library().encode!(text)} : null"
  end

  def secondary_nav_items(current_user, current_membership) do
    [
      current_membership && organization_item(),
      current_user && current_user.is_admin && admin_console_item()
    ]
    |> Enum.filter(& &1)
  end

  def current_nav_label(socket) do
    case Enum.find(all_nav_items(), &active_nav?(socket, &1.menu)) do
      %{label: label} -> label
      _ -> "Workspace"
    end
  end

  defp organization_item do
    %{menu: :organization, label: "Organization", to: ~p"/organization/profile", icon: "sidebar-organization"}
  end

  defp admin_console_item do
    %{menu: :admin_console, label: "Admin Console", to: "/admin", icon: "sidebar-admin"}
  end

  defp all_nav_items do
    nav_items() ++ [organization_item()]
  end

  defp sidebar_link_classes(true) do
    "bg-[linear-gradient(135deg,rgba(20,184,166,0.18),rgba(255,255,255,0.88))] text-slate-900 ring-1 ring-inset ring-teal-500/20 shadow-[0_16px_34px_-26px_rgba(13,148,136,0.8)] dark:bg-[linear-gradient(135deg,rgba(45,212,191,0.18),rgba(15,23,42,0.92))] dark:text-white dark:ring-teal-300/20"
  end

  defp sidebar_link_classes(false) do
    "text-slate-600 hover:bg-white/95 hover:text-slate-950 hover:shadow-[0_14px_24px_-24px_rgba(15,23,42,0.45)] dark:text-slate-300 dark:hover:bg-white/[0.06] dark:hover:text-white"
  end

  defp sidebar_icon_shell_classes(true) do
    "bg-teal-500/15 text-teal-700 ring-teal-500/20 shadow-inner shadow-white/60 dark:bg-teal-400/14 dark:text-teal-200 dark:ring-teal-300/20 dark:shadow-transparent"
  end

  defp sidebar_icon_shell_classes(false) do
    "bg-white/90 text-slate-500 ring-slate-200/80 group-hover:bg-white group-hover:text-slate-800 dark:bg-slate-900/80 dark:text-slate-400 dark:ring-white/10 dark:group-hover:bg-slate-800 dark:group-hover:text-slate-100"
  end

  defp sidebar_icon_classes(true), do: "text-teal-700 dark:text-teal-200"

  defp sidebar_icon_classes(false) do
    "text-inherit"
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

    img = "https://www.gravatar.com/avatar/#{hash}?s=150&d=identicon"
    Phoenix.HTML.raw("<img src=\"#{img}\" alt='' class='h-8 w-8 rounded-full'></img>")
  end
end
