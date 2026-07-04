defmodule Trifle.Stats.SeriesFetcher do
  @moduledoc """
  Unified module for fetching and processing series data with transponder application.

  This module provides a consistent interface for:
  - Fetching raw stats data from Trifle.Stats
  - Applying transponders to transform data
  - Progressive loading for large datasets
  - Handling both system keys and specific keys
  """

  alias Trifle.Organizations.Database
  alias Trifle.Stats.ConnectorValues
  alias Trifle.Stats.Source

  require Logger

  @default_chunk_size 720
  @default_progressive_concurrency 1
  @connector_progressive_concurrency 10
  @transponder_timeout 300_000

  # Public API

  @doc """
  Fetches series data for a given key with transponder application.

  ## Parameters
  - `database` - Database struct
  - `key` - The key to fetch data for
  - `from` - Start datetime
  - `to` - End datetime  
  - `granularity` - Time granularity
  - `transponders` - List of transponders to apply (empty list for __system__key__)
  - `opts` - Options for progressive loading

  ## Options
  - `:progressive` - Enable progressive loading for large datasets (default: true)
  - `:chunk_size` - Size of chunks for progressive loading (default: 720)
  """
  def fetch_series(source, key, from, to, granularity, transponders, opts \\ [])

  def fetch_series(%Source{} = source, key, from, to, granularity, transponders, opts) do
    :telemetry.span(
      [:trifle, :stats, :fetch_series],
      %{key: key, granularity: granularity},
      fn ->
        result = do_fetch_series(source, key, from, to, granularity, transponders, opts)

        status =
          case result do
            {:ok, _} -> :ok
            _ -> :error
          end

        {result, %{key: key, granularity: granularity, status: status}}
      end
    )
  end

  def fetch_series(
        %Trifle.Organizations.Database{} = database,
        key,
        from,
        to,
        granularity,
        transponders,
        opts
      ) do
    source = Source.from_database(database)
    fetch_series(source, key, from, to, granularity, transponders, opts)
  end

  defp do_fetch_series(%Source{} = source, key, from, to, granularity, transponders, opts) do
    config = Source.stats_config(source)

    opts =
      Keyword.merge(
        [
          progressive: true,
          chunk_size: @default_chunk_size,
          progressive_concurrency: default_progressive_concurrency(source),
          progress_callback: nil
        ],
        opts
      )

    fetcher = raw_stats_fetcher(source, opts)

    with {:ok, raw_stats} <- fetch_raw_stats(key, from, to, granularity, config, opts, fetcher),
         {:ok, result} <-
           apply_transponders_to_stats(raw_stats, transponders, opts[:progress_callback]) do
      {:ok, result}
    end
  end

  @doc """
  Fetches database system overview (all keys) with progressive loading.
  """
  def fetch_system_overview(source, from, to, granularity, opts \\ [])

  def fetch_system_overview(%Source{} = source, from, to, granularity, opts) do
    fetch_series(source, "__system__key__", from, to, granularity, [], opts)
  end

  def fetch_system_overview(
        %Trifle.Organizations.Database{} = database,
        from,
        to,
        granularity,
        opts
      ) do
    source = Source.from_database(database)
    fetch_system_overview(source, from, to, granularity, opts)
  end

  @doc """
  Generates timeline for the given parameters.
  """
  def generate_timeline(from, to, granularity, config) do
    parser = Trifle.Stats.Nocturnal.Parser.new(granularity)
    from_normalized = DateTime.shift_zone!(from, config.time_zone)
    to_normalized = DateTime.shift_zone!(to, config.time_zone)

    # Use the correct Nocturnal API - it expects keyword arguments
    Trifle.Stats.Nocturnal.timeline(
      from: from_normalized,
      to: to_normalized,
      offset: parser.offset,
      unit: parser.unit,
      config: config
    )
  end

  @doc """
  Determines if timeline should be loaded progressively.
  """
  def should_slice_timeline?(from, to, granularity, config, chunk_size \\ @default_chunk_size) do
    from
    |> generate_timeline(to, granularity, config)
    |> timeline_exceeds_chunk_size?(chunk_size)
  end

  # Private Implementation

  defp timeline_exceeds_chunk_size?(timeline, chunk_size) do
    length(timeline) > (chunk_size || @default_chunk_size)
  end

  defp fetch_raw_stats(key, from, to, granularity, config, opts, fetcher) do
    timeline = if opts[:progressive], do: generate_timeline(from, to, granularity, config)

    if timeline && timeline_exceeds_chunk_size?(timeline, opts[:chunk_size]) do
      fetch_stats_progressive(
        key,
        timeline,
        granularity,
        config,
        opts[:chunk_size],
        opts[:progressive_concurrency],
        opts[:progress_callback],
        fetcher
      )
    else
      fetch_stats_direct(key, from, to, granularity, config, opts[:progress_callback], fetcher)
    end
  end

  defp fetch_stats_direct(key, from, to, granularity, config, progress_callback, fetcher) do
    if progress_callback do
      progress_callback.({:chunk_progress, 1, 1})
    end

    with {:ok, stats} <- fetcher.(key, from, to, granularity, config) do
      {:ok, ensure_chronological(stats)}
    end
  end

  defp fetch_stats_progressive(
         key,
         timeline,
         granularity,
         config,
         chunk_size,
         progressive_concurrency,
         progress_callback,
         fetcher
       ) do
    chunks = Enum.chunk_every(timeline, chunk_size)
    total_chunks = length(chunks)
    concurrency = normalize_progressive_concurrency(progressive_concurrency)

    chunk_entries =
      chunks
      # Load newest first.
      |> Enum.reverse()
      |> Enum.with_index(1)

    loaded_chunks =
      if concurrency == 1 do
        load_chunks_serial(
          chunk_entries,
          key,
          granularity,
          config,
          progress_callback,
          fetcher,
          total_chunks
        )
      else
        load_chunks_concurrent(
          chunk_entries,
          key,
          granularity,
          config,
          progress_callback,
          fetcher,
          total_chunks,
          concurrency
        )
      end

    results =
      loaded_chunks
      |> Enum.sort_by(fn {chunk_index, _chunk_result} -> chunk_index end)
      |> Enum.reduce({:ok, %{}}, fn {_chunk_index, chunk_result}, acc_result ->
        accumulate_chunk_result(chunk_result, acc_result)
      end)

    case results do
      {:ok, accumulated_stats} ->
        {:ok, ensure_chronological(accumulated_stats)}

      error ->
        error
    end
  end

  defp load_chunks_serial(
         chunk_entries,
         key,
         granularity,
         config,
         progress_callback,
         fetcher,
         total_chunks
       ) do
    Enum.map(chunk_entries, fn {chunk, chunk_index} ->
      if progress_callback do
        progress_callback.({:chunk_progress, chunk_index, total_chunks})
      end

      {chunk_index, load_chunk(key, chunk, granularity, config, fetcher)}
    end)
  end

  defp load_chunks_concurrent(
         chunk_entries,
         key,
         granularity,
         config,
         progress_callback,
         fetcher,
         total_chunks,
         concurrency
       ) do
    {loaded_chunks, _completed} =
      chunk_entries
      |> Task.async_stream(
        fn {chunk, chunk_index} ->
          {chunk_index, load_chunk(key, chunk, granularity, config, fetcher)}
        end,
        max_concurrency: concurrency,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.reduce({[], 0}, fn
        {:ok, {chunk_index, chunk_result}}, {acc, completed} ->
          completed = completed + 1

          if progress_callback do
            progress_callback.({:chunk_progress, completed, total_chunks})
          end

          {[{chunk_index, chunk_result} | acc], completed}

        {:exit, reason}, {acc, completed} ->
          completed = completed + 1

          if progress_callback do
            progress_callback.({:chunk_progress, completed, total_chunks})
          end

          {[{completed, {:error, reason}} | acc], completed}
      end)

    loaded_chunks
  end

  defp load_chunk(key, chunk, granularity, config, fetcher) do
    chunk_from = List.first(chunk)
    chunk_to = List.last(chunk)

    fetcher.(key, chunk_from, chunk_to, granularity, config)
  end

  defp default_progressive_concurrency(%Source{
         module: Trifle.Stats.Source.Database,
         record: %Database{connection_method: "connector"}
       }) do
    @connector_progressive_concurrency
  end

  defp default_progressive_concurrency(_source), do: @default_progressive_concurrency

  defp normalize_progressive_concurrency(value) when is_integer(value) do
    value
    |> max(1)
    |> min(@connector_progressive_concurrency)
  end

  defp normalize_progressive_concurrency(_value), do: @default_progressive_concurrency

  defp raw_stats_fetcher(
         %Source{
           module: Trifle.Stats.Source.Database,
           record: %Database{connection_method: "connector"} = database
         },
         opts
       ) do
    connector_opts = Keyword.take(opts, [:connector_timeout])

    fn key, from, to, granularity, _config ->
      ConnectorValues.fetch_values(database, key, from, to, granularity, connector_opts)
    end
  end

  defp raw_stats_fetcher(_source, _opts) do
    fn key, from, to, granularity, config ->
      {:ok, Trifle.Stats.values(key, from, to, granularity, config)}
    end
  end

  defp accumulate_chunk_result({:ok, chunk_stats}, {:ok, accumulated_stats}) do
    # Merge the timeline (at) arrays and values while preserving chronological order.
    # We iterate chunks newest-first, so prepend the current chunk to keep ascending timestamps.
    merged_at = (chunk_stats[:at] || []) ++ (accumulated_stats[:at] || [])
    merged_values = (chunk_stats[:values] || []) ++ (accumulated_stats[:values] || [])

    merged_stats = %{at: merged_at, values: merged_values}
    {:ok, merged_stats}
  end

  defp accumulate_chunk_result({:error, error}, _accumulated_stats) do
    {:error, error}
  end

  defp accumulate_chunk_result(_chunk, {:error, error}) do
    {:error, error}
  end

  defp ensure_chronological(%{at: at, values: values} = stats) do
    zipped = Enum.zip(at || [], values || [])

    sorted = Enum.sort_by(zipped, fn {ts, _v} -> ts_to_int(ts) end)

    if sorted != zipped do
      Logger.warning(fn ->
        %{
          total_points: length(zipped),
          original_first: format_ts_value(List.first(zipped)),
          original_last: format_ts_value(List.last(zipped)),
          sorted_first: format_ts_value(List.first(sorted)),
          sorted_last: format_ts_value(List.last(sorted))
        }
        |> then(&"[SeriesFetcher] timeline out of order; reordered #{inspect(&1)}")
      end)
    end

    {sorted_at, sorted_values} = Enum.unzip(sorted)
    %{stats | at: sorted_at, values: sorted_values}
  end

  defp ensure_chronological(other), do: other

  defp ts_to_int(%DateTime{} = dt), do: DateTime.to_unix(dt, :microsecond)

  defp ts_to_int(%NaiveDateTime{} = ndt),
    do: DateTime.to_unix(DateTime.from_naive!(ndt, "Etc/UTC"), :microsecond)

  defp ts_to_int(int) when is_integer(int), do: int
  defp ts_to_int(float) when is_float(float), do: round(float * 1_000_000)
  defp ts_to_int(_), do: 0

  defp format_ts_value(nil), do: nil

  defp format_ts_value({ts, value}) do
    %{ts: inspect(ts), value: inspect(value)}
  end

  defp format_ts_value(other), do: inspect(other)

  defp apply_transponders_to_stats(raw_stats, transponders, progress_callback) do
    if Enum.empty?(transponders) do
      {:ok,
       %{
         series: Trifle.Stats.Series.new(raw_stats),
         transponder_results: %{
           successful: [],
           failed: [],
           errors: []
         }
       }}
    else
      if progress_callback do
        progress_callback.({:transponder_progress, :starting})
      end

      task =
        Task.async(fn ->
          try do
            series = Trifle.Stats.Series.new(raw_stats)

            # Use reduce instead of reduce_while to continue on failures
            {final_series, results} =
              Enum.reduce(
                transponders,
                {series, %{successful: [], failed: [], errors: []}},
                fn transponder, {acc_series, acc_results} ->
                  case apply_single_transponder(transponder, acc_series) do
                    {:ok, transformed} ->
                      {transformed,
                       %{
                         successful: [transponder | acc_results.successful],
                         failed: acc_results.failed,
                         errors: acc_results.errors
                       }}

                    {:error, error} ->
                      Logger.warning("Transponder #{transponder.key} failed: #{inspect(error)}")

                      {acc_series,
                       %{
                         successful: acc_results.successful,
                         failed: [transponder | acc_results.failed],
                         errors: [%{transponder: transponder, error: error} | acc_results.errors]
                       }}
                  end
                end
              )

            {:ok,
             %{
               series: final_series,
               transponder_results: %{
                 successful: Enum.reverse(results.successful),
                 failed: Enum.reverse(results.failed),
                 errors: Enum.reverse(results.errors)
               }
             }}
          rescue
            e -> {:error, {:transponder_exception, e}}
          end
        end)

      try do
        case Task.await(task, @transponder_timeout) do
          {:ok, result} ->
            {:ok, result}

          {:error, error} ->
            Logger.error("Transponder application failed: #{inspect(error)}")

            {:ok,
             %{
               series: Trifle.Stats.Series.new(raw_stats),
               transponder_results: %{
                 successful: [],
                 failed: transponders,
                 errors:
                   Enum.map(transponders, fn t ->
                     %{
                       transponder: t,
                       error: %{message: "Timeout or exception: #{inspect(error)}"}
                     }
                   end)
               }
             }}
        end
      after
        if progress_callback do
          progress_callback.({:transponder_progress, :finished})
        end
      end
    end
  end

  defp apply_single_transponder(transponder, series) do
    config = transponder.config || %{}

    try do
      paths = config["paths"] || config[:paths] || []
      expression = config["expression"] || config[:expression] || ""
      response = config["response"] || config[:response] || ""

      case Trifle.Stats.Transponder.Expression.transform(
             series.series,
             paths,
             expression,
             response
           ) do
        {:ok, updated} -> {:ok, %Trifle.Stats.Series{series: updated}}
        {:error, reason} -> {:error, reason}
      end
    rescue
      e -> {:error, {:transponder_execution_error, e}}
    end
  end

  # Chart Data Conversion

  @doc """
  Converts processed stats to chart-ready format.
  """
  def to_chart_data(stats, from, to, granularity, config) do
    timeline = generate_timeline(from, to, granularity, config)

    # Convert timeline to millisecond timestamps for charts
    chart_timeline = Enum.map(timeline, &datetime_to_chart_timestamp/1)

    # Process stats into chart series format
    chart_series = process_stats_for_charts(stats, chart_timeline)

    %{
      timeline: chart_timeline,
      series: chart_series
    }
  end

  defp datetime_to_chart_timestamp(%DateTime{} = dt) do
    dt
    |> DateTime.to_naive()
    |> NaiveDateTime.to_erl()
    |> :calendar.datetime_to_gregorian_seconds()
    # Unix epoch adjustment
    |> Kernel.-(62_167_219_200)
    # Convert to milliseconds
    |> Kernel.*(1000)
  end

  defp process_stats_for_charts(stats, _timeline) do
    # This would need the specific chart processing logic
    # extracted from the original implementation
    stats
  end
end
