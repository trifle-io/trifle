defmodule Trifle.Monitors.Schedule do
  @moduledoc """
  Evaluates whether a monitor is due for execution based on its frequency or
  alert granularity. All calculations are performed in UTC.
  """

  require Timex

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

  def due?(_monitor, _now, _last_triggered_at), do: false

  defp report_due?(%Monitor{} = monitor, now, last_triggered_at) do
    frequency =
      monitor.report_settings
      |> case do
        nil -> :weekly
        settings -> Map.get(settings, :frequency, :weekly)
      end

    boundary_reached? = report_boundary_reached?(frequency, now)
    period_start = report_period_start(frequency, now)

    cond do
      boundary_reached? && is_nil(last_triggered_at) ->
        true

      boundary_reached? && DateTime.compare(last_triggered_at, period_start) == :lt ->
        true

      true ->
        false
    end
  end

  defp alert_due?(%Monitor{} = monitor, now, last_triggered_at) do
    case granularity_minutes(monitor.alert_granularity) do
      {:ok, minutes} when minutes > 0 ->
        bucket_end = truncate_to_minute(now)
        boundary? = boundary_hit?(bucket_end, minutes)

        cond do
          not boundary? ->
            false

          is_nil(last_triggered_at) ->
            true

          DateTime.compare(last_triggered_at, bucket_end) == :lt ->
            true

          true ->
            false
        end

      _ ->
        false
    end
  end

  defp report_boundary_reached?(:hourly, now),
    do: now.minute == 0

  defp report_boundary_reached?(:daily, now),
    do: now.hour == 0 and now.minute == 0

  defp report_boundary_reached?(:weekly, now) do
    {:ok, date} = Date.new(now.year, now.month, now.day)
    Date.day_of_week(date) == 1 and now.hour == 0 and now.minute == 0
  end

  defp report_boundary_reached?(:monthly, now),
    do: now.day == 1 and now.hour == 0 and now.minute == 0

  defp report_boundary_reached?(_other, now),
    do: now.hour == 0 and now.minute == 0

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
