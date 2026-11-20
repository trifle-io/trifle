defmodule Trifle.Traces.Overview do
  @moduledoc "Per-job summaries projected from the trace activity Stats input."
  alias Trifle.Traces.Activity
  alias Trifle.Stats.MeasurementSummary

  @sorts ~w(name count success duration lines)
  def row_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {rows, ""} -> row_count(rows)
      _ -> 3
    end
  end

  def row_count(value) when is_integer(value) and value in 1..100, do: value
  def row_count(_), do: 3

  def controls(params, preferences \\ %{}) do
    rows = row_count(preferences[:rows])
    columns = if preferences[:columns] in [1, 2, 3, 4, 6], do: preferences[:columns], else: 3

    %{
      sort: if(params["sort"] in @sorts, do: params["sort"], else: "count"),
      direction: if(params["direction"] == "asc", do: "asc", else: "desc"),
      row_count: rows,
      columns: columns,
      size: rows * columns,
      page: positive_integer(params["page"])
    }
  end

  def build(input, path, state, params, preferences \\ %{}) do
    activity = Activity.build(input, path)
    page = input |> prepare(path, state, activity) |> paginate(params, preferences)
    %{page | rows: Enum.map(page.rows, &expand(&1, input, state, activity))}
  end

  def prepare(input, path, state, activity) do
    metrics = (input || %{})[:metrics] || %{}
    all_series = state_series(activity) |> Enum.group_by(& &1.path)

    matching_paths(input, path, state, activity)
    |> Enum.map(fn key ->
      counts = Map.get(all_series, key, [])
      timeline = Enum.filter(counts, &(state in [nil, "", &1.state]))

      total =
        timeline |> Enum.flat_map(& &1.data) |> Enum.reduce(0, fn [_, n], sum -> sum + n end)

      buckets = metric_buckets(metrics[key])

      success_rate =
        counts
        |> Enum.reduce(%{}, fn series, buckets ->
          Enum.reduce(series.data, buckets, fn [at, count], acc ->
            successes = if series.state == "success", do: count, else: 0
            Map.update(acc, at, {successes, count}, fn {s, c} -> {s + successes, c + count} end)
          end)
        end)
        |> Enum.map(fn {at, {successes, count}} -> {at, successes * 100, count} end)
        |> MeasurementSummary.summarize()

      duration =
        Enum.map(buckets, fn {at, values} ->
          sample = values["duration"] || %{}

          sample =
            if state in [nil, ""], do: sample, else: get_in(sample, ["states", state]) || %{}

          {at, sample["sum"], sample["count"]}
        end)
        |> MeasurementSummary.summarize()

      lines =
        if state in [nil, ""] do
          Enum.map(buckets, fn {at, values} ->
            {at, get_in(values, ["entries", "count"]), values["count"]}
          end)
          |> MeasurementSummary.summarize()
        else
          MeasurementSummary.summarize([])
        end

      %{
        path: key,
        count: total,
        success: success_rate.average,
        success_rate: success_rate,
        state_distribution: state_distribution(counts),
        duration: duration,
        lines: lines,
        series: timeline
      }
    end)
  end

  def paginate(rows, params, preferences \\ %{}) do
    controls = controls(params, preferences)

    rows =
      rows
      |> Enum.sort(fn a, b ->
        av = sort_value(a, controls.sort)
        bv = sort_value(b, controls.sort)

        cond do
          av == bv -> a.path <= b.path
          is_nil(av) -> false
          is_nil(bv) -> true
          controls.direction == "asc" -> av < bv
          true -> av > bv
        end
      end)

    page(rows, length(rows), controls) |> Map.put(:collapsed, false)
  end

  def collapsed(input, path, state, params, activity, preferences \\ %{}) do
    page([], length(matching_paths(input, path, state, activity)), controls(params, preferences))
    |> Map.put(:collapsed, true)
  end

  def expand(row, input, state, activity) do
    counts = Enum.filter(state_series(activity), &(&1.path == row.path))
    buckets = metric_buckets(get_in(input || %{}, [:metrics, row.path]))
    Map.put(row, :points, timeline_points(counts, buckets, state))
  end

  defp matching_paths(input, path, state, activity) do
    metrics = (input || %{})[:metrics] || %{}
    series = state_series(activity) |> Enum.filter(&(state in [nil, "", &1.state]))
    paths = MapSet.new(series, & &1.path)

    Enum.filter(activity.paths, fn key ->
      Activity.matches?(key, path) &&
        if(state in [nil, ""],
          do: Map.has_key?(metrics, key) || MapSet.member?(paths, key),
          else: MapSet.member?(paths, key)
        )
    end)
  end

  defp state_series(activity), do: Enum.filter(activity.series, &Map.has_key?(&1, :state))

  defp page(rows, total, controls) do
    pages = max(1, ceil(total / controls.size))
    page = min(controls.page, pages)

    Map.merge(controls, %{
      rows: Enum.slice(rows, (page - 1) * controls.size, controls.size),
      total: total,
      pages: pages,
      page: page
    })
  end

  defp sort_value(row, "name"), do: row.path
  defp sort_value(row, "count"), do: row.count
  defp sort_value(row, "success"), do: row.success
  defp sort_value(row, "duration"), do: row.duration.average
  defp sort_value(row, "lines"), do: row.lines.average

  defp state_distribution(series) do
    counts =
      Enum.map(series, fn item ->
        %{state: item.state, count: Enum.reduce(item.data, 0, fn [_, n], sum -> sum + n end)}
      end)

    total = Enum.reduce(counts, 0, &(&1.count + &2))

    for item <- counts, item.count > 0, total > 0 do
      Map.put(item, :percentage, item.count / total * 100)
    end
  end

  defp timeline_points(series, buckets, state) do
    values = Map.new(buckets, fn {at, value} -> {timestamp(at), value || %{}} end)
    states = Map.new(series, &{&1.state, Map.new(&1.data, fn [at, count] -> {at, count} end)})

    (Map.keys(values) ++ Enum.flat_map(series, &Enum.map(&1.data, fn [at, _] -> at end)))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn at ->
      value = Map.get(values, at, %{})
      counts = Map.new(states, fn {name, samples} -> {name, Map.get(samples, at, 0)} end)
      total = numeric(value["count"]) || Enum.sum(Map.values(counts))
      duration = value["duration"] || %{}

      duration =
        if state in [nil, ""], do: duration, else: get_in(duration, ["states", state]) || %{}

      duration_sum = numeric(duration["sum"])
      duration_count = numeric(duration["count"])
      lines_sum = numeric(get_in(value, ["entries", "count"]))

      %{
        at: at,
        states: counts,
        total_count: total,
        count: if(state in [nil, ""], do: total, else: Map.get(counts, state, 0)),
        success: average(Map.get(counts, "success", 0) * 100, total),
        duration_sum: duration_sum,
        duration_count: duration_count,
        duration: average(duration_sum, duration_count),
        lines_sum: lines_sum,
        lines: if(state in [nil, ""], do: average(lines_sum, total), else: nil)
      }
    end)
  end

  defp average(sum, count) when is_number(sum) and is_number(count) and count > 0, do: sum / count
  defp average(_, _), do: nil
  defp numeric(%Decimal{} = value), do: Decimal.to_float(value)
  defp numeric(value) when is_number(value), do: value
  defp numeric(_), do: nil
  defp timestamp(%DateTime{} = at), do: DateTime.to_unix(at, :millisecond)
  defp timestamp(%NaiveDateTime{} = at), do: at |> DateTime.from_naive!("Etc/UTC") |> timestamp()
  defp timestamp(at), do: at

  defp metric_buckets(%Trifle.Stats.Series{series: series}), do: metric_buckets(series)

  defp metric_buckets(%{at: times, values: values}),
    do: Enum.zip(times, values) |> Enum.sort_by(&elem(&1, 0))

  defp metric_buckets(_), do: []

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp positive_integer(_), do: 1
end
