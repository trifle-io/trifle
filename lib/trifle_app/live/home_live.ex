defmodule TrifleApp.HomeLive do
  use TrifleApp, :live_view

  alias Decimal
  alias Trifle.Monitors
  alias Trifle.Organizations
  alias TrifleApp.ExploreCore
  alias TrifleApp.HomeData
  alias Trifle.Stats.Source

  @recent_limit 5

  def mount(_params, _session, %{assigns: %{current_membership: nil}} = socket) do
    {:ok, redirect(socket, to: ~p"/organization/profile")}
  end

  def mount(
        _params,
        _session,
        %{assigns: %{current_user: user, current_membership: membership}} = socket
      ) do
    {:ok,
     socket
     |> assign(:page_title, "Home")
     |> assign(:breadcrumb_links, ["Home"])
     |> assign(:nav_section, :home)
     |> assign(:recent_limit, @recent_limit)
     |> assign(:current_user, user)
     |> assign(:current_membership, membership)
     |> load_home_data(user, membership)}
  end

  def handle_params(_params, _uri, %{assigns: %{current_user: user, current_membership: membership}} = socket) do
    {:noreply, load_home_data(socket, user, membership)}
  end

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-6">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-baseline sm:justify-between mb-6">
        <div>
          <h1 class="text-2xl font-semibold text-gray-900 dark:text-white">Welcome {welcome_name(@current_user)}!</h1>
          <p class="text-sm text-gray-600 dark:text-slate-400">
            Quick pulse of your dashboards, monitors, and sources.
          </p>
        </div>
      </div>

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <section class="rounded-xl border border-gray-200 bg-white p-4 shadow-sm dark:border-slate-700 dark:bg-slate-800 lg:order-1 order-2">
          <div class="flex items-center justify-between mb-3">
            <div>
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
                Recent Dashboards
              </h2>
              <p class="text-sm text-gray-500 dark:text-slate-400">Last {@recent_limit} you opened</p>
            </div>
            <.link
              navigate={~p"/dashboards"}
              class="inline-flex items-center gap-1 rounded-lg border border-teal-600 px-2.5 py-1.5 text-sm font-medium text-teal-700 transition hover:bg-teal-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600 dark:border-teal-400 dark:text-teal-200 dark:hover:bg-teal-900/40"
            >
              <span class="sr-only">View dashboards</span>
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-4 w-4">
                <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3" />
              </svg>
            </.link>
          </div>

          <%= cond do %>
            <% @dashboards_count == 0 and @has_sources? -> %>
              <div class="rounded-lg border border-dashed border-gray-200 bg-gray-50 px-4 py-5 text-sm text-gray-600 dark:border-slate-700 dark:bg-slate-900/40 dark:text-slate-300">
                You don't have any dashboards yet.
                <div class="mt-3">
                  <.link
                    navigate={~p"/dashboards/new"}
                    class="inline-flex items-center gap-2 rounded-lg bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-teal-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-4 w-4">
                      <path d="M10.75 4.75a.75.75 0 00-1.5 0v4.5h-4.5a.75.75 0 000 1.5h4.5v4.5a.75.75 0 001.5 0v-4.5h4.5a.75.75 0 000-1.5h-4.5v-4.5z" />
                    </svg>
                    Create your first dashboard
                  </.link>
                </div>
              </div>
            <% Enum.empty?(@dashboard_visits) -> %>
              <div class="rounded-lg border border-dashed border-gray-200 bg-gray-50 px-4 py-5 text-sm text-gray-600 dark:border-slate-700 dark:bg-slate-900/40 dark:text-slate-300">
                No recent visits yet.
                <.link navigate={~p"/dashboards"} class="ml-1 font-medium text-teal-600 hover:text-teal-700 dark:text-teal-300">
                  Browse dashboards
                </.link>
                to start exploring.
              </div>
            <% @dashboards_count == 0 -> %>
              <div class="rounded-lg border border-dashed border-gray-200 bg-gray-50 px-4 py-5 text-sm text-gray-600 dark:border-slate-700 dark:bg-slate-900/40 dark:text-slate-300">
                You don't have any dashboards yet. Add a source to get started.
              </div>
            <% true -> %>
              <ul class="divide-y divide-gray-200 dark:divide-slate-700">
                <%= for visit <- @dashboard_visits do %>
                  <li class="py-3 flex items-center justify-between">
                    <div>
                      <.link
                        navigate={~p"/dashboards/#{visit.dashboard.id}"}
                        class="text-sm font-semibold text-gray-900 hover:text-teal-600 dark:text-white dark:hover:text-teal-300"
                      >
                        {dashboard_full_name(visit.dashboard)}
                      </.link>
                      <div class="text-xs text-gray-500 dark:text-slate-400">
                        Last opened {relative_time(visit.last_viewed_at)}
                      </div>
                    </div>
                  </li>
                <% end %>
              </ul>
          <% end %>
        </section>

        <section class="rounded-xl border border-gray-200 bg-white p-4 shadow-sm dark:border-slate-700 dark:bg-slate-800 lg:order-2 order-1">
          <div class="flex items-center justify-between mb-3">
            <div>
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
                Triggered Monitors
              </h2>
              <p class="text-sm text-gray-500 dark:text-slate-400">Alerts firing right now</p>
            </div>
            <.link
              navigate={~p"/monitors"}
              class="inline-flex items-center gap-1 rounded-lg border border-teal-600 px-2.5 py-1.5 text-sm font-medium text-teal-700 transition hover:bg-teal-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600 dark:border-teal-400 dark:text-teal-200 dark:hover:bg-teal-900/40"
            >
              <span class="sr-only">View monitors</span>
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-4 w-4">
                <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3" />
              </svg>
            </.link>
          </div>

          <%= cond do %>
            <% @monitors_count == 0 and @has_sources? -> %>
              <div class="rounded-lg border border-dashed border-gray-200 bg-gray-50 px-4 py-5 text-sm text-gray-600 dark:border-slate-700 dark:bg-slate-900/40 dark:text-slate-300">
                You don't have any monitors yet.
                <div class="mt-3">
                  <.link
                    navigate={~p"/monitors/new"}
                    class="inline-flex items-center gap-2 rounded-lg bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-teal-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-4 w-4">
                      <path d="M10.75 4.75a.75.75 0 00-1.5 0v4.5h-4.5a.75.75 0 000 1.5h4.5v4.5a.75.75 0 001.5 0v-4.5h4.5a.75.75 0 000-1.5h-4.5v-4.5z" />
                    </svg>
                    Create a monitor
                  </.link>
                </div>
              </div>
            <% Enum.empty?(@triggered_monitors) -> %>
              <div class="rounded-lg border border-dashed border-gray-200 bg-gray-50 px-4 py-5 text-sm text-gray-600 dark:border-slate-700 dark:bg-slate-900/40 dark:text-slate-300">
                Everything is running smoothly. No monitors are currently triggered.
              </div>
            <% @monitors_count == 0 -> %>
              <div class="rounded-lg border border-dashed border-gray-200 bg-gray-50 px-4 py-5 text-sm text-gray-600 dark:border-slate-700 dark:bg-slate-900/40 dark:text-slate-300">
                You don't have any monitors yet. Add a source to get started.
              </div>
            <% true -> %>
              <ul class="divide-y divide-gray-200 dark:divide-slate-700">
                <%= for monitor <- @triggered_monitors do %>
                  <li class="py-3 flex items-center justify-between gap-3">
                    <div class="flex items-center gap-3">
                      <span class="inline-flex h-9 w-9 items-center justify-center rounded-full bg-red-100 text-red-700 ring-1 ring-red-200 dark:bg-red-900/40 dark:text-red-200 dark:ring-red-800/80">
                        🚨
                      </span>
                      <div>
                        <.link
                          navigate={~p"/monitors/#{monitor.id}"}
                          class="text-sm font-semibold text-gray-900 hover:text-teal-600 dark:text-white dark:hover:text-teal-300"
                        >
                          {monitor.name}
                        </.link>
                        <div class="text-xs text-gray-500 dark:text-slate-400">
                          Status: {humanize_status(monitor.trigger_status)}
                          <%= if monitor.dashboard do %>
                            • Dashboard: <.link
                              navigate={~p"/dashboards/#{monitor.dashboard_id}"}
                              class="hover:text-teal-600 dark:hover:text-teal-300"
                            >
                              {monitor.dashboard.name}
                            </.link>
                          <% end %>
                        </div>
                      </div>
                    </div>
                    <span class="inline-flex items-center rounded-full bg-red-50 px-2 py-1 text-xs font-medium text-red-700 ring-1 ring-inset ring-red-200 dark:bg-red-900/40 dark:text-red-200 dark:ring-red-800/80">
                      Alerting
                    </span>
                  </li>
                <% end %>
              </ul>
          <% end %>
        </section>
      </div>

      <section class="mt-6">
        <div class="flex flex-col gap-2 sm:flex-row sm:items-baseline sm:justify-between mb-3">
          <div>
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">Sources</h2>
            <p class="text-sm text-gray-500 dark:text-slate-400">
              24h activity across your databases and projects.
            </p>
          </div>
        </div>

        <%= if Enum.empty?(@source_activity) do %>
          <div class="rounded-lg border border-dashed border-gray-200 bg-gray-50 px-4 py-5 text-sm text-gray-600 dark:border-slate-700 dark:bg-slate-900/40 dark:text-slate-300">
            Connect a data source to see activity.
            <.link navigate={~p"/dbs/new"} class="ml-1 font-medium text-teal-600 hover:text-teal-700 dark:text-teal-300">
              Add a database
            </.link>
            <%= if Trifle.Config.projects_enabled?() do %>
              <span class="mx-1 text-gray-400 dark:text-slate-500">|</span>
              <.link navigate={~p"/projects/new"} class="font-medium text-teal-600 hover:text-teal-700 dark:text-teal-300">
                Add a project
              </.link>
            <% end %>
          </div>
        <% else %>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
            <%= for activity <- @source_activity do %>
              <div class="relative overflow-hidden rounded-xl border border-gray-200 bg-white p-4 pb-10 shadow-sm dark:border-slate-700 dark:bg-slate-800">
                <div class="flex items-start justify-between gap-3 pb-4">
                  <div>
                    <div class="text-base font-semibold text-gray-900 dark:text-white flex items-center gap-2">
                      <span class="inline-flex h-8 w-8 items-center justify-center rounded-md bg-gray-100 text-gray-600 dark:bg-slate-700 dark:text-slate-200">
                        <%= source_icon(activity.source) %>
                      </span>
                      <span class="truncate">
                        {Source.display_name(activity.source)}
                      </span>
                    </div>
                    <div class="text-xs text-gray-500 dark:text-slate-400">
                      Last event: {last_event_label(activity.last_event_at)}
                    </div>
                  </div>
                    <div class="text-right">
                      <div class="text-xl font-semibold text-teal-700 dark:text-teal-300">
                        {ExploreCore.format_number(activity.total)}
                      </div>
                    <div class="text-xs text-gray-500 dark:text-slate-400">events</div>
                  </div>
                </div>

                <%= if activity_error = Map.get(activity, :error) do %>
                  <div class="rounded-lg bg-red-50 px-3 py-2 text-xs text-red-700 ring-1 ring-inset ring-red-200 dark:bg-red-900/30 dark:text-red-200 dark:ring-red-800/60">
                    Unable to load activity ({format_error(activity_error)})
                  </div>
                <% else %>
                  <div
                    id={"sparkline-#{sparkline_dom_id(activity)}"}
                    class="pointer-events-none absolute inset-x-0 bottom-0 h-14"
                    phx-hook="HomeSparkline"
                    data-series={Jason.encode!(sparkline_series(activity.timeline))}
                  >
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  defp load_home_data(socket, user, membership) do
    socket
    |> assign(:dashboard_visits, HomeData.recent_dashboard_visits(user, membership, @recent_limit))
    |> assign(:dashboards_count, Organizations.count_dashboards_for_membership(user, membership))
    |> assign(:triggered_monitors, HomeData.triggered_monitors(user, membership, preload: [:dashboard]))
    |> assign(:monitors_count, Monitors.count_monitors_for_membership(membership))
    |> assign(:source_activity, HomeData.source_activity(membership))
    |> assign(:has_sources?, has_sources?(membership))
  end

  defp dashboard_full_name(%{name: name, group_id: group_id}) do
    groups =
      group_id
      |> Organizations.get_dashboard_group_chain()
      |> Enum.map(& &1.name)

    case groups do
      [] -> name
      list -> Enum.join(list ++ [name], " / ")
    end
  end

  defp source_icon(source) do
    assigns = %{type: Source.type(source)}

    ~H"""
    <%= case @type do %>
      <% :database -> %>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="h-5 w-5">
          <ellipse cx="12" cy="6" rx="7" ry="3"></ellipse>
          <path d="M5 6v6c0 1.66 3.134 3 7 3s7-1.34 7-3V6" stroke-linecap="round"></path>
          <path d="M5 12v6c0 1.66 3.134 3 7 3s7-1.34 7-3v-6" stroke-linecap="round"></path>
        </svg>

      <% :project -> %>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="h-5 w-5">
          <path
            d="M3.75 6.75A2.25 2.25 0 0 1 6 4.5h4.379a1.5 1.5 0 0 1 1.06.44l1.621 1.62H18a2.25 2.25 0 0 1 2.25 2.25v9a2.25 2.25 0 0 1-2.25 2.25H6A2.25 2.25 0 0 1 3.75 18V6.75Z"
            stroke-linejoin="round"
          />
        </svg>

      <% _ -> %>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="h-5 w-5">
          <path d="M4.5 7.5h15" stroke-linecap="round" />
          <path d="M6 5.25h12.75A1.75 1.75 0 0 1 20.5 7v10.25a1.75 1.75 0 0 1-1.75 1.75H6a1.75 1.75 0 0 1-1.75-1.75V7A1.75 1.75 0 0 1 6 5.25Z" />
          <path d="M9 3.5h6" stroke-linecap="round" />
        </svg>
    <% end %>
    """
  end

  defp humanize_status(nil), do: "alerting"

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

  defp last_event_label(nil), do: "No events yet"
  defp last_event_label(%DateTime{} = dt), do: relative_time(dt)
  defp last_event_label(%NaiveDateTime{} = ndt), do: ndt |> DateTime.from_naive!("Etc/UTC") |> relative_time()
  defp last_event_label(_), do: "—"

  defp format_error({:exception, %struct{} = error}) do
    "#{inspect(struct)}: #{Exception.message(error)}"
  end

  defp format_error({:exception, error}) do
    "Exception: #{inspect(error)}"
  end

  defp format_error(%struct{} = error) do
    "#{inspect(struct)}: #{Exception.message(error)}"
  end

  defp format_error(error), do: inspect(error)

  defp relative_time(nil), do: "—"

  defp relative_time(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> relative_time()
  end

  defp relative_time(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, dt, :second)

    cond do
      diff_seconds < 60 ->
        "#{max(diff_seconds, 0)}s ago"

      diff_seconds < 3600 ->
        minutes = div(diff_seconds, 60)
        "#{minutes}m ago"

      diff_seconds < 86_400 ->
        hours = div(diff_seconds, 3600)
        minutes = rem(div(diff_seconds, 60), 60)

        if minutes > 0 do
          "#{hours}h #{minutes}m ago"
        else
          "#{hours}h ago"
        end

      diff_seconds < 2_592_000 ->
        days = div(diff_seconds, 86_400)
        "#{days}d ago"

      true ->
        Calendar.strftime(dt, "%b %-d, %Y")
    end
  rescue
    _ -> Calendar.strftime(dt, "%b %-d, %Y")
  end

  defp has_sources?(membership) do
    membership
    |> Source.list_for_membership()
    |> Enum.any?()
  end

  defp sparkline_dom_id(activity) do
    source = activity.source
    "#{Source.type(source)}-#{Source.id(source)}"
  end

  defp sparkline_series(timeline) do
    timeline
    |> Enum.map(fn
      %{at: %DateTime{} = dt, value: value} -> [DateTime.to_unix(dt, :millisecond), normalize_number(value)]
      %{at: %NaiveDateTime{} = ndt, value: value} ->
        ndt
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.to_unix(:millisecond)
        |> then(&[&1, normalize_number(value)])

      %{at: at, value: value} when is_integer(at) -> [at, normalize_number(value)]
      %{at: at, value: value} when is_float(at) -> [round(at), normalize_number(value)]
      %{value: value} -> [System.system_time(:millisecond), normalize_number(value)]
      other -> [System.system_time(:millisecond), normalize_number(Map.get(other, :value))]
    end)
  end

  defp normalize_number(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp normalize_number(value) when is_number(value), do: value * 1.0
  defp normalize_number(_), do: 0.0

  defp welcome_name(%{name: name}) when is_binary(name) do
    trimmed = String.trim(name)
    if trimmed == "", do: welcome_name(:fallback), else: trimmed
  end

  defp welcome_name(%{email: email}) when is_binary(email), do: email
  defp welcome_name(:fallback), do: "back"
  defp welcome_name(_), do: "back"
end
