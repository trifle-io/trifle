defmodule TrifleApi.MonitorsJSON do
  alias Trifle.Monitors.Alert
  alias Trifle.Monitors.Monitor

  def render("index.json", %{monitors: monitors}) do
    %{data: Enum.map(monitors, &format_monitor/1)}
  end

  def render("show.json", %{monitor: monitor}) do
    %{data: format_monitor(monitor)}
  end

  defp format_monitor(%Monitor{} = monitor) do
    %{
      id: monitor.id,
      name: monitor.name,
      description: monitor.description,
      type: to_string(monitor.type || ""),
      status: to_string(monitor.status || ""),
      locked: monitor.locked,
      target: monitor.target || %{},
      segment_values: monitor.segment_values || %{},
      trigger_status: to_string(monitor.trigger_status || ""),
      source_type: format_source_type(monitor.source_type),
      source_id: monitor.source_id,
      dashboard_id: monitor.dashboard_id,
      alert_metric_key: monitor.alert_metric_key,
      alert_metric_path: monitor.alert_metric_path,
      alert_timeframe: monitor.alert_timeframe,
      alert_granularity: monitor.alert_granularity,
      alert_notify_every: monitor.alert_notify_every,
      report_settings: format_report_settings(monitor.report_settings),
      delivery_channels: format_delivery_channels(monitor.delivery_channels),
      delivery_media: format_delivery_media(monitor.delivery_media),
      alerts: format_alerts(monitor.alerts),
      inserted_at: format_datetime(monitor.inserted_at),
      updated_at: format_datetime(monitor.updated_at)
    }
  end

  defp format_alerts(alerts) when is_list(alerts) do
    alerts
    |> Enum.map(&format_alert/1)
  end

  defp format_alerts(_), do: []

  defp format_alert(%Alert{} = alert) do
    %{
      id: alert.id,
      analysis_strategy: to_string(alert.analysis_strategy || ""),
      status: to_string(alert.status || ""),
      settings: format_alert_settings(alert.settings),
      last_summary: alert.last_summary,
      last_evaluated_at: format_datetime(alert.last_evaluated_at),
      continuous_trigger_count: alert.continuous_trigger_count,
      inserted_at: format_datetime(alert.inserted_at),
      updated_at: format_datetime(alert.updated_at)
    }
  end

  defp format_alert(_), do: %{}

  defp format_report_settings(nil), do: nil

  defp format_report_settings(settings) when is_map(settings) do
    %{
      frequency: format_enum(Map.get(settings, :frequency)),
      timeframe: Map.get(settings, :timeframe),
      granularity: Map.get(settings, :granularity)
    }
  end

  defp format_delivery_channels(channels) when is_list(channels) do
    Enum.map(channels, fn channel ->
      %{
        channel: format_enum(Map.get(channel, :channel)),
        label: Map.get(channel, :label),
        target: Map.get(channel, :target),
        config: Map.get(channel, :config) || %{}
      }
    end)
  end

  defp format_delivery_channels(_), do: []

  defp format_delivery_media(media) when is_list(media) do
    Enum.map(media, fn item ->
      %{
        medium: format_enum(Map.get(item, :medium))
      }
    end)
  end

  defp format_delivery_media(_), do: []

  defp format_alert_settings(nil), do: %{}

  defp format_alert_settings(settings) when is_map(settings) do
    settings
    |> Map.from_struct()
    |> Map.delete(:__struct__)
  end

  defp format_alert_settings(_), do: %{}

  defp format_source_type(nil), do: nil
  defp format_source_type(value) when is_atom(value), do: Atom.to_string(value)
  defp format_source_type(value), do: to_string(value)

  defp format_enum(nil), do: nil
  defp format_enum(value) when is_atom(value), do: Atom.to_string(value)
  defp format_enum(value), do: to_string(value)

  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_datetime(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  defp format_datetime(_), do: nil
end
