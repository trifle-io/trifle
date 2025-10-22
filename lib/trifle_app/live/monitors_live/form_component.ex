defmodule TrifleApp.MonitorsLive.FormComponent do
  use TrifleApp, :live_component

  alias Ecto.Changeset
  alias Trifle.Monitors
  alias Trifle.Monitors.Monitor
  alias Trifle.Monitors.Monitor.{AlertSettings, DeliveryChannel, ReportSettings}
  alias Trifle.Stats.Source
  require Logger

  @impl true
  def update(assigns, socket) do
    Logger.debug(
      "[MonitorForm] update action=#{assigns[:action]} handles=#{inspect(assigns[:monitor] && assigns.monitor.delivery_channels)}"
    )

    monitor = ensure_monitor_struct(assigns.monitor, assigns.current_membership)

    {:ok,
     socket
     |> assign_new(:dashboards, fn -> assigns.dashboards || [] end)
     |> assign_new(:available_dashboards, fn -> assigns.dashboards || [] end)
     |> assign_new(:delivery_options, fn -> assigns.delivery_options || [] end)
     |> assign_new(:delivery_handles, fn -> [] end)
     |> assign_new(:sources, fn -> assigns.sources || [] end)
     |> assign(assigns)
     |> assign(:persisted_monitor, monitor)
     |> assign(:action, assigns[:action] || derive_action(monitor))
     |> assign(:delivery_handle_error, nil)
     |> assign_form(assigns.changeset || Monitors.change_monitor(monitor, %{}))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.app_modal id="monitor-modal" show on_cancel={JS.patch(@patch)} size="md">
        <:title>{@title}</:title>
        <:body>
          <.simple_form
            for={@form}
            id="monitor-form"
            phx-target={@myself}
            phx-change="validate"
            phx-submit="save"
          >
            <div class="space-y-6">
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

            <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
              <div class="md:col-span-2">
                <label class="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-200">
                  Data source
                </label>
                <%= if type == :alert do %>
                  <% grouped_sources = group_sources_for_select(@sources || []) %>
                  <div class="grid grid-cols-1 sm:max-w-xs">
                    <select
                      name="monitor[source_ref]"
                      id="monitor-source-ref"
                      class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
                      disabled={grouped_sources == []}
                    >
                      <option value="">Select a source...</option>
                      <%= for {group_label, sources} <- grouped_sources do %>
                        <optgroup label={group_label}>
                          <%= for source <- sources do %>
                            <% option_value = encode_source_ref(source) %>
                            <option value={option_value} selected={source_selected?(@selected_source_ref, source)}>
                              {Source.display_name(source)}
                            </option>
                          <% end %>
                        </optgroup>
                      <% end %>
                    </select>
                    <svg
                      viewBox="0 0 16 16"
                      fill="currentColor"
                      data-slot="icon"
                      aria-hidden="true"
                      class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4"
                    >
                      <path
                        d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
                        clip-rule="evenodd"
                        fill-rule="evenodd"
                      />
                    </svg>
                  </div>
                  <%= if grouped_sources == [] do %>
                    <p class="mt-2 text-xs text-red-600 dark:text-red-400">
                      No available sources. Create a database or project first.
                    </p>
                  <% end %>
                <% else %>
                  <div class="rounded-md border border-dashed border-slate-300 dark:border-slate-600 bg-slate-50 px-3 py-2 text-sm text-slate-700 dark:bg-slate-800/60 dark:text-slate-200">
                    {monitor_source_display(@monitor, @sources)}
                  </div>
                  <p class="mt-2 text-xs text-slate-500 dark:text-slate-400">
                    Source is derived from the selected dashboard.
                  </p>
                <% end %>
                <%= for error <- source_errors(@form) do %>
                  <p class="mt-1 text-xs text-rose-600 dark:text-rose-400">
                    {translate_error(error)}
                  </p>
                <% end %>
              </div>
            </div>

            <div class="border-t border-gray-200 pt-6 dark:border-slate-700">
              <h3 class="text-sm font-semibold text-slate-900 dark:text-white">
                {if type == :report, do: "Report configuration", else: "Alert configuration"}
              </h3>
                <div class="mt-4">
                  <%= if type == :report do %>
                    <.inputs_for :let={report_form} field={@form[:report_settings]}>
                      <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
                        <div class="md:col-span-2">
                          <label class="mb-1 block text-sm font-medium text-slate-700 dark:text-slate-200">
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
                            <p class="mt-1 text-xs text-rose-600 dark:text-rose-400">
                              {translate_error(error)}
                            </p>
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
              </div>

              <div class="border-t border-gray-200 pt-6 dark:border-slate-700">
                <h3 class="text-sm font-semibold text-slate-900 dark:text-white">Delivery targets</h3>
                <p class="mt-1 text-xs text-slate-500 dark:text-slate-400">
                  Choose the channels or teammates that should receive this monitor.
                </p>
                <div class="mt-4">
                  <.delivery_selector
                    id="monitor-delivery-selector"
                    name="monitor[delivery_handles]"
                    placeholder="Select teammates or channels..."
                    options={@delivery_options}
                    values={@delivery_handles || []}
                    error={@delivery_handle_error}
                    help="Start typing to narrow down recipients."
                  />
                </div>
              </div>
            </div>

            <:actions>
              <div class="flex w-full items-center justify-end gap-3">
                <.link
                  patch={@patch}
                  class="inline-flex items-center whitespace-nowrap rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-slate-700 dark:text-white dark:ring-slate-600 dark:hover:bg-slate-600"
                >
                  Cancel
                </.link>
                <.button type="submit">
                  {if @action == :new, do: "Create monitor", else: "Save changes"}
                </.button>
              </div>
            </:actions>

            <div
              :if={@persisted_monitor && @persisted_monitor.id}
              class="mt-8 border-t border-red-200 pt-6 dark:border-red-800"
            >
              <div class="mb-4">
                <span class="text-sm font-medium text-red-700 dark:text-red-400">Danger zone</span>
                <p class="text-xs text-red-600 dark:text-red-400">
                  Deleting this monitor cannot be undone.
                </p>
              </div>
              <button
                type="button"
                phx-click="delete_monitor"
                phx-target={@myself}
                data-confirm="Are you sure you want to delete this monitor? This action cannot be undone."
                class="w-full inline-flex items-center justify-center rounded-md bg-red-50 px-3 py-2 text-sm font-semibold text-red-700 ring-1 ring-inset ring-red-600/20 hover:bg-red-100 dark:bg-red-900 dark:text-red-200 dark:ring-red-500/30 dark:hover:bg-red-800"
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
                <span class="hidden md:inline">Delete monitor</span>
                <span class="md:hidden">Delete</span>
              </button>
            </div>
          </.simple_form>
        </:body>
      </.app_modal>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"monitor" => monitor_params}, socket) do
    Logger.debug(
      "[MonitorForm] validate event - delivery_handles: #{inspect(monitor_params["delivery_handles"])}"
    )

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

  def handle_event("delete_monitor", _params, socket) do
    if socket.assigns.persisted_monitor && socket.assigns.persisted_monitor.id do
      notify_parent({:delete, socket.assigns.persisted_monitor})
    end

    {:noreply, socket}
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
         |> assign(:persisted_monitor, monitor)
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
           socket.assigns.persisted_monitor,
           socket.assigns.current_membership,
           monitor_params
         ) do
      {:ok, monitor} ->
        notify_parent({:saved, monitor})

        {:noreply,
         socket
         |> assign(:persisted_monitor, monitor)
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

  defp ensure_monitor_struct(%Monitor{} = monitor, _membership),
    do: populate_missing_embeds(monitor)

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
    base_monitor = socket.assigns.persisted_monitor || %Monitor{}

    {channels, invalid} =
      Monitors.delivery_channels_from_handles(
        handles,
        membership,
        base_monitor.delivery_channels || []
      )

    prepared_params =
      params
      |> Map.delete("delivery_handles")
      |> Map.put("delivery_channels", channels)
      |> maybe_apply_source_ref()

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

  defp maybe_apply_source_ref(params) do
    {ref, params} =
      cond do
        Map.has_key?(params, "source_ref") -> Map.pop(params, "source_ref")
        Map.has_key?(params, :source_ref) -> Map.pop(params, :source_ref)
        true -> {nil, params}
      end

    case ref do
      nil ->
        params

      "" ->
        params
        |> Map.delete("source_type")
        |> Map.delete(:source_type)
        |> Map.delete("source_id")
        |> Map.delete(:source_id)

      value ->
        case parse_source_ref(value) do
          {:ok, {type, id}} ->
            params
            |> Map.delete("source_type")
            |> Map.delete(:source_type)
            |> Map.delete("source_id")
            |> Map.delete(:source_id)
            |> Map.put("source_type", Atom.to_string(type))
            |> Map.put("source_id", id)

          {:error, _reason} ->
            params
        end
    end
  end

  defp parse_source_ref(nil), do: {:error, :blank}

  defp parse_source_ref(ref) when is_binary(ref) do
    case String.split(ref, ":", parts: 2) do
      [type, id] when type in ["database", "project"] and id not in [nil, ""] ->
        {:ok, {String.to_existing_atom(type), id}}

      _ ->
        {:error, :invalid}
    end
  rescue
    ArgumentError ->
      {:error, :invalid}
  end

  defp encode_source_ref(%Source{} = source) do
    "#{Source.type(source)}:#{Source.id(source)}"
  end

  defp source_selected?(selected_ref, %Source{} = source) do
    selected_ref == encode_source_ref(source)
  end

  defp monitor_source_ref(%Monitor{source_type: nil}), do: nil

  defp monitor_source_ref(%Monitor{source_type: type, source_id: id})
       when not is_nil(type) and not is_nil(id) do
    "#{type}:#{id}"
  end

  defp monitor_source_ref(_), do: nil

  defp monitor_source_display(%Monitor{} = monitor, sources) do
    ref = monitor_source_ref(monitor)

    with true <- not is_nil(ref),
         %Source{} = source <- Enum.find(sources, &(encode_source_ref(&1) == ref)) do
      source_option_label(source)
    else
      _ ->
        case ref do
          nil -> "Select a dashboard to determine the source"
          value -> value
        end
    end
  end

  defp source_option_label(%Source{} = source) do
    type_label =
      case Source.type(source) do
        :database -> "Database"
        :project -> "Project"
        other -> other |> Atom.to_string() |> String.capitalize()
      end

    "#{type_label} · #{Source.display_name(source)}"
  end

  defp group_sources_for_select(sources) do
    sources
    |> Enum.group_by(&Source.type/1)
    |> Enum.map(fn {type, list} -> {Source.type_label(type), Enum.sort_by(list, &Source.display_name/1)} end)
    |> Enum.sort_by(fn {label, _} -> label end)
  end

  defp source_errors(form) do
    (form[:source_type].errors ++ form[:source_id].errors)
    |> Enum.uniq()
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
    |> assign(:selected_source_ref, monitor_source_ref(monitor))
  end
end
