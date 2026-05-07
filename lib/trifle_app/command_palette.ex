defmodule TrifleApp.CommandPalette do
  @moduledoc """
  Builds the app-wide command palette navigation items.
  """

  use TrifleApp, :verified_routes

  alias Trifle.Accounts.User
  alias Trifle.Monitors
  alias Trifle.Monitors.Monitor
  alias Trifle.Organizations

  alias Trifle.Organizations.{
    Dashboard,
    Database,
    OrganizationMembership,
    Project
  }

  alias TrifleApp.HomeData

  @recent_limit 5
  @triggered_limit 5

  def items(%User{} = user, %OrganizationMembership{} = membership) do
    action_items() ++
      recent_dashboard_items(user, membership) ++
      triggered_monitor_items(user, membership) ++
      dashboard_items(user, membership) ++
      monitor_items(user, membership) ++
      database_items(membership) ++
      project_items(membership)
  end

  def items(_, _), do: []

  defp action_items do
    [
      item(
        id: "action:home",
        title: "Home",
        subtitle: "Open workspace home",
        token: "H",
        icon: "sidebar-home",
        to: ~p"/",
        default_section: "Actions",
        search_section: "Actions",
        search_aliases: ["home", "overview"]
      ),
      item(
        id: "action:baker",
        title: "Mr. Baker",
        subtitle: "Open chat assistant",
        token: "B",
        icon: "chef-hat-alt-2",
        action: "chat",
        default_section: "Actions",
        search_section: "Actions",
        search_aliases: ["baker", "chat", "assistant"]
      ),
      item(
        id: "action:dashboards",
        title: "Dashboards",
        subtitle: "Browse saved dashboards",
        token: "D",
        icon: "sidebar-dashboards",
        to: ~p"/dashboards",
        default_section: "Actions",
        search_section: "Actions"
      ),
      item(
        id: "action:monitors",
        title: "Monitors",
        subtitle: "Review reports and alerts",
        token: "M",
        icon: "sidebar-monitors",
        to: ~p"/monitors",
        default_section: "Actions",
        search_section: "Actions"
      ),
      item(
        id: "action:explore",
        title: "Explore",
        subtitle: "Open metric exploration",
        token: "E",
        icon: "sidebar-explore",
        to: ~p"/explore",
        default_section: "Actions",
        search_section: "Actions"
      ),
      Trifle.Config.projects_enabled?() &&
        item(
          id: "action:projects",
          title: "Projects",
          subtitle: "Browse metric projects",
          token: "P",
          icon: "sidebar-projects",
          to: ~p"/projects",
          default_section: "Actions",
          search_section: "Actions"
        ),
      item(
        id: "action:databases",
        title: "Databases",
        subtitle: "Browse configured databases",
        token: "DB",
        icon: "sidebar-databases",
        to: ~p"/dbs",
        default_section: "Actions",
        search_section: "Actions"
      )
    ]
    |> Enum.filter(& &1)
  end

  defp recent_dashboard_items(%User{} = user, %OrganizationMembership{} = membership) do
    user
    |> HomeData.recent_dashboard_visits(membership, @recent_limit)
    |> Enum.map(fn visit ->
      dashboard = visit.dashboard

      item(
        id: "recent:dashboard:#{dashboard.id}",
        title: dashboard_title(dashboard),
        subtitle: "Recent dashboard",
        token: "D",
        icon: "sidebar-dashboards",
        to: ~p"/dashboards/#{dashboard.id}",
        default_section: "Recent",
        search_section: nil,
        searchable?: false,
        search_aliases: ["dashboard", "recent"]
      )
    end)
  end

  defp triggered_monitor_items(%User{} = user, %OrganizationMembership{} = membership) do
    user
    |> HomeData.triggered_monitors(membership, limit: @triggered_limit, preload: [:dashboard])
    |> Enum.map(fn monitor ->
      item(
        id: "triggered:monitor:#{monitor.id}",
        title: monitor_title(monitor),
        subtitle: "Triggered monitor · #{humanize_status(monitor.trigger_status)}",
        token: "M",
        icon: "sidebar-monitors",
        to: ~p"/monitors/#{monitor.id}",
        default_section: "Triggered",
        search_section: nil,
        searchable?: false,
        search_aliases: ["monitor", "triggered", humanize_status(monitor.trigger_status)]
      )
    end)
  end

  defp dashboard_items(%User{} = user, %OrganizationMembership{} = membership) do
    user
    |> Organizations.list_all_dashboards_for_membership(membership)
    |> Enum.map(fn dashboard ->
      item(
        id: "dashboard:#{dashboard.id}",
        title: dashboard_title(dashboard),
        subtitle: "Dashboard",
        token: "D",
        icon: "sidebar-dashboards",
        to: ~p"/dashboards/#{dashboard.id}",
        default_section: nil,
        search_section: "Dashboards",
        search_aliases: ["dashboard", "dashboards"]
      )
    end)
  end

  defp monitor_items(%User{} = user, %OrganizationMembership{} = membership) do
    user
    |> Monitors.list_monitors_for_membership(membership)
    |> Enum.map(fn monitor ->
      item(
        id: "monitor:#{monitor.id}",
        title: monitor_title(monitor),
        subtitle: "Monitor · #{humanize_status(monitor.status)}",
        token: "M",
        icon: "sidebar-monitors",
        to: ~p"/monitors/#{monitor.id}",
        default_section: nil,
        search_section: "Monitors",
        search_aliases: ["monitor", "monitors", humanize_status(monitor.status)]
      )
    end)
  end

  defp database_items(%OrganizationMembership{} = membership) do
    membership.organization_id
    |> Organizations.list_databases_for_org()
    |> Enum.map(fn database ->
      item(
        id: "database:#{database.id}",
        title: database_title(database),
        subtitle: "Database",
        token: "DB",
        icon: "sidebar-databases",
        to: ~p"/dbs/#{database.id}/transponders",
        default_section: nil,
        search_section: "Databases",
        search_aliases: ["database", "databases", database.driver]
      )
    end)
  end

  defp project_items(%OrganizationMembership{} = membership) do
    if Trifle.Config.projects_enabled?() do
      membership
      |> Organizations.list_projects_for_membership()
      |> Enum.map(fn project ->
        item(
          id: "project:#{project.id}",
          title: project_title(project),
          subtitle: "Project",
          token: "P",
          icon: "sidebar-projects",
          to: ~p"/projects/#{project.id}/transponders",
          default_section: nil,
          search_section: "Projects",
          search_aliases: ["project", "projects"]
        )
      end)
    else
      []
    end
  end

  defp item(opts) do
    id = Keyword.fetch!(opts, :id)
    title = opts |> Keyword.fetch!(:title) |> present_text("Untitled")
    subtitle = opts |> Keyword.get(:subtitle) |> present_text(nil)
    search_aliases = opts |> Keyword.get(:search_aliases, []) |> List.wrap()

    %{
      "id" => id,
      "dom_id" => dom_id(id),
      "title" => title,
      "subtitle" => subtitle,
      "token" => Keyword.get(opts, :token, ""),
      "icon" => Keyword.get(opts, :icon),
      "to" => Keyword.get(opts, :to),
      "action" => Keyword.get(opts, :action),
      "default_section" => Keyword.get(opts, :default_section),
      "search_section" => Keyword.get(opts, :search_section),
      "searchable" => Keyword.get(opts, :searchable?, true),
      "search_text" => search_text([title, subtitle, search_aliases])
    }
  end

  defp dashboard_title(%Dashboard{name: name, group_id: group_id}) do
    groups =
      group_id
      |> dashboard_group_names()
      |> Enum.reject(&blank?/1)

    name = present_text(name, "Untitled dashboard")

    case groups do
      [] -> name
      list -> Enum.join(list ++ [name], " / ")
    end
  end

  defp dashboard_group_names(nil), do: []

  defp dashboard_group_names(group_id) do
    group_id
    |> Organizations.get_dashboard_group_chain()
    |> Enum.map(& &1.name)
  rescue
    _ -> []
  end

  defp monitor_title(%Monitor{name: name}), do: present_text(name, "Untitled monitor")
  defp database_title(%Database{display_name: name}), do: present_text(name, "Untitled database")
  defp project_title(%Project{name: name}), do: present_text(name, "Untitled project")

  defp humanize_status(nil), do: "Idle"

  defp humanize_status(status) when is_atom(status) do
    status
    |> Atom.to_string()
    |> humanize_status()
  end

  defp humanize_status(status) when is_binary(status) do
    status
    |> String.replace("_", " ")
    |> String.trim()
    |> String.capitalize()
  end

  defp present_text(value, fallback) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> fallback
      text -> text
    end
  end

  defp present_text(nil, fallback), do: fallback
  defp present_text(value, _fallback), do: to_string(value)

  defp blank?(value), do: is_nil(present_text(value, nil))

  defp search_text(parts) do
    parts
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.join(" ")
    |> String.downcase()
  end

  defp dom_id(id) do
    suffix =
      id
      |> to_string()
      |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")

    "command-palette-item-#{suffix}"
  end
end
