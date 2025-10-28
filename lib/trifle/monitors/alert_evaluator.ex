defmodule Trifle.Monitors.AlertEvaluator do
  @moduledoc """
  Evaluates monitor alerts against a `Trifle.Stats.Series` dataset and
  returns structured metadata describing triggered breaches and visual overlays.
  """

  alias Decimal
  alias Trifle.Monitors.Alert
  alias Trifle.Stats.Series

  @type overlay_segment :: %{
          from_iso: String.t(),
          to_iso: String.t(),
          from_ts: integer(),
          to_ts: integer(),
          start_index: non_neg_integer(),
          end_index: non_neg_integer(),
          severity: atom(),
          label: String.t() | nil,
          color: String.t() | nil,
          direction: atom() | nil
        }

  @type overlay_point :: %{
          at_iso: String.t(),
          ts: integer(),
          index: non_neg_integer(),
          value: float(),
          label: String.t() | nil,
          color: String.t() | nil,
          severity: atom()
        }

  @type overlay_line :: %{
          value: float(),
          label: String.t() | nil,
          color: String.t() | nil,
          direction: atom() | nil
        }

  @type overlay_band :: %{
          min: float(),
          max: float(),
          label: String.t() | nil,
          color: String.t() | nil
        }

  defmodule Result do
    @moduledoc false
    defstruct [
      :alert_id,
      :strategy,
      :path,
      :triggered?,
      :window,
      :latest_point,
      :summary,
      segments: [],
      points: [],
      reference_lines: [],
      bands: [],
      trigger_indexes: MapSet.new(),
      meta: %{}
    ]
  end

  @type result :: %Result{}

  @type evaluation_error ::
          {:error, :missing_path}
          | {:error, :no_data}
          | {:error, :invalid_parameters}

  @threshold_line_color "#f87171"
  @threshold_segment_color "rgba(248,113,113,0.22)"
  @range_band_color "rgba(16,185,129,0.08)"
  @range_line_color "#0f766e"
  @hampel_point_color "#f97316"
  @cusum_positive_color "rgba(250,204,21,0.28)"
  @cusum_negative_color "rgba(59,130,246,0.28)"
  @cusum_line_color "#facc15"

  @doc """
  Evaluates the given `alert` against the provided timeseries `series`.

  Returns `{:ok, %Result{}}` when evaluation succeeds, or `{:error, reason}` otherwise.
  """
  @spec evaluate(Alert.t(), Series.t(), String.t() | nil, keyword()) ::
          {:ok, result()} | evaluation_error
  def evaluate(%Alert{} = alert, %Series{} = series, path, opts \\ []) do
    with {:ok, resolved_path, points} <- timeline_points(series, path),
         false <- Enum.empty?(points) do
      exclude_recent? = Keyword.get(opts, :exclude_recent, true)
      effective_points = maybe_trim_recent(points, exclude_recent?)

      window =
        opts
        |> Keyword.get(:window)
        |> normalize_window(alert)

      latest_point = List.last(effective_points) || List.last(points)

      case alert.analysis_strategy || :threshold do
        :threshold ->
          evaluate_threshold(alert, resolved_path, effective_points, window)

        :range ->
          evaluate_range(alert, resolved_path, effective_points, window)

        :hampel ->
          evaluate_hampel(alert, resolved_path, effective_points, window)

        :cusum ->
          evaluate_cusum(alert, resolved_path, effective_points, window)

        unsupported ->
          {:error, {:unsupported_strategy, unsupported}}
      end
      |> case do
        {:ok, %Result{} = result} ->
          {:ok, %{result | latest_point: latest_point}}

        other ->
          other
      end
    else
      true -> {:error, :no_data}
      {:error, _} = error -> error
    end
  end

  defp maybe_trim_recent(points, false), do: points

  defp maybe_trim_recent(points, true) do
    Enum.drop(points, -1)
  end

  @doc """
  Builds a lightweight overlay map for the front-end chart renderer based on the evaluation result.
  """
  @spec overlay(result()) :: map()
  def overlay(%Result{} = result) do
    %{
      alert_id: result.alert_id && to_string(result.alert_id),
      strategy: result.strategy,
      triggered: result.triggered?,
      summary: result.summary,
      segments:
        Enum.map(
          result.segments,
          &Map.take(&1, [
            :from_iso,
            :to_iso,
            :from_ts,
            :to_ts,
            :severity,
            :label,
            :color,
            :direction
          ])
        ),
      points:
        Enum.map(result.points, fn point ->
          Map.take(point, [:at_iso, :ts, :index, :value, :label, :color, :severity])
        end),
      reference_lines:
        Enum.map(result.reference_lines, fn line ->
          Map.take(line, [:value, :label, :color, :direction])
        end),
      bands:
        Enum.map(result.bands, fn band ->
          Map.take(band, [:min, :max, :label, :color])
        end),
      meta: %{
        window: result.window
      }
    }
  end

  # -- Threshold -------------------------------------------------------------

  defp evaluate_threshold(%Alert{} = alert, path, points, window) do
    settings = alert.settings || %{}
    direction = settings.threshold_direction || :above
    threshold_value = to_float(settings.threshold_value)

    cond do
      is_nil(threshold_value) ->
        {:error, :invalid_parameters}

      true ->
        condition =
          case direction do
            :below -> fn %{value: value} -> is_number(value) && value <= threshold_value end
            _ -> fn %{value: value} -> is_number(value) && value >= threshold_value end
          end

        {segments, indexes} =
          gather_segments(points, condition,
            severity: :breach,
            label: threshold_label(direction, threshold_value),
            color: @threshold_segment_color,
            direction: direction
          )

        triggered? = window_triggered?(indexes, length(points), window)

        summary =
          threshold_summary(
            List.last(points),
            threshold_value,
            direction,
            triggered?
          )

        result =
          %Result{
            alert_id: alert.id,
            strategy: :threshold,
            path: path,
            window: window,
            triggered?: triggered?,
            segments: segments,
            reference_lines: [
              %{
                value: threshold_value,
                label: threshold_label(direction, threshold_value),
                color: @threshold_line_color,
                direction: direction
              }
            ],
            trigger_indexes: indexes,
            summary: summary,
            meta: %{
              threshold: threshold_value,
              direction: direction
            }
          }

        {:ok, result}
    end
  end

  defp threshold_label(:below, value), do: "𝑥 ≤ #{format_number(value)}"
  defp threshold_label(_direction, value), do: "𝑥 ≥ #{format_number(value)}"

  defp threshold_summary(nil, threshold, _direction, _triggered?) do
    "Monitor checks against threshold #{format_number(threshold)}."
  end

  defp threshold_summary(%{value: value} = point, threshold, direction, triggered?) do
    timestamp =
      case point do
        %{at: %DateTime{} = at} -> " at #{DateTime.to_iso8601(at)}"
        _ -> ""
      end

    comparator = if direction == :below, do: "≤", else: "≥"

    base =
      "Latest reading 𝑥=#{format_number(value)}#{timestamp}; threshold demands 𝑥 #{comparator} #{format_number(threshold)}."

    if triggered?,
      do: base <> " Threshold breached in the latest window.",
      else: base <> " Threshold not breached recently."
  end

  # -- Range -----------------------------------------------------------------

  defp evaluate_range(%Alert{} = alert, path, points, window) do
    settings = alert.settings || %{}
    min_value = to_float(settings.range_min_value)
    max_value = to_float(settings.range_max_value)

    cond do
      is_nil(min_value) or is_nil(max_value) ->
        {:error, :invalid_parameters}

      max_value <= min_value ->
        {:error, :invalid_parameters}

      true ->
        condition = fn %{value: value} ->
          is_number(value) && (value < min_value or value > max_value)
        end

        target_range_label = "#{format_number(min_value)} ≤ 𝑥 ≤ #{format_number(max_value)}"

        {segments, indexes} =
          gather_segments(points, condition,
            severity: :breach,
            label: "Outside #{target_range_label}",
            color: @threshold_segment_color
          )

        triggered? = window_triggered?(indexes, length(points), window)

        summary = range_summary(List.last(points), min_value, max_value, triggered?)

        result =
          %Result{
            alert_id: alert.id,
            strategy: :range,
            path: path,
            window: window,
            triggered?: triggered?,
            segments: segments,
            reference_lines: [
              %{
                value: min_value,
                label: "Min #{format_number(min_value)}",
                color: @range_line_color,
                direction: :lower
              },
              %{
                value: max_value,
                label: "Max #{format_number(max_value)}",
                color: @range_line_color,
                direction: :upper
              }
            ],
            bands: [
              %{min: min_value, max: max_value, label: "Target range", color: @range_band_color}
            ],
            trigger_indexes: indexes,
            summary: summary,
            meta: %{min: min_value, max: max_value}
          }

        {:ok, result}
    end
  end

  defp range_summary(nil, min_value, max_value, _triggered?) do
    "Monitor tracks for values outside #{format_number(min_value)} ≤ 𝑥 ≤ #{format_number(max_value)}."
  end

  defp range_summary(%{value: value} = point, min_value, max_value, triggered?) do
    timestamp =
      case point do
        %{at: %DateTime{} = at} -> " at #{DateTime.to_iso8601(at)}"
        _ -> ""
      end

    target_range = "#{format_number(min_value)} ≤ 𝑥 ≤ #{format_number(max_value)}"

    base =
      "Latest reading 𝑥=#{format_number(value)}#{timestamp}; target window #{target_range}."

    if triggered?,
      do: base <> " Range breach detected in the latest window.",
      else: base <> " No recent range breach."
  end

  # -- Hampel ----------------------------------------------------------------

  defp evaluate_hampel(%Alert{} = alert, path, points, window) do
    settings = alert.settings || %{}
    window_size = sanitize_window_size(settings.hampel_window_size || window)
    k = settings.hampel_k || 3.0
    mad_floor = max(settings.hampel_mad_floor || 0.1, 1.0e-9)

    if length(points) < window_size do
      {:ok,
       %Result{
         alert_id: alert.id,
         strategy: :hampel,
         path: path,
         window: window_size,
         triggered?: false,
         summary:
           "Not enough data to evaluate Hampel outliers; requires window 𝑤=#{window_size} samples."
       }}
    else
      {outlier_indexes, point_markers} = detect_hampel(points, window_size, k, mad_floor)
      triggered? = window_triggered?(outlier_indexes, length(points), window_size)

      summary =
        hampel_summary(List.last(points), triggered?, window_size, k, mad_floor)

      result =
        %Result{
          alert_id: alert.id,
          strategy: :hampel,
          path: path,
          window: window_size,
          triggered?: triggered?,
          points: point_markers,
          trigger_indexes: outlier_indexes,
          summary: summary,
          meta: %{window_size: window_size, k: k, mad_floor: mad_floor}
        }

      {:ok, result}
    end
  end

  defp detect_hampel(points, window_size, k, mad_floor) do
    values = Enum.map(points, & &1.value)

    Enum.reduce(Enum.with_index(points), {MapSet.new(), []}, fn {point, idx},
                                                                {index_acc, point_acc} ->
      value = point.value

      cond do
        not is_number(value) ->
          {index_acc, point_acc}

        true ->
          window_values =
            values
            |> Enum.slice(max(idx - window_size + 1, 0)..idx)
            |> Enum.filter(&is_number/1)

          if length(window_values) < max(3, div(window_size, 2)) do
            {index_acc, point_acc}
          else
            median = median(window_values)
            mad = mad(window_values, median)
            scale = max(mad, mad_floor)
            deviation = abs(value - median)

            cond do
              scale == 0.0 ->
                {index_acc, point_acc}

              true ->
                score = deviation / scale

                if score > k do
                  index_acc = MapSet.put(index_acc, idx)

                  marker =
                    %{
                      at_iso: point.at_iso,
                      ts: point.ts,
                      index: idx,
                      value: value,
                      label: "Outlier (score #{format_number(score)})",
                      color: @hampel_point_color,
                      severity: :outlier
                    }

                  {index_acc, [marker | point_acc]}
                else
                  {index_acc, point_acc}
                end
            end
          end
      end
    end)
    |> then(fn {indexes, markers} -> {indexes, Enum.reverse(markers)} end)
  end

  defp median(values) do
    sorted = Enum.sort(values)
    len = length(sorted)
    mid = div(len, 2)

    if rem(len, 2) == 1 do
      Enum.at(sorted, mid)
    else
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    end
  end

  defp mad(values, median) do
    values
    |> Enum.map(&abs(&1 - median))
    |> median()
  end

  defp hampel_summary(nil, _triggered?, window_size, k, mad_floor) do
    "Hampel detector using window 𝑤=#{window_size}, threshold 𝑘=#{format_number(k)}, MAD floor 𝑚=#{format_number(mad_floor)}."
  end

  defp hampel_summary(%{value: value} = point, triggered?, window_size, k, mad_floor) do
    timestamp =
      case point do
        %{at: %DateTime{} = at} -> " at #{DateTime.to_iso8601(at)}"
        _ -> ""
      end

    base =
      "Latest reading 𝑥=#{format_number(value)}#{timestamp}; Hampel window 𝑤=#{window_size}, 𝑘=#{format_number(k)}, 𝑚=#{format_number(mad_floor)}."

    if triggered?,
      do: base <> " Outlier detected in the latest window.",
      else: base <> " No recent outliers."
  end

  # -- CUSUM -----------------------------------------------------------------

  defp evaluate_cusum(%Alert{} = alert, path, points, window) do
    settings = alert.settings || %{}
    k = settings.cusum_k || 0.5
    h = settings.cusum_h || 5.0
    values = Enum.map(points, & &1.value)

    mean =
      values
      |> Enum.filter(&is_number/1)
      |> average()

    cond do
      mean == nil ->
        {:ok,
         %Result{
           alert_id: alert.id,
           strategy: :cusum,
           path: path,
           window: window,
           triggered?: false,
           summary: "CUSUM monitoring skipped due to missing numeric values.",
           meta: %{mean: mean, k: k, h: h}
         }}

      true ->
        {segments, indexes} = detect_cusum(points, mean, k, h)
        triggered? = window_triggered?(indexes, length(points), window)

        summary =
          cusum_summary(List.last(points), triggered?, mean, k, h)

        result =
          %Result{
            alert_id: alert.id,
            strategy: :cusum,
            path: path,
            window: window,
            triggered?: triggered?,
            segments: segments,
            trigger_indexes: indexes,
            summary: summary,
            meta: %{mean: mean, k: k, h: h}
          }

        {:ok, result}
    end
  end

  defp detect_cusum(points, mean, k, h) do
    Enum.with_index(points)
    |> Enum.reduce(
      %{pos: 0.0, neg: 0.0, pos_start: nil, neg_start: nil, segments: [], indexes: MapSet.new()},
      fn {point, idx}, acc ->
        value = point.value

        if not is_number(value) do
          acc
        else
          deviation = value - mean

          pos = max(0.0, acc.pos + deviation - k)
          neg = min(0.0, acc.neg + deviation + k)

          pos_start = if pos > 0.0 && is_nil(acc.pos_start), do: idx, else: acc.pos_start
          neg_start = if neg < 0.0 && is_nil(acc.neg_start), do: idx, else: acc.neg_start

          {segments, indexes, pos, pos_start} =
            if pos > h do
              segment =
                build_segment(points, pos_start || idx, idx,
                  severity: :shift,
                  label: "Positive shift",
                  color: @cusum_positive_color,
                  direction: :positive
                )

              indexes = MapSet.put(acc.indexes, idx)
              {[segment | acc.segments], indexes, 0.0, nil}
            else
              {acc.segments, acc.indexes, pos, pos_start}
            end

          {segments, indexes, neg, neg_start} =
            if abs(neg) > h do
              segment =
                build_segment(points, neg_start || idx, idx,
                  severity: :shift,
                  label: "Negative shift",
                  color: @cusum_negative_color,
                  direction: :negative
                )

              indexes = MapSet.put(indexes, idx)
              {[segment | segments], indexes, 0.0, nil}
            else
              {segments, indexes, neg, neg_start}
            end

          %{
            pos: pos,
            neg: neg,
            pos_start: pos_start,
            neg_start: neg_start,
            segments: segments,
            indexes: indexes
          }
        end
      end
    )
    |> then(fn acc ->
      segments =
        acc.segments
        |> Enum.reverse()
        |> Enum.map(&maybe_extend_segment(&1, points))

      {segments,
       acc.indexes
       |> MapSet.new(fn idx -> idx end)}
    end)
  end

  defp cusum_summary(nil, _triggered?, mean, k, h) do
    "CUSUM monitors shifts around mean μ=#{format_number(mean)} with allowance 𝑘=#{format_number(k)} and decision limit 𝐻=#{format_number(h)}."
  end

  defp cusum_summary(%{value: value} = point, triggered?, mean, k, h) do
    timestamp =
      case point do
        %{at: %DateTime{} = at} -> " at #{DateTime.to_iso8601(at)}"
        _ -> ""
      end

    base =
      "Latest reading 𝑥=#{format_number(value)}#{timestamp}; CUSUM baseline μ=#{format_number(mean)}, 𝑘=#{format_number(k)}, 𝐻=#{format_number(h)}."

    if triggered?,
      do: base <> " Level shift detected in the latest window.",
      else: base <> " No recent level shift detected."
  end

  # -- Shared helpers --------------------------------------------------------

  defp gather_segments(points, condition_fun, opts) do
    Enum.with_index(points)
    |> Enum.reduce({nil, [], MapSet.new()}, fn {point, idx}, {current, segments, indexes} ->
      if condition_fun.(point) do
        indexes = MapSet.put(indexes, idx)

        current =
          case current do
            nil -> %{start: idx, finish: idx}
            %{start: start} -> %{start: start, finish: idx}
          end

        {current, segments, indexes}
      else
        segments =
          case current do
            nil ->
              segments

            %{start: start, finish: finish} ->
              [build_segment(points, start, finish, opts) | segments]
          end

        {nil, segments, indexes}
      end
    end)
    |> then(fn {current, segments, indexes} ->
      segments =
        case current do
          nil ->
            segments

          %{start: start, finish: finish} ->
            [build_segment(points, start, finish, opts) | segments]
        end

      {Enum.reverse(segments), indexes}
    end)
  end

  defp build_segment(points, start_idx, end_idx, opts) do
    start_point = Enum.at(points, start_idx)
    end_point = Enum.at(points, end_idx)

    %{
      from_iso: start_point.at_iso,
      to_iso: end_point.at_iso,
      from_ts: start_point.ts,
      to_ts: end_point.ts,
      start_index: start_idx,
      end_index: end_idx,
      severity: Keyword.get(opts, :severity, :breach),
      label: Keyword.get(opts, :label),
      color: Keyword.get(opts, :color),
      direction: Keyword.get(opts, :direction)
    }
  end

  defp maybe_extend_segment(segment, points) do
    if segment.from_ts == segment.to_ts do
      next =
        points
        |> Enum.at(segment.end_index + 1)
        |> case do
          nil -> segment
          next_point -> %{segment | to_iso: next_point.at_iso, to_ts: next_point.ts}
        end
    else
      segment
    end
  end

  defp window_triggered?(%MapSet{} = indexes, total_points, window) do
    cond do
      total_points <= 0 ->
        false

      MapSet.size(indexes) == 0 ->
        false

      true ->
        start_idx = max(total_points - window, 0)
        Enum.any?(start_idx..(total_points - 1), fn idx -> MapSet.member?(indexes, idx) end)
    end
  end

  defp normalize_window(nil, %Alert{analysis_strategy: :hampel} = alert),
    do: sanitize_window_size((alert.settings && alert.settings.hampel_window_size) || 5)

  defp normalize_window(nil, %Alert{}), do: 1
  defp normalize_window(value, _alert) when is_integer(value) and value > 0, do: value
  defp normalize_window(_other, _alert), do: 1

  defp sanitize_window_size(value) when is_integer(value) and value >= 3, do: value
  defp sanitize_window_size(_), do: 5

  defp average([]), do: nil

  defp average(values) do
    cleaned = Enum.filter(values, &is_number/1)

    case cleaned do
      [] -> nil
      _ -> Enum.sum(cleaned) / length(cleaned)
    end
  end

  defp timeline_points(_series, path) when path in [nil, ""], do: {:error, :missing_path}

  defp timeline_points(%Series{} = series, path) do
    callback = fn at, value ->
      dt = normalize_datetime(at)

      %{
        at: dt,
        at_iso: dt && DateTime.to_iso8601(dt),
        ts: dt && DateTime.to_unix(dt, :millisecond),
        value: to_float(value)
      }
    end

    series
    |> Series.format_timeline(path, 1, callback)
    |> case do
      %{} = map when map_size(map) > 0 ->
        {resolved_path, values} =
          Enum.find(map, fn {key, _} -> key == path end) ||
            Enum.at(map, 0)

        points =
          values
          |> Enum.filter(& &1[:at_iso])

        {:ok, resolved_path, sort_points(points)}

      _ ->
        {:error, :no_data}
    end
  end

  defp sort_points(points) do
    Enum.sort_by(points, & &1.ts, &<=/2)
  end

  defp normalize_datetime(%DateTime{} = dt), do: dt

  defp normalize_datetime(%NaiveDateTime{} = naive) do
    DateTime.from_naive!(naive, "Etc/UTC")
  rescue
    _ -> nil
  end

  defp normalize_datetime(value) when is_integer(value) do
    millis? = abs(value) > 9_999_999_999
    unit = if millis?, do: :millisecond, else: :second
    DateTime.from_unix!(value, unit)
  rescue
    _ -> nil
  end

  defp normalize_datetime(_), do: nil

  defp to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp to_float(value) when is_integer(value), do: value * 1.0
  defp to_float(value) when is_float(value), do: value
  defp to_float(_), do: nil

  defp format_number(value) when is_float(value) do
    value
    |> Float.round(6)
    |> :erlang.float_to_binary(decimals: 6)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  defp format_number(value) when is_number(value), do: to_string(value)
  defp format_number(_), do: "—"
end
