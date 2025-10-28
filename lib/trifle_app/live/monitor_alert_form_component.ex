defmodule TrifleApp.MonitorAlertFormComponent do
  @moduledoc false
  use TrifleApp, :live_component

  alias Ecto.Changeset
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
     |> assign(:action, assigns[:action] || :new)
     |> put_changeset(changeset)}
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
                  {"Hampel (Robust Outlier)", "hampel"},
                  {"CUSUM (Level Shift)", "cusum"}
                ]}
                required
              />

              <.inputs_for :let={settings_form} field={f[:settings]}>
                <%= case @strategy do %>
                  <% :threshold -> %>
                    <div class="space-y-3">
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Threshold alerts fire when the metric crosses a single fixed boundary. Choose whether you want to be warned about surges or drops in the tracked value.
                      </p>
                      <.input
                        field={settings_form[:threshold_direction]}
                        type="select"
                        label="Trigger when value is"
                        options={[
                          {"Above threshold", "above"},
                          {"Below threshold", "below"}
                        ]}
                      />
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Direction decides if the alert triggers on upward movement (above) or downward movement (below).
                      </p>
                      <.input
                        field={settings_form[:threshold_value]}
                        type="number"
                        step="any"
                        label="Threshold value"
                        placeholder="e.g. 120"
                        required
                      />
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Threshold value is the numeric boundary; the alert fires as soon as any point crosses it in the chosen direction.
                      </p>
                    </div>
                  <% :range -> %>
                    <div class="space-y-3">
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Range alerts track when the metric escapes a safe band between two limits. We notify you the moment values drift below the minimum or above the maximum.
                      </p>
                      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                        <.input
                          field={settings_form[:range_min_value]}
                          type="number"
                          step="any"
                          label="Minimum"
                          placeholder="e.g. 25"
                          required
                        />
                        <p class="text-xs text-slate-500 dark:text-slate-400 sm:col-span-2">
                          Minimum is the lower boundary; anything lower triggers an alert.
                        </p>
                        <.input
                          field={settings_form[:range_max_value]}
                          type="number"
                          step="any"
                          label="Maximum"
                          placeholder="e.g. 45"
                          required
                        />
                        <p class="text-xs text-slate-500 dark:text-slate-400 sm:col-span-2">
                          Maximum is the upper boundary; readings above it also trigger alerts.
                        </p>
                      </div>
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Keep the range tight for sensitive monitoring or widen it for tolerant alerting.
                      </p>
                    </div>
                  <% :hampel -> %>
                    <div class="space-y-3">
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Hampel alerts detect robust outliers by comparing each point to the rolling median and scaled median absolute deviation (MAD). It’s ideal for spotting spikes while ignoring gradual trends.
                      </p>
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Tune the window, K multiplier, and MAD floor to control sensitivity in noisy data.
                      </p>
                      <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
                        <.input
                          field={settings_form[:hampel_window_size]}
                          type="number"
                          step="1"
                          min="1"
                          label="Window size"
                          placeholder="e.g. 7"
                          required
                        />
                        <p class="text-xs text-slate-500 dark:text-slate-400 sm:col-span-3">
                          Window size is the number of recent points used to compute the rolling median; larger windows smooth more volatility.
                        </p>
                        <.input
                          field={settings_form[:hampel_k]}
                          type="number"
                          step="0.1"
                          label="K threshold"
                          placeholder="e.g. 3.0"
                          required
                        />
                        <p class="text-xs text-slate-500 dark:text-slate-400 sm:col-span-3">
                          K threshold scales the MAD; higher values make the detector less sensitive to moderate deviations.
                        </p>
                        <.input
                          field={settings_form[:hampel_mad_floor]}
                          type="number"
                          step="0.1"
                          min="0"
                          label="MAD floor"
                          placeholder="e.g. 0.1"
                          required
                        />
                      </div>
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        MAD floor prevents the detector from collapsing when variance is near zero by enforcing a minimum spread.
                      </p>
                    </div>
                  <% :cusum -> %>
                    <div class="space-y-3">
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        CUSUM alerts accumulate small deviations over time and trigger when the shift indicates a sustained level change. It excels at catching subtle drifts that wouldn’t cross a single threshold.
                      </p>
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Balance the drift allowance and alarm threshold to set how quickly CUSUM reacts.
                      </p>
                      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                        <.input
                          field={settings_form[:cusum_k]}
                          type="number"
                          step="0.1"
                          min="0"
                          label="K (drift allowance)"
                          placeholder="e.g. 0.5"
                          required
                        />
                        <p class="text-xs text-slate-500 dark:text-slate-400 sm:col-span-2">
                          K (drift allowance) defines the size of deviation ignored in each step; larger values tolerate gradual changes longer.
                        </p>
                        <.input
                          field={settings_form[:cusum_h]}
                          type="number"
                          step="0.1"
                          min="0.1"
                          label="H threshold"
                          placeholder="e.g. 5.0"
                          required
                        />
                      </div>
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        H threshold is the cumulative score that must be exceeded before an alert fires; lower values trigger sooner.
                      </p>
                    </div>
                  <% _ -> %>
                    <div class="text-xs text-slate-500 dark:text-slate-400">
                      Select an analysis strategy to configure its parameters.
                    </div>
                <% end %>
              </.inputs_for>

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

          <div :if={@action == :edit} class="mt-6 border-t border-red-200 pt-4 dark:border-red-800">
            <div class="mb-3">
              <span class="text-sm font-semibold text-red-700 dark:text-red-200">Danger zone</span>
              <p class="mt-1 text-xs text-red-600 dark:text-red-300">
                Deleting this alert cannot be undone.
              </p>
            </div>
            <button
              type="button"
              class="mt-3 w-full inline-flex items-center justify-center rounded-md bg-red-50 px-3 py-2 text-sm font-semibold text-red-700 ring-1 ring-inset ring-red-600/20 hover:bg-red-100 dark:bg-red-900 dark:text-red-200 dark:ring-red-500/30 dark:hover:bg-red-800"
              phx-click="delete"
              phx-target={@myself}
              data-confirm="Are you sure you want to delete this alert?"
            >
              <svg
                class="-ml-0.5 mr-1.5 h-4 w-4"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"
                />
              </svg>
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

    {:noreply, put_changeset(socket, changeset)}
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
        {:noreply, put_changeset(socket, changeset)}
    end
  end

  defp update_alert(socket, params) do
    case Monitors.update_alert(socket.assigns.alert, params) do
      {:ok, alert} ->
        notify_parent({:saved, alert, :edit})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_changeset(socket, changeset)}
    end
  end

  defp notify_parent(message), do: send(self(), {__MODULE__, message})

  defp put_changeset(socket, %Changeset{} = changeset) do
    strategy =
      Changeset.get_field(changeset, :analysis_strategy) ||
        socket.assigns.alert.analysis_strategy || :threshold

    socket
    |> assign(:changeset, changeset)
    |> assign(:strategy, strategy)
  end
end
