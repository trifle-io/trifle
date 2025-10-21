defmodule TrifleApp.MonitorComponents do
  @moduledoc """
  Reusable UI components for monitor detail pages.
  """
  use TrifleApp, :html

  alias Trifle.Monitors
  alias Trifle.Monitors.Monitor

  ## Shared helpers

  defp monitor_status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold uppercase tracking-wide",
      @status == :active && "bg-teal-100 text-teal-800 dark:bg-teal-500/10 dark:text-teal-200",
      @status == :paused && "bg-slate-200 text-slate-700 dark:bg-slate-700 dark:text-slate-200"
    ]}>
      {@label}
    </span>
    """
  end

  attr :monitor, Monitor, required: true
  attr :executions, :list, default: []

  def trigger_history(assigns) do
    ~H"""
    <div class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-6 shadow-sm">
      <% targets = delivery_target_badges(@monitor.delivery_channels) %>
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-semibold text-slate-900 dark:text-white">Delivery</h3>
        <span class="text-xs text-slate-500 dark:text-slate-400">Up to 25 most recent events</span>
      </div>
      <div class="mt-4">
        <h4 class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
          Delivery targets
        </h4>
        <div :if={Enum.any?(targets)} class="mt-3 flex flex-wrap gap-2">
          <span
            :for={target <- targets}
            class="inline-flex items-center gap-1 rounded-full bg-teal-600/10 px-2.5 py-1 text-[0.7rem] font-semibold text-teal-800 dark:bg-teal-500/10 dark:text-teal-200"
          >
            <span class="uppercase text-teal-500 dark:text-teal-300">{target.badge}</span>
            <span>{target.label}</span>
          </span>
        </div>
        <p :if={Enum.empty?(targets)} class="mt-3 text-xs text-slate-500 dark:text-slate-400">
          No delivery targets configured.
        </p>
      </div>
      <div class="mt-6">
        <h4 class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
          Recent triggers
        </h4>
        <div
          :if={Enum.empty?(@executions)}
          class="mt-3 rounded-lg border border-dashed border-slate-300 bg-slate-50 p-6 text-center dark:border-slate-700/70 dark:bg-slate-800/60"
        >
          <p class="text-sm font-medium text-slate-600 dark:text-slate-300">
            This monitor has not triggered yet.
          </p>
          <p class="mt-2 text-xs text-slate-500 dark:text-slate-400">
            Once triggers occur, you will see a chronological log with the reason and outcome.
          </p>
        </div>
        <dl :if={Enum.any?(@executions)} class="mt-4 space-y-4">
          <div
            :for={execution <- @executions}
            class="rounded-lg border border-slate-200 bg-slate-50 p-4 dark:border-slate-700/70 dark:bg-slate-800/70"
          >
            <div class="flex flex-wrap items-center justify-between gap-2">
              <div class="flex items-center gap-2">
                <%= case execution.status do %>
                  <% "delivered" -> %>
                    <.icon name="hero-check-circle" class="h-4 w-4 text-emerald-500" />
                  <% "failed" -> %>
                    <.icon name="hero-x-circle" class="h-4 w-4 text-rose-500" />
                  <% _ -> %>
                    <.icon name="hero-bolt" class="h-4 w-4 text-amber-500" />
                <% end %>
                <p class="text-sm font-semibold text-slate-900 dark:text-white">
                  {execution.summary || humanize_status(execution.status)}
                </p>
              </div>
              <span class="text-xs font-medium text-slate-500 dark:text-slate-300">
                {format_timestamp(execution.triggered_at)}
              </span>
            </div>
            <p
              :if={map_size(execution.details || %{}) > 0}
              class="mt-2 text-xs text-slate-600 dark:text-slate-300"
            >
              {format_details(execution.details)}
            </p>
          </div>
        </dl>
      </div>
    </div>
    """
  end

  attr :monitor, Monitor, required: true
  attr :dashboard, :any, default: nil

  def report_panel(assigns) do
    ~H"""
    <div class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-6 shadow-sm">
      <h3 class="text-sm font-semibold text-slate-900 dark:text-white">Report details</h3>
      <dl class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
            Dashboard
          </dt>
          <dd class="mt-1 text-sm font-medium text-slate-900 dark:text-white">
            <%= if @dashboard do %>
              <.link
                navigate={~p"/dashboards/#{@dashboard.id}"}
                class="text-teal-600 hover:text-teal-500"
              >
                {@dashboard.name}
              </.link>
            <% else %>
              <span class="text-slate-500 dark:text-slate-400">Dashboard unavailable</span>
            <% end %>
          </dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
            Delivery cadence
          </dt>
          <dd class="mt-1 text-sm font-medium text-slate-900 dark:text-white">
            {format_frequency(@monitor.report_settings)}
          </dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
            Timeframe window
          </dt>
          <dd class="mt-1 text-sm text-slate-700 dark:text-slate-200">
            {(@monitor.report_settings && @monitor.report_settings.timeframe) ||
              "Defaults to dashboard"}
          </dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
            Granularity
          </dt>
          <dd class="mt-1 text-sm text-slate-700 dark:text-slate-200">
            {(@monitor.report_settings && @monitor.report_settings.granularity) || "Auto"}
          </dd>
        </div>
        <div :if={@monitor.report_settings && @monitor.report_settings.frequency == :custom}>
          <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
            CRON expression
          </dt>
          <dd class="mt-1 text-sm text-slate-700 dark:text-slate-200">
            {@monitor.report_settings.custom_cron}
          </dd>
        </div>
      </dl>
    </div>
    """
  end

  attr :monitor, Monitor, required: true

  def alert_panel(assigns) do
    ~H"""
    <div class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-6 shadow-sm">
      <h3 class="text-sm font-semibold text-slate-900 dark:text-white">Alert details</h3>

      <dl class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
            Metric key
          </dt>
          <dd class="mt-1 text-sm font-medium text-slate-900 dark:text-white">
            <code class="rounded bg-slate-200/70 px-1.5 py-0.5 text-xs font-semibold text-slate-900 dark:bg-slate-700 dark:text-slate-200">
              {(@monitor.alert_settings && @monitor.alert_settings.metric_key) || "—"}
            </code>
          </dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
            Metric path
          </dt>
          <dd class="mt-1 text-sm font-medium text-slate-900 dark:text-white">
            <code class="rounded bg-slate-200/70 px-1.5 py-0.5 text-xs font-semibold text-slate-900 dark:bg-slate-700 dark:text-slate-200">
              {(@monitor.alert_settings && @monitor.alert_settings.metric_path) || "—"}
            </code>
          </dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
            Evaluation timeframe
          </dt>
          <dd class="mt-1 text-sm text-slate-700 dark:text-slate-200">
            {@monitor.alert_settings && (@monitor.alert_settings.timeframe || "defaults to monitor")}
          </dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
            Granularity
          </dt>
          <dd class="mt-1 text-sm text-slate-700 dark:text-slate-200">
            {@monitor.alert_settings && (@monitor.alert_settings.granularity || "Auto")}
          </dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
            Analysis strategy
          </dt>
          <dd class="mt-1 text-sm font-medium text-slate-900 dark:text-white">
            {format_analysis_strategy(@monitor.alert_settings)}
          </dd>
        </div>
      </dl>
      <div class="mt-4 rounded-md border border-dashed border-amber-300 bg-amber-50/70 dark:border-amber-400/50 dark:bg-amber-500/10 p-4 text-xs text-amber-900 dark:text-amber-200">
        Threshold configuration will arrive soon. Define the structure now so we can extend it with concrete rules later.
      </div>
    </div>
    """
  end

  ## Formatting helpers

  defp humanize_status(nil), do: "Triggered"
  defp humanize_status(status) when is_binary(status), do: String.capitalize(status)

  defp humanize_status(status) when is_atom(status),
    do: status |> Atom.to_string() |> humanize_status()

  defp format_timestamp(nil), do: "Unknown time"

  defp format_timestamp(datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%b %-d, %Y · %H:%M UTC")
  rescue
    ArgumentError -> "--"
  end

  defp format_details(details) when is_map(details) do
    details
    |> Enum.map(fn {key, value} -> "#{Phoenix.Naming.humanize(key)}: #{inspect(value)}" end)
    |> Enum.join(" · ")
  end

  defp format_details(_), do: "No additional context captured."

  defp format_frequency(%Monitor.ReportSettings{frequency: :custom, custom_cron: cron})
       when is_binary(cron) and cron != "" do
    "Custom schedule (#{cron})"
  end

  defp format_frequency(%Monitor.ReportSettings{frequency: frequency})
       when not is_nil(frequency) do
    frequency
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_frequency(_), do: "Weekly"

  defp format_analysis_strategy(%Monitor.AlertSettings{analysis_strategy: strategy})
       when not is_nil(strategy) do
    strategy
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_analysis_strategy(_), do: "Threshold"

  defp delivery_target_badges(channels) do
    channels
    |> List.wrap()
    |> Enum.map(&delivery_target_from_channel/1)
    |> Enum.reject(&is_nil/1)
  end

  defp delivery_target_from_channel(nil), do: nil

  defp delivery_target_from_channel(channel) when is_map(channel) do
    channel_type = Map.get(channel, :channel) || Map.get(channel, "channel")
    handle = delivery_handle(channel)

    label =
      [
        Map.get(channel, :label) || Map.get(channel, "label"),
        handle,
        Map.get(channel, :target) || Map.get(channel, "target")
      ]
      |> Enum.find(fn value ->
        is_binary(value) and String.trim(value) != ""
      end)
      |> case do
        nil -> "Delivery target"
        value -> value
      end

    %{
      badge: delivery_badge(channel_type),
      label: label
    }
  end

  defp delivery_badge(channel) when is_atom(channel), do: delivery_badge(Atom.to_string(channel))
  defp delivery_badge("email"), do: "Email"
  defp delivery_badge("slack_webhook"), do: "Slack"
  defp delivery_badge("webhook"), do: "Webhook"
  defp delivery_badge("custom"), do: "Custom"
  defp delivery_badge(_), do: "Channel"

  defp delivery_handle(channel) do
    channel
    |> List.wrap()
    |> Monitors.delivery_handles_from_channels()
    |> List.first()
  end
end
