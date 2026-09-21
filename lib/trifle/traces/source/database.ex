defmodule Trifle.Traces.Source.Database do
  @moduledoc """
  Builds and manages a Trifle Traces configuration backed by an organization database.

  The database remains a Trifle Stats source. A non-empty, validated `trace_config`
  adds a trace index and payload store without changing its Stats behaviour.
  """

  alias Trifle.Organizations.Database
  alias Trifle.Traces.Configuration
  alias Trifle.Traces.Driver
  alias Trifle.Traces.Driver.Data.File, as: FileData
  alias Trifle.Traces.Driver.Data.S3, as: S3Data
  alias Trifle.Traces.Driver.Index.Mongo, as: MongoIndex
  alias Trifle.Traces.Driver.Index.Postgres, as: PostgresIndex
  alias Trifle.Traces.TraceRecord

  @probe_key "__trifle/trace_storage_probe__"

  @spec configuration(Database.t()) :: Configuration.t()
  def configuration(%Database{} = database) do
    unless Database.traces_configured?(database) do
      raise ArgumentError, "database does not have a Trifle Traces configuration"
    end

    config = database.trace_config

    Configuration.new(
      index_driver: index_driver(database, config),
      data_driver: data_driver(database, config),
      retention: config["retention_days"]
    )
  end

  @spec setup(Database.t()) :: :ok | {:error, String.t()}
  def setup(%Database{} = database) do
    if Database.traces_configured?(database) do
      try do
        config = database.trace_config
        setup_index!(database, config)
        setup_data!(database, config)
        :ok
      rescue
        error -> {:error, friendly_error(error)}
      catch
        kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
      end
    else
      :ok
    end
  end

  @spec check(Database.t()) :: {:ok, boolean()} | {:error, String.t()}
  def check(%Database{} = database) do
    if Database.traces_configured?(database) do
      try do
        config = database.trace_config

        if index_exists?(database, config) do
          probe_data!(database, config)
          {:ok, true}
        else
          {:ok, false}
        end
      rescue
        error -> {:error, friendly_error(error)}
      catch
        kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
      end
    else
      {:ok, true}
    end
  end

  @spec cleanup(Database.t()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def cleanup(%Database{} = database) do
    if Database.traces_configured?(database) do
      try do
        config = configuration(database)

        deleted =
          case config.index_driver do
            %PostgresIndex{} = driver -> PostgresIndex.cleanup!(driver)
            %MongoIndex{} -> 0
          end

        case config.data_driver do
          %FileData{} = driver -> FileData.cleanup!(driver)
          %S3Data{} -> :ok
        end

        {:ok, deleted}
      rescue
        error -> {:error, friendly_error(error)}
      catch
        kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
      end
    else
      {:ok, 0}
    end
  end

  defp index_driver(%Database{driver: "postgres"} = database, config) do
    {:ok, connection} =
      Trifle.DatabasePools.PostgresPoolSupervisor.start_postgres_pool(database)

    PostgresIndex.new(connection, table_name: config["index_name"])
  end

  defp index_driver(%Database{driver: "mongo"} = database, config) do
    {:ok, connection} = Trifle.DatabasePools.MongoPoolSupervisor.start_mongo_pool(database)
    MongoIndex.new(connection, collection_name: config["index_name"])
  end

  defp data_driver(_database, %{"data_driver" => "file"} = config) do
    FileData.new(path: config["data_path"], gzip: config["gzip"])
  end

  defp data_driver(database, %{"data_driver" => "s3"} = config) do
    S3Data.new(s3_driver_options(database, config))
  end

  defp setup_index!(%Database{driver: "postgres"} = database, config) do
    {:ok, connection} =
      Trifle.DatabasePools.PostgresPoolSupervisor.start_postgres_pool(database)

    PostgresIndex.setup!(connection, table_name: config["index_name"])
  end

  defp setup_index!(%Database{driver: "mongo"} = database, config) do
    {:ok, connection} = Trifle.DatabasePools.MongoPoolSupervisor.start_mongo_pool(database)
    MongoIndex.setup!(connection, collection_name: config["index_name"])
  end

  defp setup_data!(_database, %{"data_driver" => "file"} = config) do
    FileData.setup!(path: config["data_path"], gzip: config["gzip"])
  end

  defp setup_data!(database, %{"data_driver" => "s3"} = config) do
    if manage_s3_lifecycle?(database) do
      config
      |> s3_driver_options(database)
      |> Keyword.put(:retentions, [config["retention_days"]])
      |> S3Data.setup!()
    else
      :ok
    end
  end

  defp manage_s3_lifecycle?(%Database{managed_key: "internal_trifle_observability"}) do
    :trifle
    |> Application.get_env(Trifle.Observability, [])
    |> Keyword.get(:traces_manage_s3_lifecycle, true)
  end

  defp manage_s3_lifecycle?(_database), do: true

  defp index_exists?(%Database{driver: "postgres"} = database, config) do
    {:ok, connection} =
      Trifle.DatabasePools.PostgresPoolSupervisor.start_postgres_pool(database)

    case Postgrex.query(connection, "SELECT to_regclass($1) IS NOT NULL", [config["index_name"]]) do
      {:ok, %{rows: [[exists?]]}} -> exists?
      {:error, error} -> raise error
    end
  end

  defp index_exists?(%Database{driver: "mongo"} = database, config) do
    {:ok, connection} = Trifle.DatabasePools.MongoPoolSupervisor.start_mongo_pool(database)
    config["index_name"] in Enum.to_list(Mongo.show_collections(connection))
  end

  defp probe_data!(database, config) do
    driver = data_driver(database, config)
    reference = "probe-#{Ecto.UUID.generate()}"

    record = %TraceRecord{
      reference: reference,
      key: @probe_key,
      retention: config["retention_days"],
      bucket_id: Driver.call(driver, :generate_bucket_id)
    }

    entries = [
      %{
        at: System.system_time(:millisecond),
        message: "Trifle trace storage probe",
        state: :success,
        type: :text,
        level: 0
      }
    ]

    try do
      Driver.call(driver, :write_part, [record, 1, entries])

      case Driver.call(driver, :read_part, [record, 1]) do
        ^entries -> :ok
        other -> raise "trace payload probe returned unexpected data: #{inspect(other)}"
      end
    after
      Driver.call(driver, :delete, [record])
    end
  end

  defp s3_driver_options(%Database{} = database, config) do
    client =
      Trifle.Observability.s3_client_options(
        endpoint: config["data_endpoint"],
        region: config["data_region"],
        access_key_id: database.trace_access_key_id,
        secret_access_key: database.trace_secret_access_key
      )

    client =
      if database.trace_network_connection_id do
        case Trifle.Networking.Tailscale.s3_options(database) do
          {:ok, options} ->
            Keyword.put(client, :http_opts, options)

          {:error, reason} ->
            raise "Unable to connect to private trace storage: #{inspect(reason)}"
        end
      else
        client
      end

    [
      buckets: config["data_buckets"],
      prefix: config["data_prefix"],
      gzip: config["gzip"],
      client: client
    ]
  end

  defp s3_driver_options(config, %Database{} = database),
    do: s3_driver_options(database, config)

  defp friendly_error(error) do
    error
    |> Exception.message()
    |> String.replace(~r/(?i)(password|passphrase|secret|token)=([^\s,;]+)/, "\\1=[REDACTED]")
    |> String.replace(~r{(://[^:/\s]+:)[^@\s]+@}, "\\1[REDACTED]@")
  end
end
