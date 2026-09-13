defmodule Trifle.Traces.Activity do
  @moduledoc "Trace path/state activity from Stats counters; parent rollups are never stored."

  alias Trifle.Stats.Source
  alias Trifle.Traces.Reader

  @states ~w(success warning error running)

  def fetch(membership, id, from, to, granularity, opts \\ []) do
    fetcher = Keyword.get(opts, :fetch_series, &Source.fetch_series/6)

    with {:ok, source} <- Reader.source(membership, id) do
      fetch = fn key ->
        fetcher.(source, key, from, to, granularity,
          transponders: :none,
          progressive_concurrency: 1
        )
      end

      with {:ok, catalog} <- read(fetch, "__system__key__"),
           {:ok, metrics} <- fetch_metrics(catalog_keys(catalog), fetch) do
        {:ok, %{catalog: catalog, metrics: metrics}}
      end
    end
  rescue
    _ -> {:error, :storage_unavailable}
  end

  def build(input, path \\ nil, state \\ nil) do
    input = input || %{}
    catalog = raw(input[:catalog])
    metrics = input[:metrics] || %{}
    keys = (catalog_keys(catalog) ++ Map.keys(metrics)) |> Enum.uniq() |> Enum.sort()
    times = Enum.map(catalog[:at] || [], &timestamp/1)
    catalog_buckets = buckets(catalog)

    counts =
      keys
      |> Enum.filter(&matches?(&1, path))
      |> Map.new(fn key ->
        metric_buckets = buckets(metrics[key])

        values =
          Enum.map(times, fn at ->
            values = metric_buckets[at] || %{}
            states = values["states"] || %{}
            known = Map.new(@states, &{&1, numeric(states[&1])})
            total = numeric(values["count"] || get_in(catalog_buckets, [at, "keys", key]))

            other =
              states |> Map.drop(@states) |> Map.values() |> Enum.map(&numeric/1) |> Enum.sum()

            # Old counters without states remain visible, but never masquerade as success.
            unknown = max(other, total - Enum.sum(Map.values(known)))
            {at, Map.put(known, "unclassified", max(unknown, 0))}
          end)

        {key, values}
      end)

    timeline =
      for status <- @states ++ ["unclassified"],
          state in [nil, "", status],
          key <- keys,
          Map.has_key?(counts, key),
          data = Enum.map(counts[key], fn {at, values} -> [at, values[status]] end),
          Enum.any?(data, fn [_, value] -> value > 0 end) do
        %{
          id: Jason.encode!([key, status]),
          name: key <> " · " <> String.capitalize(status),
          legend_name: key,
          path: key,
          state: status,
          data: data
        }
      end

    %{
      series: timeline ++ duration_series(metrics, Map.keys(counts), times, state),
      paths: paths(keys),
      total:
        Enum.reduce(timeline, 0, fn item, sum ->
          sum + Enum.reduce(item.data, 0, fn [_, value], acc -> acc + value end)
        end)
    }
  end

  defp duration_series(metrics, keys, times, state) do
    samples =
      Enum.map(Enum.sort(keys), fn key ->
        values = buckets(metrics[key])

        data =
          Enum.map(times, fn at ->
            duration = get_in(values, [at, "duration"]) || %{}

            sample =
              if state in [nil, ""],
                do: duration,
                else: get_in(duration, ["states", state]) || %{}

            sum = sample["sum"]
            count = numeric(sample["count"])

            if (is_number(sum) or is_struct(sum, Decimal)) and count > 0,
              do: [at, numeric(sum), count],
              else: [at, 0, 0]
          end)

        %{name: key, data: data}
      end)

    totals =
      Enum.reduce(samples, Map.new(times, &{&1, {0, 0}}), fn sample, totals ->
        Enum.reduce(sample.data, totals, fn [at, value, size], acc ->
          Map.update!(acc, at, fn {sum, count} -> {sum + value, count + size} end)
        end)
      end)

    data =
      Enum.map(times, fn at ->
        {sum, count} = totals[at]
        [at, if(count > 0, do: sum / count, else: nil)]
      end)

    if Enum.any?(data, fn [_, value] -> is_number(value) end) do
      [
        %{
          id: "trace-average-duration",
          name: "Average duration",
          chart_type: "line",
          y_axis: "secondary",
          stacked: false,
          unit: "ms",
          color: "#8b5cf6",
          average_samples: samples,
          data: data
        }
      ]
    else
      []
    end
  end

  defp fetch_metrics(keys, fetch) do
    keys
    |> Task.async_stream(fn key -> {key, read(fetch, key)} end,
      max_concurrency: 4,
      timeout: 60_000,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.reduce_while({:ok, %{}}, fn
      {:ok, {key, {:ok, series}}}, {:ok, metrics} ->
        {:cont, {:ok, Map.put(metrics, key, series)}}

      _, _ ->
        {:halt, {:error, :storage_unavailable}}
    end)
  end

  defp read(fetch, key) do
    case fetch.(key) do
      {:ok, %{series: series}} -> {:ok, series}
      _ -> {:error, :storage_unavailable}
    end
  rescue
    _ -> {:error, :storage_unavailable}
  catch
    _, _ -> {:error, :storage_unavailable}
  end

  defp catalog_keys(catalog) do
    (raw(catalog)[:values] || [])
    |> Enum.flat_map(&Map.keys((&1 || %{})["keys"] || %{}))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp raw(%Trifle.Stats.Series{series: series}), do: series
  defp raw(series), do: series || %{}

  defp buckets(series) do
    series = raw(series)
    times = series[:at] || []
    values = series[:values] || []

    times
    |> Enum.zip(values ++ List.duplicate(%{}, max(length(times) - length(values), 0)))
    |> Map.new(fn {at, value} -> {timestamp(at), value || %{}} end)
  end

  def matches?(_key, path) when path in [nil, ""], do: true
  def matches?(key, path), do: key == path or String.starts_with?(key, path <> "/")

  def paths(keys) do
    keys
    |> Enum.flat_map(fn key -> key |> String.split("/") |> Enum.scan(&(&2 <> "/" <> &1)) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp timestamp(%DateTime{} = at), do: DateTime.to_unix(at, :millisecond)
  defp timestamp(%NaiveDateTime{} = at), do: at |> DateTime.from_naive!("Etc/UTC") |> timestamp()
  defp timestamp(at), do: at
  defp numeric(%Decimal{} = value), do: Decimal.to_float(value)
  defp numeric(value) when is_number(value), do: value
  defp numeric(_), do: 0
end
