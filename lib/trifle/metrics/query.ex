defmodule Trifle.Metrics.Query do
  @moduledoc """
  Shared helpers for metric querying, aggregation, and formatting.
  """

  alias Decimal, as: D
  alias Trifle.Stats.Series
  alias Trifle.Stats.Tabler

  @aggregators %{
    "sum" => &Series.aggregate_sum/3,
    "mean" => &Series.aggregate_mean/3,
    "min" => &Series.aggregate_min/3,
    "max" => &Series.aggregate_max/3
  }
  @aggregator_names @aggregators |> Map.keys() |> Enum.sort()

  def aggregator_names, do: @aggregator_names

  def resolve_aggregator(nil) do
    {:error,
     %{
       status: "error",
       error: "Aggregator must be provided (options: #{Enum.join(@aggregator_names, ", ")})."
     }}
  end

  def resolve_aggregator(value) when is_atom(value), do: resolve_aggregator(Atom.to_string(value))

  def resolve_aggregator(value) when is_binary(value) do
    key =
      value
      |> String.trim()
      |> String.downcase()

    case Map.get(@aggregators, key) do
      nil ->
        {:error,
         %{
           status: "error",
           error: "Unsupported aggregator #{inspect(value)}.",
           allowed: @aggregator_names
         }}

      fun ->
        {:ok, {key, fun}}
    end
  end

  def resolve_aggregator(_other) do
    {:error,
     %{
       status: "error",
       error: "Aggregator must be a string."
     }}
  end

  def resolve_slices(args_or_value, default \\ 1) do
    value =
      case args_or_value do
        %{} = map -> Map.get(map, "slices") || Map.get(map, :slices)
        other -> other
      end

    case value do
      nil -> {:ok, default}
      other -> cast_positive_integer(other)
    end
  end

  def normalize_paths(value) do
    value
    |> List.wrap()
    |> Enum.flat_map(fn
      path when is_binary(path) ->
        path
        |> String.trim()
        |> case do
          "" -> []
          cleaned -> [cleaned]
        end

      other ->
        other
        |> to_string()
        |> String.trim()
        |> case do
          "" -> []
          cleaned -> [cleaned]
        end
    end)
  end

  def ensure_single_path([]), do: {:error, %{status: "error", error: "Value path required."}}
  def ensure_single_path([path]), do: {:ok, path}

  def ensure_single_path(paths) when is_list(paths) do
    {:error,
     %{
       status: "error",
       error: "Only a single value_path is supported for this tool.",
       provided_paths: paths
     }}
  end

  def ensure_no_wildcards(path) do
    if String.contains?(path, "*") do
      {:error,
       %{
         status: "error",
         error: "Wildcards are not supported in value_path #{inspect(path)}"
       }}
    else
      {:ok, path}
    end
  end

  def ensure_paths_exist(paths, available) do
    missing = Enum.reject(paths, &Enum.member?(available, &1))

    case missing do
      [] ->
        :ok

      _ ->
        {:error,
         %{
           status: "error",
           error: "Unknown path(s): #{Enum.join(missing, ", ")}",
           missing_paths: missing,
           available_paths: available
         }}
    end
  end

  def available_paths(%Series{} = series) do
    series.series[:values]
    |> List.wrap()
    |> Enum.flat_map(fn row ->
      row
      |> flatten_numeric_paths()
      |> Map.keys()
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def available_paths(_), do: []

  def summarise_series(%Series{} = series) do
    data_points = series.series[:values] || []
    flattened_rows = Enum.map(data_points, &flatten_numeric_paths/1)

    flattened_rows
    |> Enum.reduce(%{}, fn row, acc ->
      Enum.reduce(row, acc, fn {path, value}, inner ->
        Map.update(inner, path, [value], fn existing -> [value | existing] end)
      end)
    end)
    |> Enum.map(fn {path, values} ->
      numeric_values =
        values
        |> Enum.map(&convert_numeric/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.reverse()

      if numeric_values == [] do
        nil
      else
        %{
          path: path,
          count: length(numeric_values),
          sum: Enum.sum(numeric_values),
          average: safe_average(numeric_values),
          min: Enum.min(numeric_values),
          max: Enum.max(numeric_values),
          latest: List.last(numeric_values)
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def summarise_series(_), do: []

  def format_series_points(%Series{} = series) do
    timeline = series.series[:at] || []
    values = series.series[:values] || []

    timeline
    |> Enum.zip(values)
    |> Enum.map(fn {timestamp, data} ->
      %{
        at: timestamp |> ensure_datetime() |> DateTime.to_iso8601(),
        data: convert_data_map(data)
      }
    end)
  end

  def format_series_points(_), do: []

  def aggregate_series(%Series{} = series, aggregator_fun, path, slices)
      when is_function(aggregator_fun, 3) and is_integer(slices) and slices >= 1 do
    try do
      values =
        aggregator_fun.(series, path, slices)
        |> List.wrap()
        |> Enum.map(&convert_numeric/1)
        |> Enum.reject(&is_nil/1)

      {:ok, values}
    rescue
      error ->
        {:error,
         %{
           status: "error",
           error: "Aggregator failed for #{path}: #{Exception.message(error)}"
         }}
    end
  end

  def aggregate_series(_series, _fun, _path, _slices) do
    {:error,
     %{
       status: "error",
       error: "Series data unavailable."
     }}
  end

  def format_timeline_result(%Series{} = series, path, slices) do
    try do
      result = Series.format_timeline(series, path, slices)
      formatted = normalize_timeline_output(result)

      matched_paths =
        formatted
        |> extract_timeline_paths()
        |> case do
          [] -> [path]
          list -> list
        end

      {:ok, formatted, matched_paths}
    rescue
      error ->
        {:error,
         %{
           status: "error",
           error: "Timeline formatter failed for #{path}: #{Exception.message(error)}"
         }}
    end
  end

  def format_timeline_result(_series, _path, _slices) do
    {:error,
     %{
       status: "error",
       error: "Series data unavailable."
     }}
  end

  def format_category_result(%Series{} = series, path, slices) do
    try do
      result = Series.format_category(series, path, slices)
      formatted = normalize_category_output(result)

      matched_paths =
        formatted
        |> extract_category_paths()
        |> case do
          [] -> []
          list -> list
        end

      {:ok, formatted, matched_paths}
    rescue
      error ->
        {:error,
         %{
           status: "error",
           error: "Category formatter failed for #{path}: #{Exception.message(error)}"
         }}
    end
  end

  def format_category_result(_series, _path, _slices) do
    {:error,
     %{
       status: "error",
       error: "Series data unavailable."
     }}
  end

  def tabularize_series(series_struct, opts \\ [])

  def tabularize_series(%Series{} = series_struct, opts) do
    stats = Map.get(series_struct, :series)

    with %{at: at_list, paths: raw_paths, values: values} <- safe_tabulize(stats) do
      normalized_paths =
        raw_paths
        |> Enum.map(&to_string/1)
        |> Enum.uniq()
        |> Enum.sort()

      selected_paths =
        case Keyword.get(opts, :only_paths) do
          nil -> normalized_paths
          filter -> Enum.filter(normalized_paths, &Enum.member?(filter, &1))
        end

      if selected_paths == [] do
        nil
      else
        value_lookup =
          values
          |> Enum.reduce(%{}, fn {{path, at}, value}, acc ->
            Map.put(acc, {to_string(path), at}, convert_numeric(value))
          end)

        timestamps = Enum.reverse(at_list)

        rows =
          Enum.map(timestamps, fn timestamp ->
            iso = ensure_datetime(timestamp) |> DateTime.to_iso8601()

            [
              iso
              | Enum.map(selected_paths, fn path ->
                  Map.get(value_lookup, {path, timestamp})
                end)
            ]
          end)

        %{
          "columns" => ["at" | selected_paths],
          "rows" => rows
        }
      end
    else
      _ -> nil
    end
  end

  def tabularize_series(_other, _opts), do: nil

  def subset_table(nil, _paths), do: nil

  def subset_table(%{"columns" => columns, "rows" => rows}, paths) when is_list(paths) do
    subset_paths = Enum.filter(paths, &Enum.member?(columns, &1))

    if subset_paths == [] do
      nil
    else
      indices =
        ["at" | subset_paths]
        |> Enum.map(fn col -> Enum.find_index(columns, &(&1 == col)) end)

      if Enum.any?(indices, &is_nil/1) do
        nil
      else
        subset_rows =
          rows
          |> Enum.map(fn row -> Enum.map(indices, fn idx -> Enum.at(row, idx) end) end)

        %{
          "columns" => ["at" | subset_paths],
          "rows" => subset_rows
        }
      end
    end
  end

  def subset_table(_table, _paths), do: nil

  def maybe_put_primary_value(%{values: [value | _]} = payload, 1) when not is_nil(value) do
    Map.put(payload, :value, value)
  end

  def maybe_put_primary_value(payload, _), do: payload

  defp cast_positive_integer(value) when is_integer(value) and value >= 1, do: {:ok, value}

  defp cast_positive_integer(value) when is_float(value) and value >= 1 do
    if value == trunc(value) do
      {:ok, trunc(value)}
    else
      slices_error()
    end
  end

  defp cast_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int >= 1 -> {:ok, int}
      _ -> slices_error()
    end
  end

  defp cast_positive_integer(_), do: slices_error()

  defp slices_error do
    {:error,
     %{
       status: "error",
       error: "slices must be a positive integer."
     }}
  end

  defp extract_timeline_paths(result) when is_map(result) do
    result
    |> Map.keys()
    |> Enum.map(&to_string/1)
  end

  defp extract_timeline_paths(result) when is_list(result) do
    result
    |> Enum.flat_map(&extract_timeline_paths/1)
    |> Enum.uniq()
  end

  defp extract_timeline_paths(_), do: []

  defp extract_category_paths(result) when is_map(result) do
    result
    |> Map.keys()
    |> Enum.map(&to_string/1)
  end

  defp extract_category_paths(result) when is_list(result) do
    result
    |> Enum.flat_map(&extract_category_paths/1)
    |> Enum.uniq()
  end

  defp extract_category_paths(_), do: []

  defp safe_average(list) when length(list) == 0, do: 0.0
  defp safe_average(list), do: Enum.sum(list) / length(list)

  defp ensure_datetime(%DateTime{} = dt), do: dt

  defp ensure_datetime(%NaiveDateTime{} = ndt),
    do: DateTime.from_naive!(ndt, "Etc/UTC")

  defp ensure_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp ensure_datetime(_), do: DateTime.utc_now()

  defp convert_data_map(%D{} = decimal), do: normalize_number(D.to_float(decimal))
  defp convert_data_map(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp convert_data_map(number) when is_float(number) or is_integer(number),
    do: normalize_number(number)

  defp convert_data_map(struct) when is_struct(struct) do
    struct
    |> Map.from_struct()
    |> convert_data_map()
  end

  defp convert_data_map(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} -> {to_string(k), convert_data_map(v)} end)
    |> Map.new()
  end

  defp convert_data_map(list) when is_list(list), do: Enum.map(list, &convert_data_map/1)
  defp convert_data_map(other), do: other

  defp convert_numeric(%D{} = decimal), do: normalize_number(D.to_float(decimal))
  defp convert_numeric(number) when is_number(number), do: normalize_number(number)
  defp convert_numeric(_other), do: nil

  defp flatten_numeric_paths(value, prefix \\ nil)

  defp flatten_numeric_paths(%D{} = decimal, prefix) when not is_nil(prefix) do
    case normalize_number(D.to_float(decimal)) do
      nil -> %{}
      cleaned -> %{prefix => cleaned}
    end
  end

  defp flatten_numeric_paths(map, prefix) when is_map(map) and not is_struct(map) do
    Enum.reduce(map, %{}, fn {key, v}, acc ->
      path = join_path(prefix, key)
      Map.merge(acc, flatten_numeric_paths(v, path))
    end)
  end

  defp flatten_numeric_paths(list, prefix) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {v, index}, acc ->
      path = join_path(prefix, Integer.to_string(index))
      Map.merge(acc, flatten_numeric_paths(v, path))
    end)
  end

  defp flatten_numeric_paths(number, prefix) when is_number(number) and not is_nil(prefix) do
    case normalize_number(number) do
      nil -> %{}
      cleaned -> %{prefix => cleaned}
    end
  end

  defp flatten_numeric_paths(_other, _prefix), do: %{}

  defp join_path(nil, key), do: to_string(key)
  defp join_path(prefix, key), do: "#{prefix}.#{key}"

  defp normalize_number(number) when is_integer(number), do: number

  defp normalize_number(number) when is_float(number) do
    if number == number do
      number
    else
      nil
    end
  end

  defp normalize_number(_other), do: nil

  defp safe_tabulize(nil), do: nil

  defp safe_tabulize(stats) do
    Tabler.tabulize(stats)
  rescue
    _ -> nil
  end

  defp normalize_timeline_output(result) when is_map(result) do
    result
    |> Enum.map(fn {path, entries} -> {path, normalize_timeline_entries(entries)} end)
    |> Map.new()
  end

  defp normalize_timeline_output(result) when is_list(result) do
    Enum.map(result, &normalize_timeline_entries/1)
  end

  defp normalize_timeline_output(other), do: other

  defp normalize_timeline_entries(entries) when is_list(entries) do
    Enum.map(entries, fn
      %{} = entry -> normalize_timeline_entry(entry)
      list when is_list(list) -> normalize_timeline_entries(list)
      other -> other
    end)
  end

  defp normalize_timeline_entries(%{} = entry), do: normalize_timeline_entry(entry)
  defp normalize_timeline_entries(other), do: other

  defp normalize_timeline_entry(entry) when is_map(entry) do
    entry
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      key_string = to_string(key)

      normalized_value =
        case key_string do
          "at" -> normalize_datetime_value(value)
          _ -> normalize_timeline_value(value)
        end

      Map.put(acc, key_string, normalized_value)
    end)
  end

  defp normalize_timeline_value(value) when is_list(value) do
    Enum.map(value, &normalize_timeline_value/1)
  end

  defp normalize_timeline_value(value) when is_map(value) do
    normalize_timeline_entry(value)
  end

  defp normalize_timeline_value(value) do
    convert_numeric(value) || value
  end

  defp normalize_datetime_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp normalize_datetime_value(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp normalize_datetime_value(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> DateTime.to_iso8601(dt)
      _ -> value
    end
  end

  defp normalize_datetime_value(other), do: other

  defp normalize_category_output(result) when is_map(result), do: normalize_category_map(result)

  defp normalize_category_output(result) when is_list(result) do
    Enum.map(result, fn
      %{} = map -> normalize_category_map(map)
      other -> other
    end)
  end

  defp normalize_category_output(other), do: other

  defp normalize_category_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      normalized =
        cond do
          is_map(value) -> normalize_category_map(value)
          is_list(value) -> Enum.map(value, &normalize_category_value/1)
          true -> convert_numeric(value) || value
        end

      Map.put(acc, to_string(key), normalized)
    end)
  end

  defp normalize_category_value(value) when is_map(value), do: normalize_category_map(value)
  defp normalize_category_value(value), do: convert_numeric(value) || value
end
