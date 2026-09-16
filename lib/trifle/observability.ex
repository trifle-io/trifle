defmodule Trifle.Observability do
  @moduledoc """
  Configures the application's own Trifle Stats and Trifle Traces storage.

  Trace metadata is kept in PostgreSQL. Trace payloads are written to the
  configured S3-compatible object store or filesystem path.
  """

  require Logger

  alias Trifle.Traces.Driver.Data.File, as: FileData
  alias Trifle.Traces.Driver.Data.Null, as: NullData
  alias Trifle.Traces.Driver.Data.S3, as: S3Data
  alias Trifle.Traces.Driver.Index.Postgres, as: PostgresIndex

  @stats_connection Trifle.Observability.StatsPostgres
  @stats_table "trifle_internal_stats"
  @stats_ping_table "trifle_internal_stats_ping"
  @traces_table "trifle_traces"

  @postgres_options [
    :hostname,
    :port,
    :username,
    :password,
    :database,
    :socket,
    :socket_dir,
    :endpoints,
    :socket_options,
    :ssl,
    :ssl_opts,
    :parameters,
    :types,
    :prepare,
    :extensions,
    :connect_timeout,
    :timeout,
    :show_sensitive_data_on_connection_error
  ]

  @doc "Returns and configures the children needed for internal observability."
  def setup do
    if enabled?() do
      configure_stats()
      traces_config = configure_traces()

      [
        Supervisor.child_spec(
          {Postgrex, stats_connection_options()},
          id: @stats_connection
        ),
        Supervisor.child_spec(
          {Trifle.Traces.Oban,
           config: traces_config, handler_id: {Trifle.Traces.Oban, :trifle_internal}},
          id: Trifle.Traces.Oban
        )
      ]
    else
      []
    end
  end

  def enabled? do
    config()
    |> Keyword.get(:enabled, true)
  end

  @doc false
  def stats_connection_options(repo_config \\ Trifle.Repo.config()) do
    repo_config
    |> Keyword.take(@postgres_options)
    |> Keyword.put(:name, @stats_connection)
  end

  @doc false
  def trace_data_driver(options \\ config()) do
    case storage_backend(options) do
      :none ->
        %NullData{}

      :file ->
        path =
          options
          |> Keyword.get(:traces_storage_path)
          |> normalize_path()
          |> require_file_path!()

        driver_options = [path: path, gzip: Keyword.get(options, :traces_gzip, true)]
        :ok = FileData.setup!(driver_options)
        FileData.new(driver_options)

      :s3 ->
        s3_options = Keyword.get(options, :traces_s3, [])

        client_options =
          if Keyword.has_key?(s3_options, :client),
            do: Keyword.fetch!(s3_options, :client),
            else: s3_client_options(s3_options)

        driver_options =
          [
            buckets: Keyword.get(s3_options, :buckets, []),
            prefix: Keyword.get(s3_options, :prefix, "traces"),
            gzip: Keyword.get(options, :traces_gzip, true),
            client: client_options
          ]
          |> maybe_put(:adapter, Keyword.get(s3_options, :adapter))

        setup_options =
          Keyword.put(
            driver_options,
            :retentions,
            [Keyword.get(options, :traces_retention_days, 7)]
          )

        :ok = S3Data.setup!(setup_options)
        S3Data.new(driver_options)
    end
  end

  @doc false
  def s3_client_options(options) do
    endpoint_options =
      case options |> Keyword.get(:endpoint) |> normalize_optional_string() do
        nil -> []
        endpoint -> endpoint_client_options(endpoint)
      end

    credential_options =
      [
        access_key_id: Keyword.get(options, :access_key_id),
        secret_access_key: Keyword.get(options, :secret_access_key),
        region: Keyword.get(options, :region, "us-east-1"),
        http_opts: Keyword.get(options, :http_opts, with_body: true)
      ]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)

    credential_options ++ endpoint_options
  end

  @doc "Deletes trace indexes and filesystem payloads past their retention window."
  def cleanup! do
    internal_deleted = cleanup_internal!()

    # User-configured sources retain their cleanup independently of internal telemetry.
    configured_deleted =
      Trifle.Organizations.list_trace_databases()
      |> Enum.reject(&(&1.managed_key == Trifle.Observability.DatabaseProvisioner.managed_key()))
      |> Enum.reduce(0, fn database, total ->
        case Trifle.Traces.Source.Database.cleanup(database) do
          {:ok, deleted} ->
            total + deleted

          {:error, reason} ->
            Logger.warning("Failed to clean trace storage for database #{database.id}: #{reason}")

            total
        end
      end)

    {:ok, internal_deleted + configured_deleted}
  end

  @doc "Builds the editable database source for the application's internal observability data."
  def database_attrs do
    options = config()
    repo = Trifle.Repo.config()

    with true <- enabled?() || {:error, :observability_disabled},
         host when is_binary(host) and host != "" <- Keyword.get(repo, :hostname),
         {:ok, trace_attrs} <- trace_database_attrs(options) do
      {:ok,
       %{
         display_name: "Trifle internal observability",
         driver: "postgres",
         connection_method: "direct",
         host: host,
         port: Keyword.get(repo, :port, 5432),
         database_name: Keyword.get(repo, :database),
         username: Keyword.get(repo, :username),
         password: Keyword.get(repo, :password),
         config: %{
           "table_name" => @stats_table,
           "ping_table_name" => @stats_ping_table,
           "joined_identifiers" => "full",
           "pool_size" => 5,
           "pool_timeout" => 15_000,
           "timeout" => 15_000,
           "ssl" => Keyword.get(repo, :ssl, false)
         },
         granularities: ["1m", "1h", "1d", "1w", "1mo"],
         time_zone: "UTC",
         beginning_of_week: 1,
         default_timeframe: "24h",
         default_granularity: "1h"
       }
       |> Map.merge(trace_attrs)}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :postgres_hostname_unavailable}
    end
  end

  @doc false
  def start_trace_metric(tracer) do
    # Lifecycle callbacks execute in the trace's own GenServer. Preserve its initial
    # monotonic timestamp before subsequent bumps replace bumped_at.
    Process.put({__MODULE__, :trace_started_at, tracer.reference}, tracer.bumped_at)
    :ok
  end

  @doc false
  def record_trace(tracer) do
    started_at = Process.delete({__MODULE__, :trace_started_at, tracer.reference})

    values = %{
      count: 1,
      states: %{to_string(tracer.state) => 1},
      entries: %{count: length(tracer.data || [])}
    }

    values =
      if is_integer(started_at) do
        duration = max(System.monotonic_time(:millisecond) - started_at, 0)
        sample = %{count: 1, sum: duration, square: duration * duration}

        Map.put(values, :duration, Map.put(sample, :states, %{to_string(tracer.state) => sample}))
      else
        # A trace already in flight during a configuration update has no start
        # sample. Keep its event count, without inventing a zero duration.
        values
      end

    Trifle.Stats.track(metric_key(tracer.key), DateTime.utc_now(), values)
  rescue
    error ->
      Logger.warning(
        "Failed to record internal trace metric: " <> Exception.format_banner(:error, error)
      )

      :ok
  catch
    kind, reason ->
      Logger.warning("Failed to record internal trace metric: #{kind}: #{inspect(reason)}")
      :ok
  end

  @doc false
  def trace_error(error, _tracer, phase) do
    Logger.warning(
      "Trifle.Traces #{phase} persistence failed: " <> Exception.format_banner(:error, error)
    )

    :ok
  end

  defp configure_stats do
    driver =
      Trifle.Stats.Driver.Postgres.new(
        @stats_connection,
        @stats_table,
        :full,
        @stats_ping_table,
        true
      )

    Trifle.Stats.configure(
      driver: driver,
      time_zone: "UTC",
      beginning_of_week: :monday,
      track_granularities: ["1m", "1h", "1d", "1w", "1mo"],
      buffer_enabled: false
    )
  end

  defp cleanup_internal! do
    if enabled?() do
      traces_config = Trifle.Traces.configuration()
      deleted = PostgresIndex.cleanup!(traces_config.index_driver)

      case traces_config.data_driver do
        %FileData{} = driver -> FileData.cleanup!(driver)
        %S3Data{} -> :ok
        _driver -> :ok
      end

      deleted
    else
      0
    end
  end

  defp trace_database_attrs(options) do
    base = %{
      "index_name" => @traces_table,
      "retention_days" => Keyword.get(options, :traces_retention_days, 7),
      "gzip" => Keyword.get(options, :traces_gzip, true)
    }

    case storage_backend(options) do
      :file ->
        case options |> Keyword.get(:traces_storage_path) |> normalize_path() do
          path when is_binary(path) ->
            {:ok,
             %{trace_config: Map.merge(base, %{"data_driver" => "file", "data_path" => path})}}

          _ ->
            {:error, :trace_file_path_unavailable}
        end

      :s3 ->
        s3 = Keyword.get(options, :traces_s3, [])
        buckets = Keyword.get(s3, :buckets, [])

        if is_list(buckets) and buckets != [] do
          {:ok,
           %{
             trace_config:
               Map.merge(base, %{
                 "data_driver" => "s3",
                 "data_endpoint" => Keyword.get(s3, :endpoint),
                 "data_buckets" => buckets,
                 "data_region" => Keyword.get(s3, :region, "us-east-1"),
                 "data_prefix" => Keyword.get(s3, :prefix, "traces")
               }),
             trace_access_key_id: Keyword.get(s3, :access_key_id),
             trace_secret_access_key: Keyword.get(s3, :secret_access_key)
           }}
        else
          {:error, :trace_s3_buckets_unavailable}
        end

      :none ->
        {:error, :trace_payload_storage_unavailable}
    end
  end

  defp configure_traces do
    options = config()

    Trifle.Traces.configure(
      index_driver: PostgresIndex.new(Trifle.Repo, table_name: @traces_table),
      data_driver: trace_data_driver(options),
      bump_every: Keyword.get(options, :traces_bump_every, 15),
      payload_size_limit: Keyword.get(options, :traces_payload_size_limit, 100 * 1024),
      retention: Keyword.get(options, :traces_retention_days, 7),
      error_handler: &trace_error/3,
      on_liftoff: &start_trace_metric/1,
      on_wrapup: &record_trace/1
    )
  end

  defp config do
    Application.get_env(:trifle, __MODULE__, [])
  end

  defp metric_key(key) do
    to_string(key)
  end

  defp normalize_path(path) when path in [nil, ""], do: nil

  defp normalize_path(path) when is_binary(path) do
    case String.trim(path) do
      "" -> nil
      trimmed -> Path.expand(trimmed)
    end
  end

  defp storage_backend(options) do
    case Keyword.get(options, :traces_storage_backend) do
      backend when backend in [:none, :file, :s3] ->
        backend

      nil ->
        if(normalize_path(Keyword.get(options, :traces_storage_path)), do: :file, else: :none)

      backend ->
        raise ArgumentError, "unsupported trace storage backend: #{inspect(backend)}"
    end
  end

  defp require_file_path!(nil) do
    raise ArgumentError,
          "TRIFLE_TRACES_STORAGE_PATH is required when trace storage backend is file"
  end

  defp require_file_path!(path), do: path

  defp normalize_optional_string(value) when value in [nil, ""], do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp endpoint_client_options(endpoint) do
    uri = URI.parse(endpoint)

    if uri.scheme in ["http", "https"] and is_binary(uri.host) do
      [scheme: "#{uri.scheme}://", host: uri.host, port: uri.port]
    else
      raise ArgumentError, "invalid trace S3 endpoint: #{inspect(endpoint)}"
    end
  end

  defp maybe_put(options, _key, nil), do: options
  defp maybe_put(options, key, value), do: Keyword.put(options, key, value)
end
