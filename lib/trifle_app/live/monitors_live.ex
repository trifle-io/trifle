defmodule TrifleApp.MonitorsLive do
  use TrifleApp, :live_view

  alias Ecto.Changeset
  alias Trifle.Monitors
  alias Trifle.Monitors.Monitor
  alias Trifle.Organizations
  alias Trifle.Stats.Source, as: StatsSource
  alias TrifleApp.MonitorsLive.FormComponent
  require Logger

  @impl true
  def mount(_params, _session, %{assigns: %{current_membership: nil}} = socket) do
    {:ok, redirect(socket, to: ~p"/organization/profile")}
  end

  def mount(
        _params,
        _session,
        %{assigns: %{current_user: user, current_membership: membership}} = socket
      ) do
    Logger.debug("[MonitorsLive] mount for membership=#{membership.id}")

    {:ok,
     socket
     |> assign(:page_title, "Monitors")
     |> assign(:breadcrumb_links, ["Monitors"])
     |> assign(:nav_section, :monitors)
     |> assign(:current_membership, membership)
     |> assign(:current_user, user)
     |> assign(:sources, load_sources(membership))
     |> assign(:monitors, load_monitors(user, membership))
     |> assign(:modal_monitor, nil)
     |> assign(:modal_changeset, nil)
     |> assign(:dashboards, load_dashboards(user, membership))
     |> fetch_delivery_options()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:modal_monitor, nil)
    |> assign(:modal_changeset, nil)
  end

  defp apply_action(socket, :new, _params) do
    membership = socket.assigns.current_membership
    alert_defaults = Monitors.default_alert_settings()

    monitor =
      %Monitor{organization_id: membership.organization_id, status: :active, type: :report}
      |> Monitor.changeset(%{
        status: :active,
        type: :report,
        report_settings: Monitors.default_report_settings(),
        alert_metric_key: alert_defaults.alert_metric_key,
        alert_metric_path: alert_defaults.alert_metric_path,
        alert_timeframe: alert_defaults.alert_timeframe,
        alert_granularity: alert_defaults.alert_granularity
      })
      |> Changeset.apply_changes()

    changeset = Monitors.change_monitor(monitor, %{})

    socket
    |> assign(:modal_monitor, monitor)
    |> assign(:modal_changeset, changeset)
    |> assign(:page_title, "Create Monitor")
  end

  @impl true
  def handle_info({FormComponent, {:saved, _monitor}}, socket) do
    membership = socket.assigns.current_membership
    user = socket.assigns.current_user

    Logger.debug("[MonitorsLive] received saved message, reloading monitors")

    {:noreply,
     socket
     |> put_flash(:info, "Monitor saved")
     |> assign(:monitors, load_monitors(user, membership))
     |> assign(:sources, load_sources(membership))
     |> fetch_delivery_options()
     |> assign(:modal_monitor, nil)
     |> assign(:modal_changeset, nil)
     |> push_patch(to: ~p"/monitors")}
  end

  def handle_info({FormComponent, {:error, message}}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load_monitors(user, membership) do
    result = Monitors.list_monitors_for_membership(user, membership, preload: [:dashboard])
    Logger.debug("[MonitorsLive] loaded #{length(result)} monitors")
    result
  end

  defp load_dashboards(user, membership) do
    Organizations.list_all_dashboards_for_membership(user, membership)
  end

  defp load_sources(membership) do
    StatsSource.list_for_membership(membership)
  end

  defp fetch_delivery_options(socket) do
    membership = socket.assigns.current_membership
    Logger.debug("[MonitorsLive] fetching delivery options for membership=#{membership.id}")
    opts = Monitors.delivery_options_for_membership(membership)
    Logger.debug("[MonitorsLive] fetched #{length(opts)} delivery options")
    assign(socket, :delivery_options, opts)
  end

  defp monitor_schedule_label(%Monitor{type: :report, report_settings: settings}) do
    label =
      settings
      |> fetch_setting(:frequency, "weekly")
      |> format_setting_label()

    "#{label} schedule"
  end

  defp monitor_schedule_label(%Monitor{type: :alert} = monitor) do
    timeframe =
      case monitor.alert_timeframe do
        value when is_binary(value) ->
          trimmed = String.trim(value)
          if trimmed == "", do: nil, else: trimmed

        _ ->
          nil
      end

    case timeframe do
      nil -> "Alert monitor"
      value -> "Alert · #{value}"
    end
  end

  defp monitor_schedule_label(_), do: nil

  defp monitor_source_label(%Monitor{} = monitor, sources) do
    with {:ok, type, id} <- monitor_source_tuple(monitor),
         %StatsSource{} = source <- StatsSource.find_in_list(sources, type, id) do
      "#{source_type_label(type)} · #{StatsSource.display_name(source)}"
    else
      {:error, :missing} ->
        "Not set"

      _ ->
        case monitor_source_tuple(monitor) do
          {:ok, type, _id} -> "#{source_type_label(type)}"
          _ -> "Unknown"
        end
    end
  end

  defp monitor_source_tuple(%Monitor{source_type: type, source_id: id})
       when not is_nil(type) and not is_nil(id) do
    {:ok, type, id}
  end

  defp monitor_source_tuple(_), do: {:error, :missing}

  defp source_type_label(:database), do: "Database"
  defp source_type_label(:project), do: "Project"

  defp source_type_label(value) when is_atom(value) do
    value |> Atom.to_string() |> String.capitalize()
  end

  defp source_type_label(value), do: to_string(value)

  defp fetch_setting(settings, key, default) when is_map(settings) do
    Map.get(settings, key) || Map.get(settings, Atom.to_string(key)) || default
  end

  defp fetch_setting(_, _, default), do: default

  defp format_setting_label(value) when is_atom(value) do
    value |> Atom.to_string() |> format_setting_label()
  end

  defp format_setting_label(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.trim()
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_setting_label(_), do: "Custom"

  defp format_metric_path(%Monitor{} = monitor) do
    format_metric_path(%{
      metric_key: monitor.alert_metric_key,
      metric_path: monitor.alert_metric_path
    })
  end

  defp format_metric_path(%{metric_key: key, metric_path: path}) do
    format_metric_path(%{"metric_key" => key, "metric_path" => path})
  end

  defp format_metric_path(%{"metric_key" => key, "metric_path" => path}) do
    key = blank_if_nil(key)
    path = blank_if_nil(path)

    cond do
      key == "" and path == "" -> "—"
      path == "" -> key
      key == "" -> path
      true -> "#{key}##{path}"
    end
  end

  defp format_metric_path(_), do: "—"

  defp blank_if_nil(nil), do: ""
  defp blank_if_nil(value), do: to_string(value)

  defp monitor_icon(assigns) do
    ~H"""
    <span class={[
      "inline-flex h-10 w-10 items-center justify-center rounded-full text-white shadow-sm ring-1 ring-inset ring-black/5 dark:ring-white/10",
      Monitor.icon_color_class(@monitor)
    ]}>
      <%= if @monitor.type == :report do %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="h-5 w-5"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25M9 16.5v.75m3-3v3M15 12v5.25m-4.5-15H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z"
          />
        </svg>
      <% else %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="h-5 w-5"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"
          />
        </svg>
      <% end %>
    </span>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 class="text-base font-semibold leading-6 text-gray-900 dark:text-white">
            Your Monitors
          </h1>
          <p class="mt-2 text-sm text-gray-700 dark:text-gray-300">
            Define scheduled reports and flexible alerts that watch your metrics.
          </p>
        </div>
        <div class="flex gap-2">
          <.link
            patch={~p"/monitors/new"}
            aria-label="New Monitor"
            class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600"
          >
            <svg class="h-5 w-5 md:-ml-0.5 md:mr-1.5" viewBox="0 0 20 20" fill="currentColor">
              <path d="M10.75 4.75a.75.75 0 00-1.5 0v4.5h-4.5a.75.75 0 000 1.5h4.5v4.5a.75.75 0 001.5 0v-4.5h4.5a.75.75 0 000-1.5h-4.5v-4.5z" />
            </svg>
            <span class="hidden md:inline">New Monitor</span>
          </.link>
        </div>
      </div>

      <div
        :if={Enum.empty?(@monitors)}
        class="rounded-lg border border-dashed border-slate-400/60 bg-white dark:bg-slate-800 p-8 text-center"
      >
        <p class="text-base font-medium text-slate-900 dark:text-white">No monitors yet</p>
        <p class="mt-2 text-sm text-slate-600 dark:text-slate-300">
          Create a monitor to deliver recurring reports or alert on critical metrics changes.
        </p>
        <.link
          patch={~p"/monitors/new"}
          class="mt-4 inline-flex items-center rounded-md border border-transparent bg-teal-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-teal-500"
        >
          Create Monitor
        </.link>
      </div>

      <div :if={Enum.any?(@monitors)} class="space-y-3">
        <.link
          :for={monitor <- @monitors}
          class="group block rounded-lg border border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-800 transition-colors hover:bg-gray-50 dark:hover:bg-slate-700/40"
          navigate={~p"/monitors/#{monitor.id}"}
        >
          <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between px-3 py-3 sm:px-4">
            <div class="flex min-w-0 items-center gap-3">
              {monitor_icon(%{monitor: monitor})}
              <div class="min-w-0">
                <div class="truncate text-sm font-medium text-gray-900 dark:text-white group-hover:text-teal-600 dark:group-hover:text-teal-300">
                  {monitor.name}
                </div>
                <div class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                  <%= if monitor.type == :report do %>
                    <%= if monitor.dashboard do %>
                      Attached to dashboard
                      <strong class="font-semibold text-gray-900 dark:text-white">
                        {monitor.dashboard.name}
                      </strong>
                      from {monitor_source_label(monitor, @sources)}
                    <% else %>
                      Attached to dashboard (unavailable) from {monitor_source_label(
                        monitor,
                        @sources
                      )}
                    <% end %>
                  <% else %>
                    Watching metrics key path
                    <code class="rounded bg-slate-200/70 px-1.5 py-0.5 text-[0.65rem] font-medium text-slate-800 dark:bg-slate-700 dark:text-slate-100">
                      {format_metric_path(monitor)}
                    </code>
                    from {monitor_source_label(monitor, @sources)}
                  <% end %>
                </div>
              </div>
            </div>
            <div class="flex items-center gap-3">
              <div :if={monitor.user} class="flex items-center">
                <img
                  src={gravatar_url(monitor.user.email, 48)}
                  alt={"Owner avatar for #{monitor.name}"}
                  class="h-6 w-6 rounded-full border border-gray-200 dark:border-slate-600"
                  title={"Owned by #{monitor_owner_label(monitor.user)}"}
                />
              </div>
              <span
                :if={monitor.locked}
                class="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2.5 py-0.5 text-[0.7rem] font-semibold text-amber-700 ring-1 ring-inset ring-amber-600/20 dark:bg-amber-500/20 dark:text-amber-200 dark:ring-amber-500/30"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="h-3.5 w-3.5"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0V10.5m-.75 11.25h10.5a1.5 1.5 0 0 0 1.5-1.5v-6.75a1.5 1.5 0 0 0-1.5-1.5H6.75a1.5 1.5 0 0 0-1.5 1.5V20.25a1.5 1.5 0 0 0 1.5 1.5Z"
                  />
                </svg>
                Locked
              </span>
              <% schedule_label = monitor_schedule_label(monitor) %>
              <div :if={schedule_label} class="flex items-center">
                <span class="inline-flex h-8 items-center rounded-md bg-gray-100 px-3 text-sm font-medium text-gray-600 dark:bg-slate-700 dark:text-slate-200">
                  {schedule_label}
                </span>
              </div>
              <svg
                class="h-4 w-4 flex-shrink-0 text-gray-400 group-hover:text-teal-500 dark:text-gray-500 dark:group-hover:text-teal-400"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M13.5 4.5L21 12m0 0-7.5 7.5M21 12H3"
                />
              </svg>
            </div>
          </div>
        </.link>
      </div>

      <.live_component
        :if={@live_action == :new}
        module={FormComponent}
        id="monitor-form"
        monitor={@modal_monitor}
        changeset={@modal_changeset}
        dashboards={@dashboards}
        sources={@sources}
        current_user={@current_user}
        current_membership={@current_membership}
        delivery_options={@delivery_options}
        patch={~p"/monitors"}
        title="Create Monitor"
      />
    </div>
    """
  end

  defp monitor_owner_label(%{name: name}) when is_binary(name) and name != "" do
    name
  end

  defp monitor_owner_label(%{email: email}) when is_binary(email), do: email
  defp monitor_owner_label(_), do: "Unknown owner"

  defp gravatar_url(email, size \\ 64)

  defp gravatar_url(email, size) when is_binary(email) do
    trimmed =
      email
      |> String.trim()
      |> String.downcase()

    if trimmed == "" do
      default_gravatar(size)
    else
      hash =
        trimmed
        |> then(fn value -> :crypto.hash(:md5, value) end)
        |> Base.encode16(case: :lower)

      "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=identicon"
    end
  end

  defp gravatar_url(_email, size), do: default_gravatar(size)

  defp default_gravatar(size), do: "https://www.gravatar.com/avatar/?s=#{size}&d=identicon"
end
