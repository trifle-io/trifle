defmodule TrifleApp.MonitorsLive do
  use TrifleApp, :live_view

  alias Ecto.Changeset
  alias Trifle.Monitors
  alias Trifle.Monitors.Monitor
  alias Trifle.Organizations
  alias TrifleApp.MonitorsLive.FormComponent
  require Logger

  @impl true
  def mount(_params, _session, %{assigns: %{current_membership: nil}} = socket) do
    {:ok, redirect(socket, to: ~p"/organization/profile")}
  end

  def mount(_params, _session, %{assigns: %{current_user: user, current_membership: membership}} = socket) do
    Logger.debug("[MonitorsLive] mount for membership=#{membership.id}")
    {:ok,
     socket
     |> assign(:page_title, "Monitors")
     |> assign(:breadcrumb_links, ["Monitors"])
     |> assign(:nav_section, :monitors)
     |> assign(:current_membership, membership)
     |> assign(:current_user, user)
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

    monitor =
      %Monitor{organization_id: membership.organization_id, status: :active, type: :report}
      |> Monitor.changeset(%{
        status: :active,
        type: :report,
        report_settings: Monitors.default_report_settings(),
        alert_settings: Monitors.default_alert_settings()
      })
      |> Changeset.apply_changes()

    changeset = Monitors.change_monitor(monitor, %{})

    socket
    |> assign(:modal_monitor, monitor)
    |> assign(:modal_changeset, changeset)
    |> assign(:page_title, "Create Monitor")
  end

  @impl true
  def handle_event("delete_monitor", %{"id" => id}, socket) do
    membership = socket.assigns.current_membership
    user = socket.assigns.current_user

    monitor =
      socket.assigns.monitors
      |> Enum.find(&(&1.id == id))
      |> case do
        nil -> Monitors.get_monitor_for_membership!(membership, id)
        monitor -> monitor
      end

    case Monitors.delete_monitor_for_membership(monitor, membership) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Monitor deleted")
         |> assign(:monitors, load_monitors(user, membership))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You do not have permission to delete this monitor")}

      {:error, %Changeset{} = changeset} ->
        {:noreply,
         put_flash(socket, :error, "Unable to delete monitor: #{changeset_error_message(changeset)}")}
    end
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
    Organizations.list_dashboards_for_membership(user, membership)
  end

  defp fetch_delivery_options(socket) do
    membership = socket.assigns.current_membership
    Logger.debug("[MonitorsLive] fetching delivery options for membership=#{membership.id}")
    opts = Monitors.delivery_options_for_membership(membership)
    Logger.debug("[MonitorsLive] fetched #{length(opts)} delivery options")
    assign(socket, :delivery_options, opts)
  end

  defp changeset_error_message(%Changeset{} = changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} ->
      "#{Phoenix.Naming.humanize(field)} #{message}"
    end)
    |> Enum.join(", ")
  end

  defp type_label(:report), do: "Report"
  defp type_label(:alert), do: "Alert"
  defp type_label(other) when is_atom(other), do: other |> Atom.to_string() |> Phoenix.Naming.humanize()
  defp type_label(other) when is_binary(other), do: other

  defp delivery_channel_badge(channel) do
    channel
    |> channel_as_atom()
    |> case do
      :email -> "EMAIL"
      :slack_webhook -> "SLACK"
      :webhook -> "WEBHOOK"
      :custom -> "CUSTOM"
      _ -> "CHANNEL"
    end
  end

  defp delivery_channel_handle(channel) do
    channel
    |> List.wrap()
    |> Monitors.delivery_handles_from_channels()
    |> List.first()
  end

  defp channel_as_atom(%{} = channel) do
    value = Map.get(channel, :channel) || Map.get(channel, "channel")

    cond do
      is_atom(value) ->
        value

      is_binary(value) ->
        value
        |> String.trim()
        |> String.downcase()
        |> String.replace("-", "_")
        |> String.to_existing_atom()

      true ->
        nil
    end
  rescue
    ArgumentError -> nil
  end

  defp monitor_icon(assigns) do
    ~H"""
    <span class="inline-flex h-10 w-10 items-center justify-center rounded-full bg-teal-900/70 text-white">
      <%= if @monitor.type == :report do %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="h-6 w-6"
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
          class="h-6 w-6"
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
          <h1 class="text-2xl font-semibold text-slate-900 dark:text-white">Monitors</h1>
          <p class="mt-1 text-sm text-slate-600 dark:text-slate-300">
            Define scheduled reports and flexible alerts that watch your metrics.
          </p>
        </div>
        <div class="flex gap-2">
          <.link
            patch={~p"/monitors/new"}
            class="inline-flex items-center gap-2 rounded-md bg-teal-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-teal-500 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-teal-500"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
              <path
                fill-rule="evenodd"
                d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z"
                clip-rule="evenodd"
              />
            </svg>
            New Monitor
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

      <div :if={Enum.any?(@monitors)} class="grid gap-4 lg:grid-cols-2">
        <div
          :for={monitor <- @monitors}
          class="flex flex-col rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-5 shadow-sm transition hover:border-teal-400 hover:shadow-md"
        >
          <div class="flex items-start gap-4">
            {monitor_icon(%{monitor: monitor})}
            <div class="flex-1 space-y-1.5">
              <div class="flex items-center justify-between gap-2">
                <.link
                  navigate={~p"/monitors/#{monitor.id}"}
                  class="text-lg font-semibold text-slate-900 dark:text-white hover:text-teal-500"
                >
                  {monitor.name}
                </.link>
                <span
                  class={[
                    "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium uppercase tracking-wide",
                    monitor.status == :active &&
                      "bg-teal-100 text-teal-800 dark:bg-teal-500/10 dark:text-teal-200",
                    monitor.status == :paused &&
                      "bg-slate-200 text-slate-700 dark:bg-slate-700 dark:text-slate-200"
                  ]}
                >
                  {type_label(monitor.type)}
                </span>
              </div>
              <p class="text-sm text-slate-600 dark:text-slate-300">
                <%= if monitor.type == :report do %>
                  <%= if monitor.dashboard do %>
                    Attached to dashboard <strong class="font-semibold text-slate-900 dark:text-white">
                      {monitor.dashboard.name}
                    </strong>
                  <% else %>
                    Dashboard not available
                  <% end %>
                <% else %>
                  Watching metric key
                  <code class="rounded bg-slate-200/70 px-1.5 py-0.5 text-xs font-medium text-slate-800 dark:bg-slate-700 dark:text-slate-100">
                    {monitor.alert_settings && monitor.alert_settings.metric_key || "—"}
                  </code>
                  at path
                  <code class="rounded bg-slate-200/70 px-1.5 py-0.5 text-xs font-medium text-slate-800 dark:bg-slate-700 dark:text-slate-100">
                    {monitor.alert_settings && monitor.alert_settings.metric_path || "—"}
                  </code>
                <% end %>
              </p>
              <p :if={monitor.description} class="text-sm text-slate-500 dark:text-slate-400">
                {monitor.description}
              </p>
              <div class="flex flex-wrap gap-2 pt-1">
                <span class="inline-flex items-center gap-1 rounded-md bg-slate-100 dark:bg-slate-800/70 px-2 py-1 text-xs font-medium text-slate-600 dark:text-slate-300">
                  <%= if monitor.type == :report do %>
                    {monitor.report_settings && String.upcase(to_string(monitor.report_settings.frequency || "weekly"))} schedule
                  <% else %>
                    {monitor.alert_settings && String.upcase(to_string(monitor.alert_settings.analysis_strategy || "threshold"))} analysis
                  <% end %>
                </span>
                <span
                  :for={channel <- monitor.delivery_channels || []}
                  class="inline-flex items-center gap-1 rounded-md bg-teal-50 text-teal-700 dark:bg-teal-500/10 dark:text-teal-200 px-2 py-1 text-xs font-medium"
                >
                  {delivery_channel_badge(channel)}
                  <%= if handle = delivery_channel_handle(channel) do %>
                    <span class="text-[0.65rem] text-slate-500 dark:text-slate-300">
                      {handle}
                    </span>
                  <% end %>
                </span>
              </div>
            </div>
          </div>
          <div class="mt-4 flex items-center justify-between text-sm">
            <.link navigate={~p"/monitors/#{monitor.id}"} class="text-teal-600 hover:text-teal-500 font-medium">
              View details
            </.link>
            <button
              phx-click="delete_monitor"
              phx-value-id={monitor.id}
              data-confirm="Are you sure you want to delete this monitor?"
              class="text-slate-500 hover:text-rose-500 font-medium"
            >
              Delete
            </button>
          </div>
        </div>
      </div>

      <.live_component
        :if={@live_action == :new}
        module={FormComponent}
        id="monitor-form"
        monitor={@modal_monitor}
        changeset={@modal_changeset}
        dashboards={@dashboards}
        current_user={@current_user}
        current_membership={@current_membership}
        delivery_options={@delivery_options}
        patch={~p"/monitors"}
        title="Create Monitor"
      />
    </div>
    """
  end
end
