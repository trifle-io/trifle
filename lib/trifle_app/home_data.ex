defmodule TrifleApp.HomeData do
  @moduledoc """
  Helpers for loading data displayed on the Home view.
  """

  alias Decimal
  alias Trifle.Monitors
  alias Trifle.Organizations
  alias Trifle.Organizations.OrganizationMembership
  alias Trifle.Stats.Series
  alias Trifle.Stats.Source

  @recent_limit 5
  @activity_window_seconds 86_400
  @preferred_granularities ["10m", "15m", "30m", "1h"]
  @default_granularity "1h"
  @default_fetch_opts [transponders: :none]

  def recent_dashboard_visits(user, membership, limit \\ @recent_limit) do
    Organizations.list_recent_dashboard_visits_for_membership(user, membership, limit)
  end

  def triggered_monitors(user, membership, opts \\ []) do
    Monitors.list_triggered_monitors_for_membership(user, membership, opts)
  end

  def source_activity(membership, opts \\ [])
  def source_activity(nil, _opts), do: []

  def source_activity(%OrganizationMembership{} = membership, opts) do
    membership
    |> Source.list_for_membership()
    |> Enum.map(&build_source_activity(&1, opts))
  end

  defp build_source_activity(source, opts) do
    now = timezone_now(source)
    from = DateTime.add(now, -@activity_window_seconds, :second)
    granularity = pick_granularity(Source.available_granularities(source))

    fetch_opts =
      @default_fetch_opts
      |> Keyword.merge(Keyword.get(opts, :fetch_opts, []))

    result =
      try do
        Source.fetch_series(
          source,
          "__system__key__",
          from,
          now,
          granularity,
          fetch_opts
        )
      rescue
        e -> {:error, {:exception, e}}
      end

    case result do
      {:ok, %{series: series}} ->
        timeline = timeline_from_series(series)

        %{
          source: source,
          granularity: granularity,
          timeline: timeline,
          total: total_from_timeline(timeline),
          last_event_at: last_event_timestamp(timeline)
        }

      {:error, reason} ->
        %{
          source: source,
          granularity: granularity,
          timeline: [],
          total: 0.0,
          last_event_at: nil,
          error: reason
        }
    end
  end

  defp pick_granularity(list) do
    available =
      list
      |> List.wrap()
      |> Enum.map(&normalize_granularity/1)
      |> Enum.reject(&is_nil/1)

    Enum.find(@preferred_granularities, &Enum.member?(available, &1)) ||
      List.first(available) || @default_granularity
  end

  defp normalize_granularity(nil), do: nil

  defp normalize_granularity(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
  rescue
    _ -> nil
  end

  defp timeline_from_series(%Series{} = series) do
    ats = Map.get(series.series, :at, []) || []
    values = Map.get(series.series, :values, []) || []

    ats
    |> Enum.zip(values)
    |> Enum.map(fn {at, value} ->
      %{at: at, value: normalize_number(extract_count(value))}
    end)
  end

  defp total_from_timeline(timeline) do
    timeline
    |> Enum.map(&(&1.value || 0))
    |> Enum.reduce(0.0, fn value, acc -> acc + normalize_number(value) end)
  end

  defp last_event_timestamp(timeline) do
    timeline
    |> Enum.reverse()
    |> Enum.find_value(fn %{at: at, value: value} ->
      if normalize_number(value) > 0, do: at, else: nil
    end)
  end

  defp extract_count(value) when is_map(value) do
    Map.get(value, "count") || Map.get(value, :count) || 0
  end

  defp extract_count(_), do: 0

  defp normalize_number(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp normalize_number(value) when is_number(value), do: value * 1.0
  defp normalize_number(_), do: 0.0

  defp timezone_now(source) do
    timezone = Source.time_zone(source) || "Etc/UTC"

    case DateTime.now(timezone) do
      {:ok, dt} -> dt
      _ -> DateTime.utc_now()
    end
  rescue
    _ -> DateTime.utc_now()
  end
end
