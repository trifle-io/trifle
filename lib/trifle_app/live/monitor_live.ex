defmodule TrifleApp.MonitorLive do
  use TrifleApp, :live_view

  alias Ecto.Changeset
  alias Trifle.Monitors
  alias Trifle.Monitors.Monitor
  alias Trifle.Organizations
  alias TrifleApp.MonitorComponents
  alias TrifleApp.MonitorsLive.FormComponent

  @impl true
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
     |> assign(:current_user, user)
     |> assign(:current_membership, membership)
     |> assign(:nav_section, :monitors)
     |> assign(:monitor, nil)
     |> assign(:executions, [])
     |> assign(:dashboards, load_dashboards(user, membership))
     |> assign(:delivery_options, Monitors.delivery_options_for_membership(membership))
     |> assign(:modal_monitor, nil)
     |> assign(:modal_changeset, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    monitor = load_monitor(socket, id)

    socket =
      socket
      |> assign(:monitor, monitor)
      |> assign(:page_title, build_page_title(socket.assigns.live_action, monitor))
      |> assign(:breadcrumb_links, [{"Monitors", ~p"/monitors"}, monitor.name])
      |> assign(:executions, Monitors.list_recent_executions(monitor))

    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :show) do
    socket
    |> assign(:modal_monitor, nil)
    |> assign(:modal_changeset, nil)
  end

  defp apply_action(socket, :configure) do
    monitor = socket.assigns.monitor
    changeset = Monitors.change_monitor(monitor, %{})

    socket
    |> assign(:modal_monitor, monitor)
    |> assign(:modal_changeset, changeset)
    |> assign(:page_title, "Configure · #{monitor.name}")
  end

  @impl true
  def handle_event("delete_monitor", _params, socket) do
    delete_monitor(socket, socket.assigns.monitor)
  end

  def handle_event("toggle_status", _params, socket) do
    %{monitor: monitor, current_membership: membership} = socket.assigns
    next_status = if monitor.status == :active, do: :paused, else: :active

    case Monitors.update_monitor_for_membership(monitor, membership, %{status: next_status}) do
      {:ok, updated} ->
        refreshed = load_monitor(socket, updated.id)

        {:noreply,
         socket
         |> put_flash(:info, "Monitor #{status_label(updated.status)}")
         |> assign(:monitor, refreshed)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You do not have permission to update this monitor")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error_message(changeset))}
    end
  end

  @impl true
  def handle_info({FormComponent, {:saved, monitor}}, socket) do
    refreshed = load_monitor(socket, monitor.id)
    membership = socket.assigns.current_membership

    {:noreply,
     socket
     |> put_flash(:info, "Monitor updated")
     |> assign(:monitor, refreshed)
     |> assign(:executions, Monitors.list_recent_executions(refreshed))
     |> assign(:delivery_options, Monitors.delivery_options_for_membership(membership))
     |> push_patch(to: ~p"/monitors/#{monitor.id}")}
  end

  def handle_info({FormComponent, {:delete, monitor}}, socket) do
    delete_monitor(socket, monitor)
  end

  def handle_info({FormComponent, {:error, message}}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load_monitor(socket, id) do
    membership = socket.assigns.current_membership
    Monitors.get_monitor_for_membership!(membership, id, preload: [:dashboard])
  end

  defp build_page_title(:configure, monitor), do: "Configure · #{monitor.name}"
  defp build_page_title(_action, monitor), do: "#{monitor.name} · Monitor"

  defp load_dashboards(user, membership) do
    Organizations.list_dashboards_for_membership(user, membership)
  end

  defp status_label(:active), do: "enabled"
  defp status_label(:paused), do: "paused"
  defp status_label(_), do: "updated"

  defp monitor_icon(assigns) do
    ~H"""
    <span class={[
      "inline-flex h-12 w-12 items-center justify-center rounded-xl text-white shadow-sm ring-1 ring-inset ring-black/10 dark:ring-white/10",
      Monitor.icon_color_class(@monitor)
    ]}>
      <%= if @monitor.type == :report do %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="h-7 w-7"
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
          class="h-7 w-7"
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

  defp changeset_error_message(%Changeset{} = changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _}} -> "#{Phoenix.Naming.humanize(field)} #{message}" end)
    |> Enum.join(", ")
  end

  defp delete_monitor(socket, %Monitor{} = monitor) do
    membership = socket.assigns.current_membership

    case Monitors.delete_monitor_for_membership(monitor, membership) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Monitor deleted")
         |> redirect(to: ~p"/monitors")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You do not have permission to delete this monitor")}

      {:error, %Changeset{} = changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not delete monitor: #{changeset_error_message(changeset)}"
         )}
    end
  end

  defp delete_monitor(socket, _monitor), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div :if={@monitor} class="space-y-8">
      <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div class="flex items-start gap-4">
          {monitor_icon(%{monitor: @monitor})}
          <div>
            <h1 class="text-2xl font-semibold text-slate-900 dark:text-white">{@monitor.name}</h1>
            <p class="mt-1 text-sm text-slate-600 dark:text-slate-300">
              <%= if @monitor.type == :report do %>
                Report monitor attached to
                <%= if @monitor.dashboard do %>
                  <.link
                    navigate={~p"/dashboards/#{@monitor.dashboard.id}"}
                    class="font-semibold text-teal-600 hover:text-teal-500"
                  >
                    {@monitor.dashboard.name}
                  </.link>
                <% else %>
                  <span class="font-medium text-slate-500 dark:text-slate-400">
                    unavailable dashboard
                  </span>
                <% end %>
              <% else %>
                Alert monitor watching
                <code class="rounded bg-slate-200/70 px-1.5 py-0.5 text-xs font-semibold text-slate-900 dark:bg-slate-700 dark:text-slate-200">
                  {(@monitor.alert_settings && @monitor.alert_settings.metric_key) || "—"}
                </code>
                at
                <code class="rounded bg-slate-200/70 px-1.5 py-0.5 text-xs font-semibold text-slate-900 dark:bg-slate-700 dark:text-slate-200">
                  {(@monitor.alert_settings && @monitor.alert_settings.metric_path) || "—"}
                </code>
              <% end %>
            </p>
            <p :if={@monitor.description} class="mt-2 text-sm text-slate-500 dark:text-slate-300">
              {@monitor.description}
            </p>
          </div>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <.link
            patch={~p"/monitors/#{@monitor.id}/configure"}
            class="inline-flex items-center whitespace-nowrap rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-slate-700 dark:text-white dark:ring-slate-600 dark:hover:bg-slate-600"
          >
            <svg
              class="md:-ml-0.5 md:mr-1.5 h-4 w-4"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z"
              />
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
              />
            </svg>
            <span class="hidden md:inline">Configure</span>
          </.link>
          <button
            type="button"
            class="inline-flex items-center gap-2 rounded-md border border-slate-300 dark:border-slate-600 px-3 py-1.5 text-xs font-medium text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700/70"
            phx-click="toggle_status"
          >
            {if @monitor.status == :active, do: "Pause", else: "Resume"}
          </button>
        </div>
      </div>

      <div class="grid gap-6 lg:grid-cols-3">
        <div class="lg:col-span-2">
          <div class="flex h-full min-h-[16rem] items-center justify-center rounded-xl border border-dashed border-slate-300 bg-slate-50 text-center dark:border-slate-700 dark:bg-slate-800/40">
            <div>
              <h3 class="text-sm font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
                Monitor insights
              </h3>
              <p class="mt-2 text-xs text-slate-500 dark:text-slate-400">
                Additional visualizations and summaries will appear here soon.
              </p>
            </div>
          </div>
        </div>
        <div class="space-y-6">
          <%= if @monitor.type == :report do %>
            <MonitorComponents.report_panel monitor={@monitor} dashboard={@monitor.dashboard} />
          <% else %>
            <MonitorComponents.alert_panel monitor={@monitor} />
          <% end %>
          <MonitorComponents.trigger_history monitor={@monitor} executions={@executions} />
        </div>
      </div>

      <.live_component
        :if={@live_action == :configure}
        module={FormComponent}
        id="monitor-settings-form"
        monitor={@modal_monitor || @monitor}
        changeset={@modal_changeset}
        dashboards={@dashboards}
        current_user={@current_user}
        current_membership={@current_membership}
        delivery_options={@delivery_options}
        action={:edit}
        patch={~p"/monitors/#{@monitor.id}"}
        title="Configure monitor"
      />
    </div>
    """
  end
end
