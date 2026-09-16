defmodule Trifle.Observability do
  @moduledoc """
  Configures the application's own Trifle Stats and Trifle Traces storage.

  Trace metadata and Stats metrics use the configured PostgreSQL or MongoDB
  backend. Trace payloads use S3-compatible object storage or a filesystem.
  """

  require Logger

  alias Trifle.Traces.Driver.Data.File, as: FileData
  alias Trifle.Traces.Driver.Data.Null, as: NullData
  alias Trifle.Traces.Driver.Data.S3, as: S3Data
  alias Trifle.Traces.Driver.Index.Mongo, as: MongoIndex
  alias Trifle.Traces.Driver.Index.Postgres, as: PostgresIndex

  @stats_connection Trifle.Observability.StatsPostgres
  @mongo_connection Trifle.Observability.Mongo
  @stats_table "trifle_internal_stats"
  @stats_ping_table "trifle_internal_stats_ping"
  @traces_table "trifle_internal_traces"
  @default_granularities ["1m", "1h", "1d", "1mo"]
  @default_timeframe "6h"
  @default_granularity "1m"
  @default_time_zone "UTC"

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
      options = config()
      configure_stats(options)
      traces_config = configure_traces(options)

      storage_children(options) ++
        [
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

        if Keyword.get(options, :traces_manage_s3_lifecycle, true) do
          :ok = S3Data.setup!(setup_options)
        end

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
    granularities = granularities(options)

    with true <- enabled?() || {:error, :observability_disabled},
         {:ok, connection_attrs} <- database_connection_attrs(options),
         {:ok, trace_attrs} <- trace_database_attrs(options) do
      {:ok,
       %{
         display_name: "Trifle internal observability",
         connection_method: "direct",
         granularities: granularities,
         time_zone: time_zone(options),
         beginning_of_week: 1,
         default_timeframe: default_timeframe(options),
         default_granularity: default_granularity(options, granularities)
       }
       |> Map.merge(connection_attrs)
       |> Map.merge(trace_attrs)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp database_connection_attrs(options) do
    case index_backend(options) do
      :postgres ->
        repo = Trifle.Repo.config()

        case Keyword.get(repo, :hostname) do
          host when is_binary(host) and host != "" ->
            {:ok,
             %{
               driver: "postgres",
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
               }
             }}

          _ ->
            {:error, :postgres_hostname_unavailable}
        end

      :mongo ->
        mongo_database_attrs(Keyword.get(options, :mongodb_url))
    end
  end

  defp mongo_database_attrs(url) when is_binary(url) do
    uri = URI.parse(url)
    database = uri.path |> to_string() |> String.trim_leading("/") |> URI.decode()

    if uri.scheme == "mongodb" and is_binary(uri.host) and uri.host != "" and
         database != "" and not String.contains?(uri.host, ",") do
      [username, password] =
        case uri.userinfo do
          nil ->
            [nil, nil]

          userinfo ->
            case String.split(userinfo, ":", parts: 2) do
              [user, pass] -> [URI.decode(user), URI.decode(pass)]
              [user] -> [URI.decode(user), nil]
            end
        end

      auth_database =
        uri.query
        |> to_string()
        |> URI.decode_query()
        |> Map.get("authSource")

      {:ok,
       %{
         driver: "mongo",
         host: uri.host,
         port: uri.port || 27017,
         database_name: database,
         username: username,
         password: password,
         auth_database: auth_database,
         config: %{
           "collection_name" => @stats_table,
           "joined_identifiers" => "full",
           "pool_size" => 5
         }
       }}
    else
      {:error, :mongo_source_url_unavailable}
    end
  end

  defp mongo_database_attrs(_), do: {:error, :mongo_source_url_unavailable}

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

  defp configure_stats(options) do
    driver =
      case index_backend(options) do
        :postgres ->
          Trifle.Stats.Driver.Postgres.new(
            @stats_connection,
            @stats_table,
            :full,
            @stats_ping_table,
            true
          )

        :mongo ->
          Trifle.Stats.Driver.Mongo.new(@mongo_connection, @stats_table)
      end

    Trifle.Stats.configure(
      driver: driver,
      time_zone: time_zone(options),
      beginning_of_week: :monday,
      track_granularities: granularities(options),
      buffer_enabled: false
    )
  end

  @doc false
  def granularities(options \\ config()) do
    configured = Keyword.get(options, :granularities, @default_granularities)

    values =
      case configured do
        values when is_list(values) -> values
        value when is_binary(value) -> String.split(value, [",", "\n"], trim: true)
        _ -> []
      end

    values =
      values
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.uniq()
      |> Enum.filter(&valid_granularity?/1)

    if values == [], do: @default_granularities, else: values
  end

  @doc false
  def time_zone(options \\ config()) do
    configured = options |> Keyword.get(:time_zone, @default_time_zone) |> to_string()
    configured = String.trim(configured)

    if configured != "" and Tzdata.zone_exists?(configured),
      do: configured,
      else: @default_time_zone
  end

  defp valid_granularity?(value) do
    parser = Trifle.Stats.Nocturnal.Parser.new(value)
    Trifle.Stats.Nocturnal.Parser.valid?(parser) and parser.offset > 0
  end

  defp default_timeframe(options) do
    case Keyword.get(options, :default_timeframe, @default_timeframe) do
      value when is_binary(value) and value != "" -> value
      _ -> @default_timeframe
    end
  end

  defp default_granularity(options, granularities) do
    configured = Keyword.get(options, :default_granularity, @default_granularity)
    if configured in granularities, do: configured, else: List.first(granularities)
  end

  defp cleanup_internal! do
    if enabled?() do
      traces_config = Trifle.Traces.configuration()

      deleted =
        case traces_config.index_driver do
          %PostgresIndex{} = driver -> PostgresIndex.cleanup!(driver)
          %MongoIndex{} -> 0
        end

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

  defp configure_traces(options) do
    Trifle.Traces.configure(
      index_driver: trace_index_driver(options),
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

  defp index_backend(options) do
    case Keyword.get(options, :index_backend, :postgres) do
      backend when backend in [:postgres, :mongo] ->
        backend

      backend ->
        raise ArgumentError, "unsupported observability index backend: #{inspect(backend)}"
    end
  end

  defp storage_children(options) do
    case index_backend(options) do
      :postgres ->
        [Supervisor.child_spec({Postgrex, stats_connection_options()}, id: @stats_connection)]

      :mongo ->
        url = Keyword.get(options, :mongodb_url)

        if not is_binary(url) or String.trim(url) == "" do
          raise ArgumentError, "MONGODB_URL is required for MongoDB observability"
        end

        [
          Supervisor.child_spec({Mongo, name: @mongo_connection, url: url}, id: @mongo_connection),
          {Trifle.Observability.MongoSetup,
           connection: @mongo_connection,
           stats_collection: @stats_table,
           traces_collection: @traces_table}
        ]
    end
  end

  defp trace_index_driver(options) do
    case index_backend(options) do
      :postgres -> PostgresIndex.new(Trifle.Repo, table_name: @traces_table)
      :mongo -> MongoIndex.new(@mongo_connection, collection_name: @traces_table)
    end
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
