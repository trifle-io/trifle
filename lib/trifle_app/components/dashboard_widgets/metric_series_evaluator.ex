defmodule TrifleApp.Components.DashboardWidgets.MetricSeriesEvaluator do
  @moduledoc false

  alias Decimal, as: D
  alias Trifle.Stats.Series
  alias Trifle.Stats.Transponder.ExpressionEngine
  alias TrifleApp.Components.DashboardWidgets.MetricSeries
  alias TrifleApp.Components.DashboardWidgets.Timeseries

  @single_binding :"__single_binding__"

  def resolve_timeline_rows(%Series{} = series_struct, widget) do
    rows = widget |> MetricSeries.normalize_widget() |> Map.get("series", [])
    available_paths = MetricSeries.available_paths(series_struct)

    Enum.reduce(Enum.with_index(rows), [], fn {row, index}, acc ->
      resolved =
        case MetricSeries.row_kind(row) do
          "expression" -> resolve_expression_row(acc, row, index)
          _ -> resolve_timeline_path_row(series_struct, row, index, available_paths)
        end

      acc ++ [resolved]
    end)
  end

  def resolve_category_rows(%Series{} = series_struct, widget, slices \\ 1) do
    rows = widget |> MetricSeries.normalize_widget() |> Map.get("series", [])
    available_paths = MetricSeries.available_paths(series_struct)

    Enum.reduce(Enum.with_index(rows), [], fn {row, index}, acc ->
      resolved =
        case MetricSeries.row_kind(row) do
          "expression" -> resolve_expression_row(acc, row, index)
          _ -> resolve_category_path_row(series_struct, row, index, slices, available_paths)
        end

      acc ++ [resolved]
    end)
  end

  def resolve_distribution_rows(
        %Series{} = series_struct,
        widget,
        mode,
        horizontal_labels,
        vertical_labels,
        slices
      ) do
    rows = widget |> MetricSeries.normalize_widget() |> Map.get("series", [])
    available_paths = MetricSeries.available_paths(series_struct)

    Enum.reduce(Enum.with_index(rows), [], fn {row, index}, acc ->
      resolved =
        case MetricSeries.row_kind(row) do
          "expression" ->
            resolve_expression_row(acc, row, index)

          _ ->
            resolve_distribution_path_row(
              series_struct,
              row,
              index,
              mode,
              horizontal_labels,
              vertical_labels,
              slices,
              available_paths
            )
        end

      acc ++ [resolved]
    end)
  end

  def resolve_kpi_scalar_rows(%Series{} = series_struct, widget, slices, function) do
    timeline_rows = resolve_timeline_rows(series_struct, widget)

    Enum.map(timeline_rows, fn resolved ->
      %{
        resolved
        | entries:
            Enum.into(resolved.entries, %{}, fn {binding_key, entry} ->
              samples = aggregate_sample_map(entry.samples, function, slices)
              {binding_key, %{entry | samples: samples}}
            end)
      }
    end)
  end

  def visible_rows(rows) when is_list(rows), do: Enum.filter(rows, &MetricSeries.visible?(&1.row))
  def visible_rows(_), do: []

  def timeline_series(rows) when is_list(rows) do
    rows
    |> visible_rows()
    |> Enum.flat_map(&timeline_entries_to_series/1)
  end

  def category_entries(rows) when is_list(rows) do
    rows
    |> visible_rows()
    |> Enum.flat_map(&category_entries_for_row/1)
  end

  def distribution_series(rows, mode) when is_list(rows) do
    rows
    |> visible_rows()
    |> Enum.flat_map(&distribution_entries_for_row(&1, mode))
  end

  def primary_kpi_entry(rows) when is_list(rows) do
    rows
    |> visible_rows()
    |> Enum.find_value(fn resolved ->
      resolved.entries
      |> sorted_entries()
      |> List.first()
      |> case do
        nil -> nil
        {_binding_key, entry} -> entry
      end
    end)
  end

  defp resolve_timeline_path_row(series_struct, row, index, available_paths) do
    expanded_path = MetricSeries.expand_path(MetricSeries.row_path(row), available_paths)

    timeline_map =
      Timeseries.format_timeline_map(series_struct, expanded_path, 1, fn at, value ->
        utc_dt =
          cond do
            match?(%DateTime{}, at) -> DateTime.shift_zone!(at, "Etc/UTC")
            match?(%NaiveDateTime{}, at) -> DateTime.from_naive!(at, "Etc/UTC")
            true -> nil
          end

        {utc_dt, normalize_number(value)}
      end)

    entries =
      timeline_map
      |> Enum.sort_by(fn {concrete_path, _data} -> to_string(concrete_path) end)
      |> Enum.reduce(%{}, fn {concrete_path, data}, acc ->
        key = binding_key(expanded_path, to_string(concrete_path))
        samples = timeline_points_to_samples(data)

        if map_size(samples) == 0 do
          acc
        else
          Map.put(acc, key, %{
            name: path_entry_name(row, expanded_path, to_string(concrete_path), key),
            source_path: to_string(concrete_path),
            samples: samples
          })
        end
      end)

    resolved_row(row, index, :timeline, entries)
  end

  defp resolve_category_path_row(series_struct, row, index, slices, _available_paths) do
    expanded_path = MetricSeries.row_path(row)

    entries =
      series_struct
      |> Series.format_category(expanded_path, slices)
      |> flatten_category_entries()
      |> Enum.sort_by(fn {concrete_path, _value} -> concrete_path end)
      |> Enum.reduce(%{}, fn {concrete_path, value}, acc ->
        key = binding_key(expanded_path, concrete_path)
        samples = %{value_key() => normalize_number(value)}

        if map_size(samples) == 0 do
          acc
        else
          Map.update(
            acc,
            key,
            %{
              name: path_entry_name(row, expanded_path, concrete_path, key),
              source_path: concrete_path,
              samples: samples
            },
            fn existing ->
              existing_value = Map.get(existing.samples, value_key(), 0.0) || 0.0
              new_value = Map.get(samples, value_key(), 0.0) || 0.0
              %{existing | samples: %{value_key() => existing_value + new_value}}
            end
          )
        end
      end)

    resolved_row(row, index, :category, entries)
  end

  defp resolve_distribution_path_row(
         series_struct,
         row,
         index,
         mode,
         horizontal_labels,
         vertical_labels,
         slices,
         available_paths
       ) do
    expanded_path = MetricSeries.row_path(row)

    entries =
      case mode do
        "3d" ->
          samples =
            distribution_point_samples(
              series_struct,
              expanded_path,
              horizontal_labels,
              vertical_labels
            )

          distribution_entries(expanded_path, row, index, samples)

        _ ->
          samples =
            series_struct
            |> distribution_bucket_samples(expanded_path, slices)
            |> fill_distribution_buckets(horizontal_labels)

          distribution_entries(expanded_path, row, index, samples)
      end

    shape = if mode == "3d", do: :distribution_points, else: :distribution_values
    resolved_row(row, index, shape, entries)
  end

  defp distribution_entries(expanded_path, row, _index, samples) do
    if map_size(samples) == 0 do
      %{}
    else
      %{
        @single_binding => %{
          name: path_entry_name(row, expanded_path, expanded_path, @single_binding),
          source_path: expanded_path,
          samples: samples
        }
      }
    end
  end

  defp resolve_expression_row(prior_rows, row, index) do
    prior_count = length(prior_rows)
    expression = MetricSeries.row_expression(row)
    shape = expression_shape(prior_rows)

    entries =
      with true <- prior_count > 0,
           false <- expression == "",
           {:ok, ast} <- ExpressionEngine.parse(expression, placeholder_paths(prior_count)) do
        vars = ExpressionEngine.allowed_vars(prior_count)
        keys = candidate_binding_keys(prior_rows)

        keys
        |> Enum.reduce(%{}, fn key, acc ->
          row_entries = Enum.map(prior_rows, &binding_entry(&1.entries, key))

          sample_keys =
            row_entries
            |> Enum.flat_map(fn
              nil -> []
              entry -> Map.keys(entry.samples)
            end)
            |> Enum.uniq()
            |> Enum.sort_by(&sample_sort_key/1)

          samples =
            Enum.reduce(sample_keys, %{}, fn sample_key, sample_acc ->
              env =
                vars
                |> Enum.zip(row_entries)
                |> Enum.into(%{}, fn {var, entry} ->
                  value =
                    case entry do
                      nil -> nil
                      %{samples: samples_map} -> Map.get(samples_map, sample_key)
                    end

                  {var, value}
                end)

              case ExpressionEngine.evaluate(ast, env) do
                {:ok, value} ->
                  Map.put(sample_acc, sample_key, normalize_number(value))

                _ ->
                  maybe_preserve_empty_timeline_sample(sample_acc, sample_key, shape)
              end
            end)

          if sample_map_has_values?(samples) do
            Map.put(acc, key, %{
              name: expression_entry_name(row, index, key),
              source_path: "__expression__.#{index}.#{binding_key_string(key)}",
              samples: samples
            })
          else
            acc
          end
        end)
      else
        _ -> %{}
      end

    resolved_row(row, index, shape, entries)
  end

  defp timeline_entries_to_series(resolved) do
    resolved.entries
    |> sorted_entries()
    |> Enum.with_index()
    |> Enum.map(fn {{_binding_key, entry}, emitted_index} ->
      %{
        name: entry.name,
        data:
          entry.samples
          |> Enum.sort_by(fn {at, _value} -> sample_sort_key(at) end)
          |> Enum.map(fn {at, value} ->
            timestamp =
              case at do
                %DateTime{} = dt -> DateTime.to_unix(dt, :millisecond)
                %NaiveDateTime{} = dt -> dt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:millisecond)
                _ -> at
              end

            [timestamp || 0, value]
          end),
        color: color_for_row(resolved.row, emitted_index),
        source_path: entry.source_path
      }
    end)
  end

  defp category_entries_for_row(resolved) do
    resolved.entries
    |> sorted_entries()
    |> Enum.with_index()
    |> Enum.map(fn {{_binding_key, entry}, emitted_index} ->
      %{
        name: entry.name,
        value: Map.get(entry.samples, value_key()),
        color: color_for_row(resolved.row, emitted_index),
        source_path: entry.source_path
      }
    end)
  end

  defp distribution_entries_for_row(resolved, mode) do
    resolved.entries
    |> sorted_entries()
    |> Enum.with_index()
    |> Enum.map(fn {{_binding_key, entry}, emitted_index} ->
      base = %{
        name: entry.name,
        path: entry.source_path,
        color: color_for_row(resolved.row, emitted_index)
      }

      case mode do
        "3d" ->
          points =
            entry.samples
            |> Enum.map(fn {{bucket_x, bucket_y}, value} ->
              %{bucket_x: bucket_x, bucket_y: bucket_y, value: value}
            end)
            |> Enum.sort_by(fn %{bucket_x: bucket_x, bucket_y: bucket_y} ->
              {sample_sort_key(bucket_x), sample_sort_key(bucket_y)}
            end)

          Map.put(base, :points, points)

        _ ->
          values =
            entry.samples
            |> Enum.map(fn {bucket, value} -> %{bucket: bucket, value: value} end)
            |> Enum.sort_by(fn %{bucket: bucket} -> sample_sort_key(bucket) end)

          Map.put(base, :values, values)
      end
    end)
  end

  defp aggregate_sample_map(samples, function, slices) when is_map(samples) do
    values =
      samples
      |> Enum.sort_by(fn {sample_key, _value} -> sample_sort_key(sample_key) end)
      |> Enum.map(fn {_sample_key, value} -> value end)

    aggregates =
      case slices do
        count when is_integer(count) and count > 1 -> slice_aggregate(values, count, function)
        _ -> [aggregate_values(values, function)]
      end

    aggregates
    |> Enum.with_index()
    |> Enum.into(%{}, fn {value, idx} -> {idx, value} end)
  end

  defp aggregate_sample_map(_, _function, _slices), do: %{}

  defp slice_aggregate(values, slices, function) do
    count = length(values)

    cond do
      count == 0 ->
        []

      slices <= 1 ->
        [aggregate_values(values, function)]

      true ->
        slice_size = div(count, slices)

        if slice_size <= 0 do
          [aggregate_values(values, function)]
        else
          start_index = count - slice_size * slices

          values
          |> Enum.drop(start_index)
          |> Enum.chunk_every(slice_size)
          |> Enum.map(&aggregate_values(&1, function))
        end
    end
  end

  defp aggregate_values(values, function) do
    numeric = values |> Enum.map(&normalize_number/1) |> Enum.reject(&is_nil/1)

    case {function, numeric} do
      {_, []} -> nil
      {"sum", list} -> Enum.sum(list)
      {"min", list} -> Enum.min(list)
      {"max", list} -> Enum.max(list)
      {_, list} -> Enum.sum(list) / max(length(list), 1)
    end
  end

  defp placeholder_paths(count), do: Enum.map(1..count, &Integer.to_string/1)

  defp resolved_row(row, index, shape, entries) do
    %{
      row: row,
      index: index,
      shape: shape,
      entries: entries
    }
  end

  defp candidate_binding_keys(prior_rows) do
    keys =
      prior_rows
      |> Enum.flat_map(fn resolved -> Map.keys(resolved.entries) end)
      |> Enum.uniq()

    multi_keys = Enum.reject(keys, &(&1 == @single_binding))

    cond do
      multi_keys != [] -> multi_keys
      keys != [] -> [@single_binding]
      true -> []
    end
  end

  defp binding_entry(entries, _key) when map_size(entries) == 0, do: nil

  defp binding_entry(entries, key) do
    cond do
      Map.has_key?(entries, key) ->
        Map.get(entries, key)

      map_size(entries) == 1 ->
        entries |> Map.values() |> List.first()

      true ->
        nil
    end
  end

  defp expression_shape([first | _rest]), do: first.shape
  defp expression_shape(_), do: :timeline

  defp maybe_preserve_empty_timeline_sample(samples, sample_key, :timeline) do
    Map.put(samples, sample_key, nil)
  end

  defp maybe_preserve_empty_timeline_sample(samples, _sample_key, _shape), do: samples

  defp sample_map_has_values?(samples) when is_map(samples) do
    Enum.any?(samples, fn {_sample_key, value} -> not is_nil(value) end)
  end

  defp sample_map_has_values?(_), do: false

  defp timeline_points_to_samples(points) when is_list(points) do
    Enum.reduce(points, %{}, fn
      [at, value], acc ->
        if is_nil(at) do
          acc
        else
          Map.put(acc, at, normalize_number(value))
        end

      {at, value}, acc ->
        if is_nil(at) do
          acc
        else
          Map.put(acc, at, normalize_number(value))
        end

      _other, acc ->
        acc
    end)
  end

  defp timeline_points_to_samples(_), do: %{}

  defp flatten_category_entries(formatted) when is_map(formatted) do
    flatten_category_entries_from_map(formatted)
  end

  defp flatten_category_entries(formatted) when is_list(formatted) do
    formatted
    |> Enum.flat_map(&flatten_category_entries/1)
  end

  defp flatten_category_entries(_), do: []

  defp flatten_category_entries_from_map(map, prefix \\ nil) do
    map
    |> Enum.flat_map(fn {key, value} ->
      key_str = key |> to_string() |> String.trim()
      full_key = if prefix in [nil, ""], do: key_str, else: prefix <> "." <> key_str

      cond do
        is_map(value) and not is_struct(value) ->
          flatten_category_entries_from_map(value, full_key)

        is_number(value) or match?(%D{}, value) ->
          [{full_key, normalize_number(value)}]

        true ->
          []
      end
    end)
  end

  defp distribution_bucket_samples(series_struct, path, slices) do
    stripped = strip_wildcard(path)

    series_struct
    |> Series.format_category(path, slices, fn key, value ->
      {bucket_label_for_path(key, stripped), value}
    end)
    |> reduce_bucket_maps()
  end

  defp distribution_point_samples(series_struct, path, horizontal_labels, vertical_labels) do
    clean_segments =
      path
      |> strip_wildcard()
      |> String.split(".")
      |> Enum.reject(&(&1 == ""))

    series_struct
    |> Map.get(:series, %{})
    |> Map.get(:values, [])
    |> Enum.reduce(%{}, fn data, acc ->
      case get_in(data, clean_segments) do
        %{} = map -> accumulate_distribution_points(map, acc, horizontal_labels, vertical_labels)
        _ -> acc
      end
    end)
  end

  defp accumulate_distribution_points(map, acc, horizontal_labels, vertical_labels)
       when is_map(map) do
    Enum.reduce(map, acc, fn {raw_x, raw_y_map}, matrix_acc ->
      x_bucket = normalize_bucket_key(raw_x, horizontal_labels)

      cond do
        is_nil(x_bucket) ->
          matrix_acc

        is_map(raw_y_map) ->
          Enum.reduce(raw_y_map, matrix_acc, fn {raw_y, value}, inner ->
            y_bucket = normalize_bucket_key(raw_y, vertical_labels)

            if is_nil(y_bucket) do
              inner
            else
              number = normalize_number(value)
              Map.update(inner, {x_bucket, y_bucket}, number, &(&1 + number))
            end
          end)

        is_number(raw_y_map) or match?(%D{}, raw_y_map) ->
          number = normalize_number(raw_y_map)
          Map.update(matrix_acc, {x_bucket, "total"}, number, &(&1 + number))

        true ->
          matrix_acc
      end
    end)
  end

  defp accumulate_distribution_points(_other, acc, _horizontal_labels, _vertical_labels), do: acc

  defp reduce_bucket_maps(formatted) when is_map(formatted),
    do: accumulate_bucket_map(formatted, %{})

  defp reduce_bucket_maps(formatted) when is_list(formatted) do
    Enum.reduce(formatted, %{}, fn map, acc -> accumulate_bucket_map(map, acc) end)
  end

  defp reduce_bucket_maps(_), do: %{}

  defp accumulate_bucket_map(map, acc) when is_map(map) do
    Enum.reduce(map, acc, fn {bucket, value}, inner_acc ->
      label = bucket |> to_string() |> String.trim()
      number = normalize_number(value)
      Map.update(inner_acc, label, number, &((&1 || 0.0) + (number || 0.0)))
    end)
  end

  defp accumulate_bucket_map(_, acc), do: acc

  defp fill_distribution_buckets(samples, labels) when is_map(samples) and is_list(labels) do
    Enum.reduce(labels, samples, fn label, acc ->
      Map.put_new(acc, label, 0.0)
    end)
  end

  defp fill_distribution_buckets(samples, _labels), do: samples

  defp normalize_bucket_key(value, valid_labels) do
    label = value |> to_string() |> String.trim()

    cond do
      label == "" -> nil
      valid_labels == [] -> label
      label in valid_labels -> label
      true -> label
    end
  end

  defp bucket_label_for_path(key, stripped_path) do
    key
    |> to_string()
    |> String.replace_prefix(stripped_path <> ".", "")
    |> String.split(".")
    |> List.last()
    |> case do
      nil -> key
      value -> value
    end
  end

  defp strip_wildcard(path) do
    path
    |> to_string()
    |> String.trim()
    |> String.trim_trailing(".*")
  end

  defp path_entry_name(row, pattern, concrete_path, binding_key) do
    label = MetricSeries.row_label(row)

    cond do
      label == "" and binding_key == @single_binding and concrete_path == pattern ->
        concrete_path

      label == "" ->
        concrete_path

      binding_key == @single_binding ->
        label

      true ->
        "#{label}: #{binding_label(binding_key, concrete_path)}"
    end
  end

  defp expression_entry_name(row, index, binding_key) do
    label = MetricSeries.row_label(row)

    cond do
      label == "" and binding_key == @single_binding ->
        MetricSeries.row_letter(index)

      label == "" ->
        binding_label(binding_key, MetricSeries.row_letter(index))

      binding_key == @single_binding ->
        label

      true ->
        "#{label}: #{binding_label(binding_key, label)}"
    end
  end

  defp binding_key(pattern, concrete_path) do
    pattern_regex = wildcard_regex(pattern)

    case Regex.run(pattern_regex, concrete_path, capture: :all_but_first) do
      nil ->
        if concrete_path == pattern, do: @single_binding, else: concrete_path

      [] ->
        if concrete_path == pattern, do: @single_binding, else: concrete_path

      captures ->
        {:captures, captures}
    end
  end

  defp wildcard_regex(pattern) do
    segments = String.split(pattern, ".", trim: true)

    parts =
      segments
      |> Enum.with_index()
      |> Enum.map(fn
        {"*", index} when index == length(segments) - 1 -> "(.+)"
        {"*", _index} -> "([^.]+)"
        {segment, _index} -> Regex.escape(segment)
      end)

    Regex.compile!("^" <> Enum.join(parts, "\\.") <> "$")
  end

  defp binding_label(@single_binding, fallback), do: fallback
  defp binding_label({:captures, captures}, _fallback), do: Enum.join(captures, " / ")
  defp binding_label(other, _fallback), do: to_string(other)

  defp binding_key_string(@single_binding), do: "single"
  defp binding_key_string({:captures, captures}), do: Enum.join(captures, "__")
  defp binding_key_string(other), do: other |> to_string() |> String.replace(".", "__")

  defp color_for_row(row, emitted_index) do
    row
    |> MetricSeries.row_color_selector()
    |> TrifleApp.Components.DashboardWidgets.Helpers.resolve_series_color(emitted_index)
  end

  defp normalize_number(%D{} = value), do: D.to_float(value)
  defp normalize_number(value) when is_number(value), do: value * 1.0
  defp normalize_number(_), do: nil

  defp value_key, do: :"__value__"

  defp sorted_entries(entries) do
    Enum.sort_by(entries, fn {_binding_key, entry} -> entry.name end)
  end

  defp sample_sort_key(%DateTime{} = dt), do: {:datetime, DateTime.to_unix(dt, :microsecond)}
  defp sample_sort_key(%NaiveDateTime{} = dt), do: {:naive_datetime, NaiveDateTime.to_iso8601(dt)}
  defp sample_sort_key({left, right}), do: {:tuple, sample_sort_key(left), sample_sort_key(right)}
  defp sample_sort_key(value) when is_integer(value), do: {:integer, value}
  defp sample_sort_key(value) when is_float(value), do: {:float, value}
  defp sample_sort_key(value), do: {:string, to_string(value)}
end
