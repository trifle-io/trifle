defmodule Trifle.Monitors.Schedule do
  @moduledoc """
  Evaluates whether a monitor is due for execution based on its frequency or
  alert granularity. All calculations are performed in UTC.
  """

  require Timex
  require Logger

  alias Trifle.Monitors.Monitor

  @typep timestamp :: DateTime.t() | nil

  @doc """
  Returns `true` when the given `monitor` should run at the provided `now`
  datetime, taking the `last_triggered_at` into account.
  """
  @spec due?(Monitor.t(), DateTime.t(), timestamp()) :: boolean()
  def due?(%Monitor{status: :active, type: :report} = monitor, now, last_triggered_at) do
    report_due?(monitor, now, last_triggered_at)
  end

  def due?(%Monitor{status: :active, type: :alert} = monitor, now, last_triggered_at) do
    alert_due?(monitor, now, last_triggered_at)
  end

  def due?(%Monitor{status: :paused, type: :alert} = monitor, now, last_triggered_at) do
    alert_due?(monitor, now, last_triggered_at)
  end

  def due?(_monitor, _now, _last_triggered_at), do: false

  defp report_due?(%Monitor{} = monitor, now, last_triggered_at) do
    frequency =
      monitor.report_settings
      |> case do
        nil -> :weekly
        settings -> Map.get(settings, :frequency, :weekly)
      end

    period_start = report_period_start(frequency, now)

    normalized_last =
      last_triggered_at
      |> normalize_timestamp()
      |> DateTime.truncate(:second)

    result = DateTime.compare(normalized_last, period_start) == :lt

    log_report_due(monitor, now, last_triggered_at, frequency, period_start, result)
    result
  end

  defp alert_due?(%Monitor{} = monitor, now, last_triggered_at) do
    result =
      case granularity_minutes(monitor.alert_granularity) do
        {:ok, minutes} when minutes > 0 ->
          bucket_end = truncate_to_minute(now)
          boundary? = boundary_hit?(bucket_end, minutes)

          cond do
            not boundary? ->
              false

            is_nil(last_triggered_at) ->
              true

            DateTime.compare(normalize_timestamp(last_triggered_at), bucket_end) == :lt ->
              true

            true ->
              false
          end

        _ ->
          false
      end

    log_alert_due(monitor, now, last_triggered_at, result)
    result
  end

  defp report_period_start(:hourly, now), do: Timex.beginning_of_hour(now)
  defp report_period_start(:daily, now), do: Timex.beginning_of_day(now)
  defp report_period_start(:weekly, now), do: Timex.beginning_of_week(now)
  defp report_period_start(:monthly, now), do: Timex.beginning_of_month(now)
  defp report_period_start(_other, now), do: Timex.beginning_of_day(now)

  defp truncate_to_minute(%DateTime{} = dt) do
    %{dt | second: 0, microsecond: {0, 0}}
  end

  defp truncate_to_minute(%NaiveDateTime{} = dt) do
    %{dt | second: 0, microsecond: {0, 0}}
  end

  defp truncate_to_minute(other), do: other

  defp log_report_due(monitor, now, last_triggered_at, frequency, period_start, result) do
    Logger.debug(fn ->
      "[Schedule] report_due? monitor=#{monitor_id(monitor)} freq=#{frequency} now=#{format_dt(now)} last=#{format_dt(last_triggered_at)} period_start=#{format_dt(period_start)} due=#{result}"
    end)
  end

  defp log_alert_due(monitor, now, last_triggered_at, result) do
    Logger.debug(fn ->
      "[Schedule] alert_due? monitor=#{monitor_id(monitor)} granularity=#{monitor.alert_granularity} now=#{format_dt(now)} last=#{format_dt(last_triggered_at)} due=#{result}"
    end)
  end

  defp format_dt(nil), do: "nil"
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_dt(other), do: inspect(other)

  defp monitor_id(%Monitor{id: id}) when not is_nil(id), do: id
  defp monitor_id(_), do: "unknown"

  defp normalize_timestamp(nil), do: ~U[1970-01-01 00:00:00Z]

  defp normalize_timestamp(%DateTime{} = dt) do
    DateTime.truncate(dt, :second)
  end

  defp normalize_timestamp(%NaiveDateTime{} = dt) do
    dt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp normalize_timestamp(other) do
    Logger.warning("Unexpected timestamp type for monitor schedule: #{inspect(other)}")
    ~U[1970-01-01 00:00:00Z]
  end

  defp boundary_hit?(bucket_end, minutes) when minutes <= 0, do: false

  defp boundary_hit?(bucket_end, minutes) do
    bucket_end = truncate_to_minute(bucket_end)

    unix =
      case bucket_end do
        %DateTime{} = dt ->
          DateTime.to_unix(dt, :second)

        %NaiveDateTime{} = naive ->
          naive |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:second)

        _ ->
          nil
      end

    if is_integer(unix) do
      total_minutes =
        unix
        |> div(60)

      rem(total_minutes, minutes) == 0
    else
      false
    end
  end

  @doc """
  Parses monitor granularity strings into whole minutes. Returns `{:ok, minutes}`
  or `:error` when the granularity cannot be interpreted.
  """
  @spec granularity_minutes(String.t() | nil) :: {:ok, pos_integer()} | :error
  def granularity_minutes(nil), do: {:ok, 1}
  def granularity_minutes(""), do: {:ok, 1}

  def granularity_minutes(value) when is_binary(value) do
    case Regex.run(~r/^(\d+)\s*([smhdw])$/i, String.trim(value)) do
      [_, amount, unit] ->
        amount
        |> String.to_integer()
        |> convert_unit(String.downcase(unit))

      _ ->
        :error
    end
  end

  def granularity_minutes(_other), do: :error

  defp convert_unit(amount, "s") when amount <= 0, do: :error
  defp convert_unit(amount, "s"), do: {:ok, max(1, ceil_div(amount, 60))}
  defp convert_unit(amount, "m") when amount <= 0, do: :error
  defp convert_unit(amount, "m"), do: {:ok, amount}
  defp convert_unit(amount, "h") when amount <= 0, do: :error
  defp convert_unit(amount, "h"), do: {:ok, amount * 60}
  defp convert_unit(amount, "d") when amount <= 0, do: :error
  defp convert_unit(amount, "d"), do: {:ok, amount * 24 * 60}
  defp convert_unit(amount, "w") when amount <= 0, do: :error
  defp convert_unit(amount, "w"), do: {:ok, amount * 7 * 24 * 60}
  defp convert_unit(_amount, _unit), do: :error

  defp ceil_div(a, b) when is_integer(a) and is_integer(b) and b != 0 do
    div(a + b - 1, b)
  end
end
