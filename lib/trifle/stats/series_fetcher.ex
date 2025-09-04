defmodule Trifle.Stats.SeriesFetcher do
  @moduledoc """
  Unified module for fetching and processing series data with transponder application.
  
  This module provides a consistent interface for:
  - Fetching raw stats data from Trifle.Stats
  - Applying transponders to transform data
  - Progressive loading for large datasets
  - Handling both system keys and specific keys
  """
  
  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  
  require Logger
  
  @default_chunk_size 720
  @transponder_timeout 300_000
  
  # Public API
  
  @doc """
  Fetches series data for a given key with optional transponder application.
  
  ## Options
  - `:progressive` - Enable progressive loading for large datasets (default: true)
  - `:apply_transponders` - Apply transponders to the data (default: true) 
  - `:chunk_size` - Size of chunks for progressive loading (default: 720)
  """
  def fetch_series(%Database{} = database, key, from, to, granularity, opts \\ []) do
    config = Database.stats_config(database)
    
    opts = Keyword.merge([
      progressive: true,
      apply_transponders: true,
      chunk_size: @default_chunk_size
    ], opts)
    
    with {:ok, raw_stats} <- fetch_raw_stats(key, from, to, granularity, config, opts),
         {:ok, processed_stats} <- maybe_apply_transponders(raw_stats, key, database, opts) do
      {:ok, processed_stats}
    end
  end
  
  @doc """
  Fetches database system overview (all keys) with progressive loading.
  """
  def fetch_system_overview(database, from, to, granularity, opts \\ []) do
    fetch_series(database, "__system__key__", from, to, granularity, opts)
  end
  
  @doc """
  Generates timeline for the given parameters.
  """
  def generate_timeline(from, to, granularity, config) do
    parser = Trifle.Stats.Parser.new(granularity, config.time_zone || "UTC")
    normalized_from = Trifle.Stats.Normalizer.normalize(from, parser)
    normalized_to = Trifle.Stats.Normalizer.normalize(to, parser)
    
    Trifle.Stats.Timeline.generate(normalized_from, normalized_to, parser)
  end
  
  @doc """
  Determines if timeline should be loaded progressively.
  """
  def should_slice_timeline?(from, to, granularity, config, chunk_size \\ @default_chunk_size) do
    timeline = generate_timeline(from, to, granularity, config)
    length(timeline) > chunk_size
  end
  
  # Private Implementation
  
  defp fetch_raw_stats(key, from, to, granularity, config, opts) do
    if opts[:progressive] and should_slice_timeline?(from, to, granularity, config, opts[:chunk_size]) do
      fetch_stats_progressive(key, from, to, granularity, config, opts[:chunk_size])
    else
      fetch_stats_direct(key, from, to, granularity, config)
    end
  end
  
  defp fetch_stats_direct(key, from, to, granularity, config) do
    case Trifle.Stats.values(key, from, to, granularity, config) do
      {:ok, stats} -> {:ok, stats}
      error -> {:error, {:fetch_failed, error}}
    end
  end
  
  defp fetch_stats_progressive(key, from, to, granularity, config, chunk_size) do
    timeline = generate_timeline(from, to, granularity, config)
    chunks = Enum.chunk_every(timeline, chunk_size)
    
    # Load all chunks and accumulate results
    results = 
      chunks
      |> Enum.reverse() # Load newest first
      |> Enum.map(&load_chunk(key, &1, granularity, config))
      |> Enum.reduce({:ok, %{}}, &accumulate_chunk_result/2)
    
    case results do
      {:ok, accumulated_stats} -> {:ok, accumulated_stats}
      error -> error
    end
  end
  
  defp load_chunk(key, chunk, granularity, config) do
    chunk_from = List.first(chunk)
    chunk_to = List.last(chunk)
    
    case Trifle.Stats.values(key, chunk_from, chunk_to, granularity, config) do
      {:ok, stats} -> {:ok, stats}
      error -> {:error, {:chunk_failed, error}}
    end
  end
  
  defp accumulate_chunk_result({:ok, chunk_stats}, {:ok, accumulated_stats}) do
    merged_stats = Trifle.Stats.Packer.deep_sum([accumulated_stats, chunk_stats])
    {:ok, merged_stats}
  end
  
  defp accumulate_chunk_result({:error, error}, _acc) do
    {:error, error}
  end
  
  defp accumulate_chunk_result(_chunk, {:error, error}) do
    {:error, error}
  end
  
  defp maybe_apply_transponders(raw_stats, key, database, opts) do
    if opts[:apply_transponders] do
      apply_transponders_to_stats(raw_stats, key, database)
    else
      {:ok, raw_stats}
    end
  end
  
  defp apply_transponders_to_stats(raw_stats, key, database) do
    transponders = get_enabled_transponders_for_key(key, database)
    
    if Enum.empty?(transponders) do
      {:ok, raw_stats}
    else
      task = Task.async(fn -> 
        try do
          series = Trifle.Stats.Series.new(raw_stats)
          
          result = Enum.reduce_while(transponders, series, fn transponder, acc ->
            case apply_single_transponder(transponder, acc) do
              {:ok, transformed} -> {:cont, transformed}
              {:error, error} -> 
                Logger.warning("Transponder #{transponder.key} failed: #{inspect(error)}")
                {:halt, {:error, error}}
            end
          end)
          
          case result do
            %Trifle.Stats.Series{} = final_series -> {:ok, final_series.values}
            {:error, error} -> {:error, error}
          end
        rescue
          e -> {:error, {:transponder_exception, e}}
        end
      end)
      
      case Task.await(task, @transponder_timeout) do
        {:ok, transformed_stats} -> {:ok, transformed_stats}
        {:error, error} -> 
          Logger.error("Transponder application failed: #{inspect(error)}")
          {:ok, raw_stats} # Fallback to raw stats on transponder failure
      end
    end
  end
  
  defp apply_single_transponder(transponder, series) do
    config = Jason.decode!(transponder.payload || "{}")
    
    try do
      case transponder.type do
        "Add" -> 
          {:ok, Trifle.Stats.Series.transform_add(series, config["addend"] || 0)}
        "Subtract" -> 
          {:ok, Trifle.Stats.Series.transform_subtract(series, config["subtrahend"] || 0)}
        "Multiply" -> 
          {:ok, Trifle.Stats.Series.transform_multiply(series, config["multiplier"] || 1)}
        "Divide" -> 
          {:ok, Trifle.Stats.Series.transform_divide(series, config["divisor"] || 1)}
        "Ratio" -> 
          {:ok, Trifle.Stats.Series.transform_ratio(series, config["path"] || "")}
        "Sum" -> 
          {:ok, Trifle.Stats.Series.transform_sum(series, config["path"] || "")}
        "Mean" -> 
          {:ok, Trifle.Stats.Series.transform_mean(series, config["path"] || "")}
        "Min" -> 
          {:ok, Trifle.Stats.Series.transform_min(series, config["path"] || "")}
        "Max" -> 
          {:ok, Trifle.Stats.Series.transform_max(series, config["path"] || "")}
        "StandardDeviation" -> 
          {:ok, Trifle.Stats.Series.transform_standard_deviation(series, config["path"] || "")}
        _ ->
          {:error, {:unknown_transponder_type, transponder.type}}
      end
    rescue
      e -> {:error, {:transponder_execution_error, e}}
    end
  end
  
  defp get_enabled_transponders_for_key(key, database) when key != "__system__key__" do
    database
    |> Organizations.list_transponders_for_database()
    |> Enum.filter(fn t -> t.enabled && key_matches_pattern?(key, t.key) end)
    |> Enum.sort_by(& &1.order)
  end
  
  defp get_enabled_transponders_for_key("__system__key__", _database), do: []
  
  defp key_matches_pattern?(key, pattern) do
    cond do
      String.contains?(pattern, "^") or String.contains?(pattern, "$") ->
        case Regex.compile(pattern) do
          {:ok, regex} -> Regex.match?(regex, key)
          {:error, _} -> false
        end
      true ->
        key == pattern
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
  
  @doc """
  Converts processed stats to table-ready format.
  """
  def to_table_data(stats) do
    case Trifle.Stats.Tabler.tabulize(stats) do
      {:ok, tabulated} -> 
        case Trifle.Stats.Tabler.seriesize(tabulated) do
          {:ok, serialized} -> {:ok, serialized}
          error -> {:error, {:table_serialization_failed, error}}
        end
      error -> {:error, {:table_processing_failed, error}}
    end
  end
  
  defp datetime_to_chart_timestamp(%DateTime{} = dt) do
    dt
    |> DateTime.to_naive()
    |> NaiveDateTime.to_erl()
    |> :calendar.datetime_to_gregorian_seconds()
    |> Kernel.-(62167219200) # Unix epoch adjustment
    |> Kernel.*(1000) # Convert to milliseconds
  end
  
  defp process_stats_for_charts(stats, _timeline) do
    # This would need the specific chart processing logic
    # extracted from the original implementation
    stats
  end
end