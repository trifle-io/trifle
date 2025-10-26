defmodule TrifleApp.MonitorAlertFormComponent do
  @moduledoc false
  use TrifleApp, :live_component

  alias Phoenix.LiveView.JS
  alias Trifle.Monitors
  alias Trifle.Monitors.Alert

  @impl true
  def update(assigns, socket) do
    alert = assigns.alert || %Alert{monitor_id: assigns.monitor.id}
    changeset = assigns[:changeset] || Monitors.change_alert(alert, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:alert, alert)
     |> assign(:changeset, changeset)
     |> assign(:action, assigns[:action] || :new)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.app_modal id="monitor-alert-modal" show size="sm" on_cancel={JS.push("close_alert_modal")}>
        <:title>
          {if @action == :new, do: "Add alert", else: "Edit alert"}
        </:title>
        <:body>
          <.form
            :let={f}
            for={@changeset}
            as={:alert}
            id="monitor-alert-form"
            phx-target={@myself}
            phx-change="validate"
            phx-submit="save"
          >
            <div class="space-y-3">
              <.input
                field={f[:analysis_strategy]}
                type="select"
                label="Analysis strategy"
                options={[
                  {"Threshold", "threshold"},
                  {"Range", "range"},
                  {"Anomaly detection", "anomaly_detection"}
                ]}
                required
              />
              <div class="flex items-center justify-end gap-2">
                <button
                  type="button"
                  class="inline-flex items-center rounded-md border border-slate-300 dark:border-slate-600 px-3 py-1.5 text-xs font-medium text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700/70"
                  phx-click="close_alert_modal"
                >
                  Cancel
                </button>
                <.button type="submit">
                  {if @action == :new, do: "Create alert", else: "Save alert"}
                </.button>
              </div>
            </div>
          </.form>

          <div
            :if={@action == :edit}
            class="mt-6 rounded-lg border border-red-200 bg-red-50 p-4 dark:border-red-800 dark:bg-red-900/20"
          >
            <h4 class="text-sm font-semibold text-red-700 dark:text-red-200">Danger zone</h4>
            <p class="mt-1 text-xs text-red-600 dark:text-red-300">
              Deleting this alert cannot be undone.
            </p>
            <button
              type="button"
              class="mt-3 inline-flex items-center rounded-md bg-red-600 px-3 py-2 text-xs font-semibold text-white shadow-sm hover:bg-red-500"
              phx-click="delete"
              phx-target={@myself}
              data-confirm="Are you sure you want to delete this alert?"
            >
              Delete alert
            </button>
          </div>
        </:body>
      </.app_modal>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"alert" => params}, socket) do
    changeset =
      socket.assigns.alert
      |> Monitors.change_alert(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"alert" => params}, socket) do
    case socket.assigns.action do
      :new -> create_alert(socket, params)
      :edit -> update_alert(socket, params)
    end
  end

  def handle_event("delete", _params, socket) do
    case Monitors.delete_alert(socket.assigns.alert) do
      {:ok, alert} ->
        notify_parent({:deleted, alert})
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete alert: #{inspect(reason)}")}
    end
  end

  defp create_alert(socket, params) do
    case Monitors.create_alert(socket.assigns.monitor, params) do
      {:ok, alert} ->
        notify_parent({:saved, alert, :new})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp update_alert(socket, params) do
    case Monitors.update_alert(socket.assigns.alert, params) do
      {:ok, alert} ->
        notify_parent({:saved, alert, :edit})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp notify_parent(message), do: send(self(), {__MODULE__, message})
end
