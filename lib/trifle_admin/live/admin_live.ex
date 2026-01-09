defmodule TrifleAdmin.AdminLive do
  use TrifleAdmin, :live_view

  alias Trifle.Accounts
  alias Trifle.Monitors
  alias Trifle.Organizations

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Admin Overview") |> assign_counts()}
  end

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <div class="sm:flex sm:items-center">
        <div class="sm:flex-auto">
          <h1 class="text-base font-semibold leading-6 text-gray-900 dark:text-white">
            Admin Overview
          </h1>
          <p class="mt-2 text-sm text-gray-700 dark:text-gray-300">
            A quick snapshot of system activity and configured resources.
          </p>
        </div>
      </div>

      <div class="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <.summary_card title="Organizations" value={@counts.organizations} subtitle="Total orgs" />
        <.summary_card title="Users" value={@counts.users} subtitle="Registered users">
          <:footer>
            <div class="mt-3 text-xs text-gray-500 dark:text-gray-400 space-y-2">
              <div class="flex flex-wrap items-center gap-3">
                <span class="font-medium text-gray-700 dark:text-gray-300">Org roles</span>
                <span class="inline-flex items-center gap-2">
                  <span class="h-2 w-2 rounded-full bg-sky-400"></span>
                  Owners
                  <span class="font-semibold text-gray-900 dark:text-white">
                    {@counts.user_roles.owners}
                  </span>
                </span>
                <span class="inline-flex items-center gap-2">
                  <span class="h-2 w-2 rounded-full bg-amber-400"></span>
                  Org admins
                  <span class="font-semibold text-gray-900 dark:text-white">
                    {@counts.user_roles.admins}
                  </span>
                </span>
                <span class="inline-flex items-center gap-2">
                  <span class="h-2 w-2 rounded-full bg-slate-400"></span>
                  Members
                  <span class="font-semibold text-gray-900 dark:text-white">
                    {@counts.user_roles.members}
                  </span>
                </span>
                <%= if @counts.user_roles.unassigned > 0 do %>
                  <span class="inline-flex items-center gap-2">
                    <span class="h-2 w-2 rounded-full bg-gray-300"></span>
                    Unassigned
                    <span class="font-semibold text-gray-900 dark:text-white">
                      {@counts.user_roles.unassigned}
                    </span>
                  </span>
                <% end %>
              </div>
              <div class="flex flex-wrap items-center gap-3">
                <span class="font-medium text-gray-700 dark:text-gray-300">System access</span>
                <span class="inline-flex items-center gap-2">
                  <span class="h-2 w-2 rounded-full bg-teal-400"></span>
                  System admins
                  <span class="font-semibold text-gray-900 dark:text-white">
                    {@counts.system_admins}
                  </span>
                </span>
                <span class="inline-flex items-center gap-2">
                  <span class="h-2 w-2 rounded-full bg-gray-300"></span>
                  Standard users
                  <span class="font-semibold text-gray-900 dark:text-white">
                    {@counts.standard_users}
                  </span>
                </span>
              </div>
            </div>
          </:footer>
        </.summary_card>
        <.summary_card title="Projects" value={@counts.projects} subtitle="Active projects" />
        <.summary_card title="Databases" value={@counts.databases} subtitle="Configured sources" />
        <.summary_card title="Dashboards" value={@counts.dashboards} subtitle="Saved dashboards" />
        <.summary_card title="Monitors" value={@counts.monitors_total} subtitle="Configured monitors">
          <:footer>
            <div class="mt-3 flex items-center gap-4 text-xs text-gray-500 dark:text-gray-400">
              <span class="inline-flex items-center gap-2">
                <span class="h-2 w-2 rounded-full bg-red-400"></span>
                Triggered
                <span class="font-semibold text-gray-900 dark:text-white">
                  {@counts.monitors_triggered}
                </span>
              </span>
              <span class="inline-flex items-center gap-2">
                <span class="h-2 w-2 rounded-full bg-emerald-400"></span>
                Idle
                <span class="font-semibold text-gray-900 dark:text-white">
                  {@counts.monitors_idle}
                </span>
              </span>
            </div>
          </:footer>
        </.summary_card>
      </div>
    </div>
    """
  end

  defp assign_counts(socket) do
    monitors_total = Monitors.count_all_monitors()
    monitors_idle = Monitors.count_idle_monitors()
    monitors_triggered = max(monitors_total - monitors_idle, 0)

    users_total = Accounts.count_users()
    system_admins = Accounts.count_system_admins()
    standard_users = max(users_total - system_admins, 0)
    role_counts = Organizations.count_memberships_by_role()
    owners = Map.get(role_counts, "owner", 0)
    admins = Map.get(role_counts, "admin", 0)
    members = Map.get(role_counts, "member", 0)
    assigned = owners + admins + members
    unassigned = max(users_total - assigned, 0)

    assign(socket,
      counts: %{
        organizations: Organizations.count_organizations(),
        users: users_total,
        system_admins: system_admins,
        standard_users: standard_users,
        user_roles: %{
          owners: owners,
          admins: admins,
          members: members,
          unassigned: unassigned
        },
        projects: Organizations.count_projects(),
        databases: Organizations.count_databases(),
        dashboards: Organizations.count_dashboards(),
        monitors_total: monitors_total,
        monitors_triggered: monitors_triggered,
        monitors_idle: monitors_idle
      }
    )
  end

  attr :title, :string, required: true
  attr :value, :integer, required: true
  attr :subtitle, :string, default: nil

  slot :footer

  defp summary_card(assigns) do
    ~H"""
    <div class="rounded-xl border border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-800 p-4 shadow-sm">
      <div class="flex items-start justify-between">
        <div>
          <p class="text-sm font-medium text-gray-600 dark:text-gray-300">{@title}</p>
          <p class="mt-2 text-3xl font-semibold text-gray-900 dark:text-white">{@value}</p>
          <%= if @subtitle do %>
            <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">{@subtitle}</p>
          <% end %>
        </div>
      </div>
      <%= if @footer != [] do %>
        {render_slot(@footer)}
      <% end %>
    </div>
    """
  end
end
