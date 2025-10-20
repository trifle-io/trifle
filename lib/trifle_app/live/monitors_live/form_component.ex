defmodule TrifleApp.MonitorsLive.FormComponent do
  use TrifleApp, :live_component

  alias Ecto.Changeset
  alias Trifle.Monitors
  alias Trifle.Monitors.Monitor
  alias Trifle.Monitors.Monitor.{AlertSettings, DeliveryChannel, ReportSettings}
  require Logger

  @impl true
  def update(assigns, socket) do
    Logger.debug("[MonitorForm] update action=#{assigns[:action]} handles=#{inspect(assigns[:monitor] && assigns.monitor.delivery_channels)}")
    monitor = ensure_monitor_struct(assigns.monitor, assigns.current_membership)

    {:ok,
     socket
     |> assign_new(:dashboards, fn -> assigns.dashboards || [] end)
     |> assign_new(:available_dashboards, fn -> assigns.dashboards || [] end)
     |> assign_new(:delivery_options, fn -> assigns.delivery_options || [] end)
     |> assign_new(:delivery_handles, fn -> [] end)
     |> assign(assigns)
     |> assign(:monitor, monitor)
     |> assign(:action, assigns[:action] || derive_action(monitor))
     |> assign(:delivery_handle_error, nil)
     |> assign_form(assigns.changeset || Monitors.change_monitor(monitor, %{}))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.app_modal id="monitor-modal" show on_cancel={JS.patch(@patch)} size="xl">
        <:title>{@title}</:title>
        <:body>
          <.simple_form
            for={@form}
            id="monitor-form"
            phx-target={@myself}
            phx-change="validate"
            phx-submit="save"
          >
          <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
            <div class="col-span-1 md:col-span-2">
              <.input field={@form[:name]} label="Monitor name" required />
            </div>
            <div>
              <.input
                field={@form[:type]}
                type="select"
                label="Monitor type"
                options={[{"Report monitor", "report"}, {"Alert monitor", "alert"}]}
              />
            </div>
            <div>
              <.input
                field={@form[:status]}
                type="select"
                label="Status"
                options={[{"Active", "active"}, {"Paused", "paused"}]}
              />
            </div>
            <div class="col-span-1 md:col-span-2">
              <.input
                field={@form[:description]}
                type="textarea"
                label="Description"
                placeholder="Let teammates know what this monitor does."
              />
            </div>
          </div>

          <% type = @monitor.type || :report %>

          <div class="mt-6 space-y-4 rounded-lg border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-800/70 p-4">
            <h3 class="text-sm font-semibold text-slate-900 dark:text-white">
              <%= if type == :report, do: "Report configuration", else: "Alert configuration" %>
            </h3>

            <%= if type == :report do %>
              <.inputs_for :let={report_form} field={@form[:report_settings]}>
                <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
                  <div class="md:col-span-2">
                    <label class="block text-sm font-medium text-slate-700 dark:text-slate-200 mb-1">
                      Attach to dashboard
                    </label>
                    <select
                      name={@form[:dashboard_id].name}
                      id={@form[:dashboard_id].id}
                      class="block w-full rounded-md border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-900 px-3 py-2 text-sm text-slate-900 dark:text-white focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500"
                    >
                      <option value="">Select dashboard...</option>
                      <%= for dashboard <- @available_dashboards do %>
                        <option value={dashboard.id} selected={dashboard.id == @form[:dashboard_id].value}>
                          {dashboard.name}
                        </option>
                      <% end %>
                    </select>
                    <%= for error <- @form[:dashboard_id].errors do %>
                      <p class="mt-1 text-xs text-rose-600 dark:text-rose-400">{translate_error(error)}</p>
                    <% end %>
                    <%= if @available_dashboards == [] do %>
                      <p class="mt-2 text-xs text-slate-500 dark:text-slate-400">
                        No dashboards found. Create a dashboard first to connect report monitors.
                      </p>
                    <% end %>
                  </div>
                  <div>
                    <.input
                      field={report_form[:frequency]}
                      type="select"
                      label="Delivery cadence"
                      options={[
                        {"Daily", "daily"},
                        {"Weekly", "weekly"},
                        {"Monthly", "monthly"},
                        {"Custom (CRON)", "custom"}
                      ]}
                    />
                  </div>
                  <div>
                    <.input
                      field={report_form[:timeframe]}
                      label="Timeframe window"
                      placeholder="e.g. 7d, 30d"
                    />
                  </div>
                  <div>
                    <.input
                      field={report_form[:granularity]}
                      label="Granularity"
                      placeholder="e.g. 1h, 1d"
                    />
                  </div>
                  <% frequency_value = report_form[:frequency].value %>
                  <div :if={frequency_value in [:custom, "custom"]}>
                    <.input
                      field={report_form[:custom_cron]}
                      label="CRON expression"
                      placeholder="0 7 * * MON"
                    />
                  </div>
                </div>
              </.inputs_for>
            <% else %>
              <.inputs_for :let={alert_form} field={@form[:alert_settings]}>
                <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
                  <div>
                    <.input
                      field={alert_form[:metric_key]}
                      label="Metric key"
                      placeholder="e.g. app.signups.total"
                      required
                    />
                  </div>
                  <div>
                    <.input
                      field={alert_form[:metric_path]}
                      label="Metric path"
                      placeholder="e.g. $.country.US"
                      required
                    />
                  </div>
                  <div>
                    <.input
                      field={alert_form[:timeframe]}
                      label="Evaluation timeframe"
                      placeholder="e.g. 1h"
                    />
                  </div>
                  <div>
                    <.input
                      field={alert_form[:granularity]}
                      label="Evaluation granularity"
                      placeholder="e.g. 5m"
                    />
                  </div>
                  <div>
                    <.input
                      field={alert_form[:analysis_strategy]}
                      type="select"
                      label="Analysis strategy"
                      options={[
                        {"Threshold", "threshold"},
                        {"Range", "range"},
                        {"Anomaly detection", "anomaly_detection"}
                      ]}
                    />
                  </div>
                </div>
              </.inputs_for>
            <% end %>
          </div>

          <div class="mt-6">
            <.delivery_selector
              id="monitor-delivery-selector"
              name="monitor[delivery_handles]"
              label="Delivery targets"
              placeholder="Select teammates or channels..."
              options={@delivery_options}
              values={@delivery_handles || []}
              error={@delivery_handle_error}
              help="Choose where to deliver monitor notifications. Start typing to narrow down recipients."
            />
          </div>

            <:actions>
              <.button type="button" variant="ghost" phx-click={JS.patch(@patch)}>
                Cancel
              </.button>
              <.button type="submit">
                <%= if @action == :new, do: "Create monitor", else: "Save changes" %>
              </.button>
            </:actions>
          </.simple_form>
        </:body>
      </.app_modal>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"monitor" => monitor_params}, socket) do
    Logger.debug("[MonitorForm] validate event - delivery_handles: #{inspect(monitor_params["delivery_handles"])}")
    {prepared_params, handles, invalid} = normalize_delivery_params(monitor_params, socket)

    changeset =
      socket.assigns.monitor
      |> Monitors.change_monitor(prepared_params)
      |> Map.put(:action, :validate)
      |> add_delivery_handle_errors(invalid)

    {:noreply,
     socket
     |> assign(:delivery_handle_error, delivery_error_message(invalid))
     |> assign_form(changeset, handles: handles)}
  end

  def handle_event("save", %{"monitor" => monitor_params}, socket) do
    Logger.debug("[MonitorForm] save event")
    {prepared_params, handles, invalid} = normalize_delivery_params(monitor_params, socket)

    if invalid != [] do
      changeset =
        socket.assigns.monitor
        |> Monitors.change_monitor(prepared_params)
        |> add_delivery_handle_errors(invalid)
        |> Map.put(:action, :validate)

      {:noreply,
       socket
       |> assign(:delivery_handle_error, delivery_error_message(invalid))
       |> assign_form(changeset, handles: handles)}
    else
      save_monitor(socket, socket.assigns.action, prepared_params, handles)
    end
  end

  defp save_monitor(socket, :new, monitor_params, handles) do
    case Monitors.create_monitor_for_membership(
           socket.assigns.current_user,
           socket.assigns.current_membership,
           monitor_params
         ) do
      {:ok, monitor} ->
        notify_parent({:saved, monitor})

        {:noreply,
         socket
         |> assign(:monitor, monitor)
         |> assign(:delivery_handle_error, nil)
         |> assign_form(Monitors.change_monitor(monitor, %{}), handles: handles)}

      {:error, %Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:delivery_handle_error, delivery_error_from_changeset(changeset))
         |> assign_form(Map.put(changeset, :action, :validate), handles: handles)}
    end
  end

  defp save_monitor(socket, :edit, monitor_params, handles) do
    case Monitors.update_monitor_for_membership(
           socket.assigns.monitor,
           socket.assigns.current_membership,
           monitor_params
         ) do
      {:ok, monitor} ->
        notify_parent({:saved, monitor})

        {:noreply,
         socket
         |> assign(:monitor, monitor)
         |> assign(:delivery_handle_error, nil)
         |> assign_form(Monitors.change_monitor(monitor, %{}), handles: handles)}

      {:error, :unauthorized} ->
        notify_parent({:error, "You do not have permission to update this monitor"})
        {:noreply, socket}

      {:error, %Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:delivery_handle_error, delivery_error_from_changeset(changeset))
         |> assign_form(Map.put(changeset, :action, :validate), handles: handles)}
    end
  end

  defp assign_form(socket, %Changeset{} = changeset, opts \\ []) do
    monitor = Changeset.apply_changes(changeset)

    handles =
      Keyword.get(opts, :handles) ||
        Monitors.delivery_handles_from_channels(monitor.delivery_channels || [])

    socket
    |> assign(:form, to_form(changeset))
    |> assign(:monitor, monitor)
    |> assign(:delivery_handles, handles)
  end

  defp ensure_monitor_struct(%Monitor{} = monitor, _membership), do: populate_missing_embeds(monitor)

  defp ensure_monitor_struct(nil, membership) do
    %Monitor{organization_id: membership.organization_id, status: :active, type: :report}
    |> populate_missing_embeds()
  end

  defp populate_missing_embeds(monitor) do
    monitor
    |> Map.update(:report_settings, struct(ReportSettings, %{}), fn
      %ReportSettings{} = settings -> settings
      value when is_map(value) -> struct(ReportSettings, value)
    end)
    |> Map.update(:alert_settings, struct(AlertSettings, %{}), fn
      %AlertSettings{} = settings -> settings
      value when is_map(value) -> struct(AlertSettings, value)
    end)
    |> Map.update(:delivery_channels, [], fn
      [] ->
        []

      channels ->
        Enum.map(channels, fn
          %DeliveryChannel{} = channel -> channel
          value when is_map(value) -> struct(DeliveryChannel, value)
        end)
    end)
  end

  defp derive_action(%Monitor{id: nil}), do: :new
  defp derive_action(_monitor), do: :edit

  defp notify_parent(message), do: send(self(), {__MODULE__, message})

  defp normalize_delivery_params(params, socket) do
    membership = socket.assigns.current_membership
    handles = params |> Map.get("delivery_handles", "") |> parse_handles()
    {channels, invalid} = Monitors.delivery_channels_from_handles(handles, membership)

    prepared_params =
      params
      |> Map.delete("delivery_handles")
      |> Map.put("delivery_channels", channels)

    {prepared_params, handles, invalid}
  end

  defp parse_handles(nil), do: []
  defp parse_handles(""), do: []

  defp parse_handles(value) when is_binary(value) do
    value
    |> String.split(~r/[\s,]+/, trim: true)
    |> Enum.uniq()
  end

  defp parse_handles(list) when is_list(list) do
    list
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
  end

  defp add_delivery_handle_errors(%Changeset{} = changeset, []), do: changeset

  defp add_delivery_handle_errors(%Changeset{} = changeset, invalid_handles) do
    Enum.reduce(invalid_handles, changeset, fn handle, acc ->
      Changeset.add_error(acc, :delivery_channels, "unknown delivery target: #{handle}")
    end)
  end

  defp delivery_error_message([]), do: nil

  defp delivery_error_message(invalid) do
    "Unknown delivery targets: " <> Enum.join(invalid, ", ")
  end

  defp delivery_error_from_changeset(%Changeset{} = changeset) do
    changeset.errors
    |> Enum.find_value(fn
      {:delivery_channels, {message, _}} -> message
      _ -> nil
    end)
  end
end
