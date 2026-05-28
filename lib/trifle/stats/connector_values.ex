defmodule Trifle.Stats.ConnectorValues do
  @moduledoc """
  Fetches Trifle Stats values through a Private Connector.

  The app still owns timeline generation and Trifle Stats identifier generation.
  The connector receives concrete storage identifiers and only performs the
  database reads from inside the user's network.
  """

  alias Trifle.Organizations
  alias Trifle.Organizations.{ConnectorJob, Database, OrganizationConnector}
  alias Trifle.Repo
  alias Trifle.Stats.Nocturnal.Key
  alias Trifle.Stats.SeriesFetcher

  @default_timeout_ms 60_000
  @max_timeout_ms 120_000

  def fetch_values(database, key, from, to, granularity, opts \\ [])

  def fetch_values(
        %Database{connection_method: "connector"} = database,
        key,
        from,
        to,
        granularity,
        opts
      ) do
    timeout_ms =
      opts
      |> Keyword.get(:connector_timeout, @default_timeout_ms)
      |> normalize_timeout()

    with {:ok, connector} <- connector_for_database(database),
         {:ok, payload} <- build_payload(database, key, from, to, granularity, timeout_ms),
         {:ok, job} <- Organizations.enqueue_connector_job(connector, "stats_values", payload),
         {:ok, completed_job} <- await_connector_completion(connector, job, timeout_ms),
         {:ok, stats} <- connector_stats_result(completed_job) do
      discard_connector_job_result(completed_job)
      {:ok, stats}
    end
  end

  def fetch_values(_database, _key, _from, _to, _granularity, _opts) do
    {:error, :not_connector_database}
  end

  defp build_payload(database, key, from, to, granularity, timeout_ms) do
    host = database.host |> to_string() |> String.trim()
    port = database.port || default_port(database.driver)

    cond do
      host == "" ->
        {:error, "Database host is required for Private Connector queries"}

      not is_integer(port) ->
        {:error, "Database port is required for Private Connector queries"}

      true ->
        config = Database.stats_metadata_config(database)
        timeline = SeriesFetcher.generate_timeline(from, to, granularity, config)

        {:ok,
         %{
           "database_id" => database.id,
           "driver" => database.driver,
           "host" => host,
           "port" => port,
           "database_name" => database.database_name,
           "username" => database.username,
           "password" => database.password,
           "auth_database" => database.auth_database,
           "config" => database.config || %{},
           "storage" => storage_options(database),
           "points" => points(database, key || "", granularity, timeline),
           "timeout_seconds" => max(1, div(timeout_ms, 1_000))
         }}
    end
  end

  defp points(%Database{driver: "redis"} = database, key, granularity, timeline) do
    storage = storage_options(database)
    prefix = storage["prefix"]
    separator = storage["separator"]

    Enum.map(timeline, fn at ->
      redis_key =
        Key.new(key: key, granularity: granularity, at: at)
        |> Key.set_prefix(prefix)
        |> Key.join(separator)

      %{"at" => DateTime.to_iso8601(at), "redis_key" => redis_key}
    end)
  end

  defp points(database, key, granularity, timeline) do
    storage = storage_options(database)
    joined_identifier = storage["joined_identifier"]

    Enum.map(timeline, fn at ->
      identifier =
        Key.new(key: key, granularity: granularity, at: at)
        |> Key.identifier(storage["separator"], joined_identifier)
        |> stringify_identifier()

      %{"at" => DateTime.to_iso8601(at), "identifier" => identifier}
    end)
  end

  defp stringify_identifier(identifier) do
    Map.new(identifier, fn {key, value} -> {to_string(key), serialize_identifier_value(value)} end)
  end

  defp serialize_identifier_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp serialize_identifier_value(value), do: value

  defp storage_options(%Database{driver: "mongo", config: config}) do
    config = config || %{}

    %{
      "collection_name" => config["collection_name"] || "trifle_stats",
      "separator" => "::",
      "joined_identifier" => normalize_joined_identifier(config)
    }
  end

  defp storage_options(%Database{driver: driver, config: config})
       when driver in ["postgres", "mysql"] do
    config = config || %{}

    %{
      "table_name" => config["table_name"] || "trifle_stats",
      "separator" => "::",
      "joined_identifier" => normalize_joined_identifier(config)
    }
  end

  defp storage_options(%Database{driver: "redis", config: config}) do
    config = config || %{}

    %{
      "prefix" => config["prefix"] || "trifle_stats",
      "separator" => "::"
    }
  end

  defp storage_options(_database), do: %{}

  defp normalize_joined_identifier(config) do
    case Map.get(config, "joined_identifiers") || Map.get(config, "joined_identifier") || "full" do
      nil -> nil
      "separated" -> nil
      :separated -> nil
      "full" -> "full"
      :full -> "full"
      "partial" -> "partial"
      :partial -> "partial"
      _ -> "full"
    end
  end

  defp connector_for_database(%{organization_connector_id: nil}) do
    {:error, "Private Connector is not selected"}
  end

  defp connector_for_database(database) do
    case Repo.get_by(OrganizationConnector,
           id: database.organization_connector_id,
           organization_id: database.organization_id
         ) do
      %OrganizationConnector{} = connector -> {:ok, connector}
      nil -> {:error, "Private Connector is not available"}
    end
  end

  defp await_connector_completion(connector, job, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    await_connector_job(connector.id, job.id, deadline)
  end

  defp await_connector_job(connector_id, job_id, deadline) do
    case Repo.get_by(ConnectorJob, id: job_id, organization_connector_id: connector_id) do
      %ConnectorJob{status: status} = job when status in ["ok", "error"] ->
        {:ok, job}

      %ConnectorJob{} = job ->
        if System.monotonic_time(:millisecond) >= deadline do
          mark_job_timed_out(job)
          {:error, "Timed out waiting for Private Connector to query stats"}
        else
          Process.sleep(250)
          await_connector_job(connector_id, job_id, deadline)
        end

      nil ->
        {:error, "Private Connector stats query job was not found"}
    end
  end

  defp mark_job_timed_out(job) do
    job
    |> ConnectorJob.changeset(%{
      status: "error",
      error: "Timed out waiting for Private Connector to query stats",
      payload: scrub_payload(job.payload),
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  defp connector_stats_result(%ConnectorJob{status: "ok", result: %{} = result}) do
    with {:ok, at} <- decode_timeline(result["at"] || result[:at]),
         values when is_list(values) <- result["values"] || result[:values],
         true <- length(at) == length(values) do
      {:ok, %{at: at, values: Enum.map(values, &normalize_value/1)}}
    else
      false -> {:error, "Private Connector returned mismatched stats timeline and values"}
      _ -> {:error, "Private Connector returned an invalid stats result"}
    end
  end

  defp connector_stats_result(%ConnectorJob{status: "error", error: error})
       when is_binary(error) and error != "" do
    {:error, error}
  end

  defp connector_stats_result(%ConnectorJob{status: "error"}) do
    {:error, "Private Connector stats query failed"}
  end

  defp connector_stats_result(_job),
    do: {:error, "Private Connector returned an invalid stats result"}

  defp discard_connector_job_result(%ConnectorJob{} = job) do
    job
    |> ConnectorJob.changeset(%{result: %{"discarded" => true}})
    |> Repo.update()
  end

  defp decode_timeline(values) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case decode_datetime(value) do
        {:ok, datetime} -> {:cont, {:ok, [datetime | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp decode_timeline(_values), do: {:error, :invalid_timeline}

  defp decode_datetime(%DateTime{} = value), do: {:ok, value}

  defp decode_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_datetime(_value), do: {:error, :invalid_datetime}

  defp normalize_value(value) when is_map(value), do: value
  defp normalize_value(_value), do: %{}

  defp normalize_timeout(value) when is_integer(value) and value > 0 do
    min(value, @max_timeout_ms)
  end

  defp normalize_timeout(_value), do: @default_timeout_ms

  defp scrub_payload(value) when is_map(value) do
    Map.new(value, fn
      {key, _value} when key in ["password", :password] -> {key, "[redacted]"}
      {key, nested} -> {key, scrub_payload(nested)}
    end)
  end

  defp scrub_payload(values) when is_list(values), do: Enum.map(values, &scrub_payload/1)
  defp scrub_payload(value), do: value

  defp default_port("postgres"), do: 5432
  defp default_port("mysql"), do: 3306
  defp default_port("mongo"), do: 27017
  defp default_port("redis"), do: 6379
  defp default_port(_driver), do: nil
end
