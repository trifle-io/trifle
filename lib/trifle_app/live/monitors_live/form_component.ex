defmodule TrifleApp.MonitorsLive.FormComponent do
  use TrifleApp, :live_component

  alias Ecto.Changeset
  alias Trifle.Monitors
  alias Trifle.Monitors.Monitor
  alias Trifle.Monitors.Monitor.{DeliveryChannel, DeliveryMedium, ReportSettings}
  alias Trifle.Stats.Source
  alias Trifle.Organizations.DashboardSegments
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
     |> assign_new(:delivery_media_options, fn -> Monitors.delivery_media_options() end)
     |> assign_new(:delivery_handles, fn -> [] end)
     |> assign_new(:sources, fn -> assigns.sources || [] end)
     |> assign(assigns)
     |> assign(:persisted_monitor, monitor)
     |> assign(:action, assigns[:action] || derive_action(monitor))
     |> assign(:delivery_handle_error, nil)
     |> assign(:delivery_media_error, nil)
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
                              <option
                                value={option_value}
                                selected={source_selected?(@selected_source_ref, source)}
                              >
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
                              <option
                                value={dashboard.id}
                                selected={dashboard.id == @form[:dashboard_id].value}
                              >
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
                          <%= if (@dashboard_segment_definitions || []) != [] do %>
                            <div class="mt-4 space-y-3">
                              <div class="text-xs font-medium uppercase tracking-wide text-slate-500 dark:text-slate-400">
                                Segment values
                              </div>
                              <div class="space-y-3">
                                <%= for segment <- @dashboard_segment_definitions do %>
                                  <% segment_name = segment["name"] || "" %>
                                  <% label = segment["label"] || segment_name || "Segment" %>
                                  <% current_value =
                                    Map.get(@dashboard_segment_values || %{}, segment_name, "") %>
                                  <div class="space-y-1">
                                    <label class="text-xs font-semibold text-slate-600 dark:text-slate-300">
                                      {label}
                                    </label>
                                    <%= if segment["type"] == "text" do %>
                                      <input
                                        type="text"
                                        name={"monitor[segment_values][#{segment_name}]"}
                                        value={current_value}
                                        placeholder={segment["placeholder"] || ""}
                                        class="block w-full rounded-md border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-900 px-3 py-2 text-sm text-slate-900 dark:text-white focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500"
                                      />
                                    <% else %>
                                      <% groups = segment["groups"] || [] %>
                                      <% has_items =
                                        Enum.any?(groups, fn group -> (group["items"] || []) != [] end) %>
                                      <div class="grid grid-cols-1">
                                        <select
                                          name={"monitor[segment_values][#{segment_name}]"}
                                          class="col-start-1 row-start-1 w-full appearance-none rounded-md border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-900 py-2 pr-8 pl-3 text-sm text-slate-900 dark:text-white focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500"
                                        >
                                          <%= for group <- groups do %>
                                            <% group_label = group["label"] %>
                                            <%= if group_label && group_label != "" do %>
                                              <optgroup label={group_label}>
                                                <%= for item <- group["items"] || [] do %>
                                                  <% option_value = item["value"] || "" %>
                                                  <option
                                                    value={option_value}
                                                    selected={option_value == current_value}
                                                  >
                                                    {item["label"] || option_value}
                                                  </option>
                                                <% end %>
                                              </optgroup>
                                            <% else %>
                                              <%= for item <- group["items"] || [] do %>
                                                <% option_value = item["value"] || "" %>
                                                <option
                                                  value={option_value}
                                                  selected={option_value == current_value}
                                                >
                                                  {item["label"] || option_value}
                                                </option>
                                              <% end %>
                                            <% end %>
                                          <% end %>
                                          <%= if !has_items do %>
                                            <option
                                              value=""
                                              selected={current_value in [nil, ""]}
                                              disabled
                                            >
                                              No options configured
                                            </option>
                                          <% end %>
                                        </select>
                                        <svg
                                          viewBox="0 0 16 16"
                                          fill="currentColor"
                                          aria-hidden="true"
                                          class="pointer-events-none col-start-1 row-start-1 mr-2 h-4 w-4 self-center justify-self-end text-slate-500 dark:text-slate-400"
                                        >
                                          <path
                                            d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
                                            clip-rule="evenodd"
                                            fill-rule="evenodd"
                                          />
                                        </svg>
                                      </div>
                                    <% end %>
                                  </div>
                                <% end %>
                              </div>
                              <%= for error <- @form[:segment_values].errors do %>
                                <p class="text-xs text-rose-600 dark:text-rose-400">
                                  {translate_error(error)}
                                </p>
                              <% end %>
                            </div>
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
                    <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
                      <div>
                        <.input
                          field={@form[:alert_metric_key]}
                          label="Metric key"
                          placeholder="e.g. app.signups.total"
                          required
                        />
                      </div>
                      <div>
                        <.input
                          field={@form[:alert_metric_path]}
                          label="Metric path"
                          placeholder="e.g. $.country.US"
                          required
                        />
                      </div>
                      <div>
                        <.input
                          field={@form[:alert_timeframe]}
                          label="Evaluation timeframe"
                          placeholder="e.g. 1h"
                        />
                      </div>
                      <div>
                        <.input
                          field={@form[:alert_granularity]}
                          label="Evaluation granularity"
                          placeholder="e.g. 5m"
                        />
                      </div>
                    </div>
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

              <div class="border-t border-gray-200 pt-6 dark:border-slate-700">
                <h3 class="text-sm font-semibold text-slate-900 dark:text-white">Delivery media</h3>
                <p class="mt-1 text-xs text-slate-500 dark:text-slate-400">
                  Choose the format to send when you trigger a delivery. You can update this later.
                </p>
                <% selected_media = @primary_delivery_medium %>
                <div class="mt-4 grid gap-3 sm:grid-cols-3">
                  <label
                    :for={option <- @delivery_media_options}
                    class={[
                      "relative flex cursor-pointer flex-col gap-1 rounded-md border border-slate-200 bg-white p-3 text-sm shadow-sm transition hover:border-teal-500 focus-within:border-teal-500 dark:border-slate-600 dark:bg-slate-800/70 dark:hover:border-teal-400",
                      option.value == selected_media &&
                        "border-teal-500 ring-1 ring-teal-500 dark:border-teal-400"
                    ]}
                  >
                    <input
                      type="radio"
                      class="sr-only peer"
                      name="monitor[delivery_media_types]"
                      id={"monitor-delivery-media-#{option.value}"}
                      value={Atom.to_string(option.value)}
                      checked={option.value == selected_media}
                    />
                    <div class="flex items-center justify-between">
                      <span class="font-semibold text-slate-900 dark:text-white">
                        {option.label}
                      </span>
                      <.icon
                        name="hero-check-circle"
                        class={[
                          "h-4 w-4 text-teal-500 opacity-0 transition-opacity peer-checked:opacity-100",
                          option.value == selected_media && "opacity-100"
                        ]}
                      />
                    </div>
                    <p class="text-xs text-slate-500 dark:text-slate-400">
                      {option.description}
                    </p>
                  </label>
                </div>
                <p class="mt-2 text-xs text-slate-500 dark:text-slate-400">
                  Select one format for now. Support for multiple formats is coming soon.
                </p>
                <p :if={@delivery_media_error} class="mt-2 text-xs text-rose-600 dark:text-rose-400">
                  {@delivery_media_error}
                </p>
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

    normalized = normalize_delivery_params(monitor_params, socket)
    errors = normalized.errors

    changeset =
      socket.assigns.monitor
      |> Monitors.change_monitor(normalized.params)
      |> Map.put(:action, :validate)
      |> add_delivery_errors(errors)

    {:noreply,
     socket
     |> assign(:delivery_handle_error, delivery_handle_error_message(errors))
     |> assign(:delivery_media_error, delivery_media_error_message(errors))
     |> assign_form(changeset, handles: normalized.handles, media: normalized.media)}
  end

  def handle_event("save", %{"monitor" => monitor_params}, socket) do
    Logger.debug("[MonitorForm] save event")
    normalized = normalize_delivery_params(monitor_params, socket)
    errors = normalized.errors

    if delivery_errors_present?(errors) do
      changeset =
        socket.assigns.monitor
        |> Monitors.change_monitor(normalized.params)
        |> add_delivery_errors(errors)
        |> Map.put(:action, :validate)

      {:noreply,
       socket
       |> assign(:delivery_handle_error, delivery_handle_error_message(errors))
       |> assign(:delivery_media_error, delivery_media_error_message(errors))
       |> assign_form(changeset, handles: normalized.handles, media: normalized.media)}
    else
      save_monitor(socket, socket.assigns.action, normalized.params, normalized.handles)
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
         |> assign(:delivery_media_error, nil)
         |> assign_form(Monitors.change_monitor(monitor, %{}), handles: handles)}

      {:error, %Changeset{} = changeset} ->
        delivery_errors = delivery_errors_from_changeset(changeset)

        {:noreply,
         socket
         |> assign(:delivery_handle_error, Map.get(delivery_errors, :handles))
         |> assign(:delivery_media_error, Map.get(delivery_errors, :media))
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
         |> assign(:delivery_media_error, nil)
         |> assign_form(Monitors.change_monitor(monitor, %{}), handles: handles)}

      {:error, :unauthorized} ->
        notify_parent({:error, "You do not have permission to update this monitor"})
        {:noreply, socket}

      {:error, %Changeset{} = changeset} ->
        delivery_errors = delivery_errors_from_changeset(changeset)

        {:noreply,
         socket
         |> assign(:delivery_handle_error, Map.get(delivery_errors, :handles))
         |> assign(:delivery_media_error, Map.get(delivery_errors, :media))
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
    alert_defaults = Monitors.default_alert_settings()
    default_media = Monitors.default_delivery_media()

    monitor
    |> Map.update(:report_settings, struct(ReportSettings, %{}), fn
      %ReportSettings{} = settings -> settings
      value when is_map(value) -> struct(ReportSettings, value)
    end)
    |> Map.put_new(:alert_metric_key, alert_defaults.alert_metric_key)
    |> Map.put_new(:alert_metric_path, alert_defaults.alert_metric_path)
    |> Map.put_new(:alert_timeframe, alert_defaults.alert_timeframe)
    |> Map.put_new(:alert_granularity, alert_defaults.alert_granularity)
    |> Map.update(:delivery_channels, [], fn
      [] ->
        []

      channels ->
        Enum.map(channels, fn
          %DeliveryChannel{} = channel -> channel
          value when is_map(value) -> struct(DeliveryChannel, value)
        end)
    end)
    |> Map.update(:delivery_media, default_media, fn
      [] ->
        default_media
        |> Enum.map(&coerce_delivery_medium_struct/1)

      nil ->
        default_media
        |> Enum.map(&coerce_delivery_medium_struct/1)

      media when is_list(media) ->
        Enum.map(media, &coerce_delivery_medium_struct/1)

      other ->
        other
        |> List.wrap()
        |> Enum.map(&coerce_delivery_medium_struct/1)
    end)
  end

  defp derive_action(%Monitor{id: nil}), do: :new
  defp derive_action(_monitor), do: :edit

  defp notify_parent(message), do: send(self(), {__MODULE__, message})

  defp normalize_delivery_params(params, socket) do
    membership = socket.assigns.current_membership

    handles =
      params
      |> fetch_param("delivery_handles")
      |> parse_handles()

    media_inputs =
      params
      |> fetch_param("delivery_media_types")
      |> parse_media_types()

    base_monitor = socket.assigns.persisted_monitor || %Monitor{}

    {channels, invalid_handles} =
      Monitors.delivery_channels_from_handles(
        handles,
        membership,
        base_monitor.delivery_channels || []
      )

    {media, invalid_media} =
      Monitors.delivery_media_from_types(
        media_inputs,
        base_monitor.delivery_media || []
      )

    prepared_params =
      params
      |> Map.delete("delivery_handles")
      |> Map.delete(:delivery_handles)
      |> Map.delete("delivery_media_types")
      |> Map.delete(:delivery_media_types)
      |> Map.put("delivery_channels", channels)
      |> Map.put("delivery_media", media)
      |> maybe_apply_source_ref()

    %{
      params: prepared_params,
      handles: handles,
      media: Monitors.delivery_media_types_from_media(media),
      errors: %{
        handles: invalid_handles,
        media: invalid_media
      }
    }
  end

  defp fetch_param(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} ->
        value

      :error ->
        try do
          atom_key = String.to_existing_atom(key)
          Map.get(params, atom_key)
        rescue
          ArgumentError ->
            nil
        end
    end
  end

  defp parse_handles(nil), do: []
  defp parse_handles(""), do: []

  defp parse_handles(value) when is_binary(value) do
    value
    |> String.split(~r/[\s,]+/, trim: true)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_handles(list) when is_list(list) do
    list
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_handles(%{} = map) do
    map
    |> Enum.sort_by(fn {key, _} -> parse_media_index(key) end)
    |> Enum.map(fn {_k, v} -> v end)
    |> parse_handles()
  end

  defp parse_handles(other), do: parse_handles(to_string(other))

  defp parse_media_types(nil), do: []
  defp parse_media_types(""), do: []

  defp parse_media_types(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: [], else: [trimmed]
  end

  defp parse_media_types(list) when is_list(list) do
    list
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_media_types(%{} = map) do
    map
    |> Enum.sort_by(fn {key, _} -> parse_media_index(key) end)
    |> Enum.map(fn {_k, v} -> v end)
    |> parse_media_types()
  end

  defp parse_media_types(other), do: parse_media_types(to_string(other))

  defp parse_media_index(key) when is_integer(key), do: key

  defp parse_media_index(key) when is_binary(key) do
    case Integer.parse(key) do
      {int, _} -> int
      :error -> key
    end
  end

  defp parse_media_index(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> parse_media_index()
  end

  defp parse_media_index(key), do: key

  defp coerce_delivery_medium_struct(%DeliveryMedium{} = medium), do: medium

  defp coerce_delivery_medium_struct(value) when is_map(value) do
    try do
      attrs =
        Enum.reduce(value, %{}, fn
          {key, val}, acc when is_atom(key) ->
            Map.put(acc, key, val)

          {key, val}, acc when is_binary(key) ->
            atom_key =
              case key do
                "medium" -> :medium
                "id" -> :id
                other -> String.to_atom(other)
              end

            Map.put(acc, atom_key, val)

          {key, val}, acc ->
            Map.put(acc, key, val)
        end)

      medium_input = Map.get(attrs, :medium)

      medium_value =
        case normalize_medium_atom(medium_input) do
          nil when is_atom(medium_input) -> medium_input
          nil -> nil
          normalized -> normalized
        end

      attrs
      |> Map.put(:medium, medium_value)
      |> then(&struct(DeliveryMedium, &1))
    rescue
      ArgumentError ->
        struct(DeliveryMedium, %{})
    end
  end

  defp coerce_delivery_medium_struct(_), do: struct(DeliveryMedium, %{})

  @known_media [:pdf, :png_light, :png_dark, :file_csv, :file_json]

  defp normalize_medium_atom(value) when is_atom(value) do
    if value in @known_media, do: value, else: nil
  end

  defp normalize_medium_atom(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.replace(" ", "_")
    |> case do
      "pdf" -> :pdf
      "png_light" -> :png_light
      "png_dark" -> :png_dark
      "file_csv" -> :file_csv
      "file_json" -> :file_json
      _ -> nil
    end
  end

  defp normalize_medium_atom(_), do: nil

  defp add_delivery_errors(%Changeset{} = changeset, errors) when is_map(errors) do
    changeset
    |> add_delivery_handle_errors(Map.get(errors, :handles, []))
    |> add_delivery_media_errors(Map.get(errors, :media, []))
  end

  defp add_delivery_handle_errors(%Changeset{} = changeset, []), do: changeset

  defp add_delivery_handle_errors(%Changeset{} = changeset, invalid_handles) do
    Enum.reduce(invalid_handles, changeset, fn handle, acc ->
      Changeset.add_error(acc, :delivery_channels, "unknown delivery target: #{handle}")
    end)
  end

  defp add_delivery_media_errors(%Changeset{} = changeset, []), do: changeset

  defp add_delivery_media_errors(%Changeset{} = changeset, invalid_media) do
    Enum.reduce(invalid_media, changeset, fn medium, acc ->
      Changeset.add_error(acc, :delivery_media, "unknown delivery medium: #{medium}")
    end)
  end

  defp delivery_errors_present?(errors) when is_map(errors) do
    errors
    |> Map.values()
    |> Enum.any?(fn
      [_ | _] -> true
      _ -> false
    end)
  end

  defp delivery_errors_present?(_), do: false

  defp delivery_handle_error_message(%{handles: []}), do: nil

  defp delivery_handle_error_message(%{handles: handles}) do
    case handles do
      [] -> nil
      list -> "Unknown delivery targets: " <> Enum.join(list, ", ")
    end
  end

  defp delivery_handle_error_message(_), do: nil

  defp delivery_media_error_message(%{media: []}), do: nil

  defp delivery_media_error_message(%{media: media}) do
    case media do
      [] -> nil
      list -> "Unknown delivery media types: " <> Enum.join(list, ", ")
    end
  end

  defp delivery_media_error_message(_), do: nil

  defp delivery_errors_from_changeset(%Changeset{} = changeset) do
    Enum.reduce(changeset.errors, %{handles: nil, media: nil}, fn
      {:delivery_channels, {message, _}}, acc ->
        Map.update(acc, :handles, message, &(&1 || message))

      {:delivery_media, {message, _}}, acc ->
        Map.update(acc, :media, message, &(&1 || message))

      _, acc ->
        acc
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
    |> Enum.map(fn {type, list} ->
      {Source.type_label(type), Enum.sort_by(list, &Source.display_name/1)}
    end)
    |> Enum.sort_by(fn {label, _} -> label end)
  end

  defp source_errors(form) do
    (form[:source_type].errors ++ form[:source_id].errors)
    |> Enum.uniq()
  end

  defp assign_form(socket, %Changeset{} = changeset, opts \\ []) do
    monitor = Changeset.apply_changes(changeset)
    base_monitor = changeset.data || monitor

    handles =
      Keyword.get(opts, :handles) ||
        Monitors.delivery_handles_from_channels(base_monitor.delivery_channels || [])

    media =
      case Keyword.fetch(opts, :media) do
        {:ok, media_types} -> List.wrap(media_types)
        :error -> Monitors.delivery_media_types_from_media(base_monitor.delivery_media || [])
      end

    primary_medium =
      List.first(media) ||
        base_monitor
        |> Map.get(:delivery_media, [])
        |> Monitors.delivery_media_types_from_media()
        |> List.first()

    dashboards = socket.assigns[:available_dashboards] || []

    dashboard_id =
      cond do
        monitor.dashboard && monitor.dashboard.id -> to_string(monitor.dashboard.id)
        value = Changeset.get_field(changeset, :dashboard_id) -> value && to_string(value)
        true -> nil
      end

    selected_dashboard =
      Enum.find(dashboards, fn dashboard -> to_string(dashboard.id) == dashboard_id end)

    dashboard_segments =
      case selected_dashboard do
        %{segments: segments} when is_list(segments) -> segments
        _ -> []
      end

    previous_dashboard_id = socket.assigns[:selected_dashboard_id]

    reset_segments? =
      previous_dashboard_id && dashboard_id && previous_dashboard_id != dashboard_id

    overrides =
      if reset_segments?, do: %{}, else: monitor.segment_values || %{}

    {segment_values, segments_with_current} =
      DashboardSegments.compute_state(dashboard_segments, overrides, %{})

    monitor = %{monitor | segment_values: segment_values}

    changeset =
      if Changeset.get_field(changeset, :segment_values) == segment_values do
        changeset
      else
        Changeset.put_change(changeset, :segment_values, segment_values)
      end

    socket
    |> assign(:form, to_form(changeset))
    |> assign(:monitor, monitor)
    |> assign(:delivery_handles, handles)
    |> assign(:selected_delivery_media, media)
    |> assign(:primary_delivery_medium, primary_medium)
    |> assign(:selected_dashboard_id, dashboard_id)
    |> assign(:dashboard_segment_definitions, segments_with_current)
    |> assign(:dashboard_segment_values, segment_values)
    |> assign(:selected_source_ref, monitor_source_ref(monitor))
  end
end
