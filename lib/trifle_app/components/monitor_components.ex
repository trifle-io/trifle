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
  attr :timezone, :string, default: "UTC"
  attr :show_details_event, :string, default: nil
  attr :phx_target, :any, default: nil

  def trigger_history(assigns) do
    ~H"""
    <div class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-6 shadow-sm">
      <% targets = delivery_target_badges(@monitor.delivery_channels) %>
      <% media = delivery_media_badges(@monitor.delivery_media) %>
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
          Delivery media
        </h4>
        <div :if={Enum.any?(media)} class="mt-3 flex flex-wrap gap-2">
          <span
            :for={entry <- media}
            class="inline-flex items-center gap-1 rounded-full bg-slate-100 px-2.5 py-1 text-[0.7rem] font-semibold text-slate-800 dark:bg-slate-700/70 dark:text-slate-100"
            title={entry.description}
          >
            <span class="uppercase text-slate-500 dark:text-slate-300">{entry.badge}</span>
            <span>{entry.label}</span>
          </span>
        </div>
        <p :if={Enum.empty?(media)} class="mt-3 text-xs text-slate-500 dark:text-slate-400">
          No delivery media selected.
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
        <ul :if={Enum.any?(@executions)} class="mt-3 space-y-2">
          <li
            :for={execution <- @executions}
            class={[
              "flex items-center justify-between rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-xs font-medium text-slate-700 dark:border-slate-700/70 dark:bg-slate-800/70 dark:text-slate-200",
              @show_details_event &&
                "cursor-pointer transition hover:border-slate-300 hover:bg-white dark:hover:border-slate-600 dark:hover:bg-slate-800"
            ]}
            phx-click={@show_details_event}
            phx-value-id={execution.id}
            phx-target={@phx_target}
            role={if @show_details_event, do: "button", else: nil}
            tabindex={if @show_details_event, do: 0, else: nil}
          >
            <div class="flex items-center gap-2">
              <span class={trigger_icon_class(execution.status)}>
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="h-4 w-4"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z"
                  />
                </svg>
              </span>
              <span class="uppercase tracking-wide">
                {String.upcase(execution.status || "unknown")}
              </span>
            </div>
            <span>{format_full_timestamp(execution.triggered_at, @timezone)}</span>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  attr :monitor, Monitor, required: true
  attr :dashboard, :any, default: nil
  attr :source_label, :string, default: nil

  def report_panel(assigns) do
    ~H"""
    <div class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-6 shadow-sm">
      <h3 class="text-sm font-semibold text-slate-900 dark:text-white">Report details</h3>
      <dl class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div class="space-y-4">
          <div>
            <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
              Source
            </dt>
            <dd class="mt-1 text-sm font-medium text-slate-900 dark:text-white">
              {@source_label || default_source_label(@monitor)}
            </dd>
          </div>
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
        </div>
        <div class="space-y-4">
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
        </div>
      </dl>
    </div>
    """
  end

  attr :monitor, Monitor, required: true
  attr :source_label, :string, default: nil

  def alert_panel(assigns) do
    ~H"""
    <div class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-6 shadow-sm">
      <h3 class="text-sm font-semibold text-slate-900 dark:text-white">Alert details</h3>

      <dl class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div class="space-y-4">
          <div>
            <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
              Source
            </dt>
            <dd class="mt-1 text-sm font-medium text-slate-900 dark:text-white">
              {@source_label || default_source_label(@monitor)}
            </dd>
          </div>
          <div>
            <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
              Metric key
            </dt>
            <dd class="mt-1 text-sm font-medium text-slate-900 dark:text-white">
              <code class="rounded bg-slate-200/70 px-1.5 py-0.5 text-xs font-semibold text-slate-900 dark:bg-slate-700 dark:text-slate-200">
                {present_or_dash(@monitor.alert_metric_key)}
              </code>
            </dd>
          </div>
          <div>
            <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
              Metric path
            </dt>
            <dd class="mt-1 text-sm font-medium text-slate-900 dark:text-white">
              <code class="rounded bg-slate-200/70 px-1.5 py-0.5 text-xs font-semibold text-slate-900 dark:bg-slate-700 dark:text-slate-200">
                {present_or_dash(@monitor.alert_metric_path)}
              </code>
            </dd>
          </div>
        </div>
        <div class="space-y-4">
          <div>
            <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
              Evaluation timeframe
            </dt>
            <dd class="mt-1 text-sm text-slate-700 dark:text-slate-200">
              {@monitor.alert_timeframe || "Defaults to monitor"}
            </dd>
          </div>
          <div>
            <dt class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">
              Granularity
            </dt>
            <dd class="mt-1 text-sm text-slate-700 dark:text-slate-200">
              {@monitor.alert_granularity || "Auto"}
            </dd>
          </div>
        </div>
      </dl>
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

  defp format_full_timestamp(nil, _timezone), do: "--"

  defp format_full_timestamp(%DateTime{} = datetime, timezone) do
    trimmed_timezone =
      case timezone do
        value when is_binary(value) -> String.trim(value)
        _ -> nil
      end

    target_timezone =
      if trimmed_timezone && trimmed_timezone != "", do: trimmed_timezone, else: "UTC"

    with {:ok, shifted} <- DateTime.shift_zone(datetime, target_timezone) do
      format_shifted_timestamp(shifted, target_timezone)
    else
      _ ->
        datetime
        |> DateTime.shift_zone!("UTC")
        |> format_shifted_timestamp("UTC")
    end
  end

  defp format_shifted_timestamp(%DateTime{} = datetime, "UTC") do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_shifted_timestamp(%DateTime{} = datetime, _timezone) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end

  defp format_details(details) when is_map(details) do
    details
    |> Enum.map(fn {key, value} -> "#{Phoenix.Naming.humanize(key)}: #{inspect(value)}" end)
    |> Enum.join(" · ")
  end

  defp format_details(_), do: "No additional context captured."

  defp format_frequency(%Monitor.ReportSettings{frequency: :hourly}), do: "Hourly"

  defp format_frequency(%Monitor.ReportSettings{frequency: frequency})
       when not is_nil(frequency) do
    frequency
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_frequency(_), do: "Weekly"

  defp present_or_dash(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: "—", else: trimmed
  end

  defp present_or_dash(value) when is_atom(value), do: present_or_dash(Atom.to_string(value))
  defp present_or_dash(nil), do: "—"
  defp present_or_dash(value), do: to_string(value)

  defp trigger_icon_class(status) do
    case normalized_status(status) do
      "passed" -> "text-emerald-500"
      "ok" -> "text-emerald-500"
      "alerted" -> "text-red-500"
      "suppressed" -> "text-amber-500"
      "failed" -> "text-slate-400"
      "error" -> "text-slate-400"
      "partial_failure" -> "text-slate-400"
      _ -> "text-slate-400"
    end
  end

  defp normalized_status(status) when is_atom(status), do: Atom.to_string(status)
  defp normalized_status(status) when is_binary(status), do: String.downcase(status)
  defp normalized_status(_), do: ""

  defp delivery_target_badges(channels) do
    channels
    |> List.wrap()
    |> Enum.map(&delivery_target_from_channel/1)
    |> Enum.reject(&is_nil/1)
  end

  defp delivery_media_badges(media) do
    option_map = Monitors.delivery_media_option_map()

    media
    |> Monitors.delivery_media_types_from_media()
    |> Enum.uniq()
    |> Enum.map(fn medium ->
      option = Map.get(option_map, medium, %{})

      %{
        badge: delivery_media_badge(medium),
        label: option[:label] || default_media_label(medium),
        description: option[:description] || default_media_label(medium)
      }
    end)
  end

  defp default_media_label(medium) when is_atom(medium) do
    medium
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp default_media_label(value), do: to_string(value)

  defp delivery_media_badge(:pdf), do: "PDF"
  defp delivery_media_badge(:png_light), do: "PNG"
  defp delivery_media_badge(:png_dark), do: "PNG"
  defp delivery_media_badge(:file_csv), do: "CSV"
  defp delivery_media_badge(:file_json), do: "JSON"

  defp delivery_media_badge(value) when is_atom(value) do
    value |> Atom.to_string() |> String.upcase()
  end

  defp delivery_media_badge(value), do: to_string(value)

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
  defp delivery_badge("discord_webhook"), do: "Discord"
  defp delivery_badge("webhook"), do: "Webhook"
  defp delivery_badge("custom"), do: "Custom"
  defp delivery_badge(_), do: "Channel"

  defp delivery_handle(channel) do
    channel
    |> List.wrap()
    |> Monitors.delivery_handles_from_channels()
    |> List.first()
  end

  defp default_source_label(%Monitor{source_type: nil}), do: "—"

  defp default_source_label(%Monitor{} = monitor) do
    type_label = source_type_label(monitor.source_type)

    case monitor.source_id do
      nil -> type_label
      id -> "#{type_label} · #{id}"
    end
  end

  defp source_type_label(:database), do: "Database"
  defp source_type_label(:project), do: "Project"

  defp source_type_label(value) when is_atom(value) do
    value |> Atom.to_string() |> String.capitalize()
  end

  defp source_type_label(value), do: to_string(value)
end
