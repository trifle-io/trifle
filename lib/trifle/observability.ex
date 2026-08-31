defmodule Trifle.Observability do
  @moduledoc """
  Configures the application's own Trifle Stats and Trifle Traces storage.

  Trace metadata is kept in PostgreSQL. Trace payloads are written to the
  configured filesystem path, or discarded when no path is configured.
  """

  require Logger

  alias Trifle.Traces.Driver.Data.File, as: FileData
  alias Trifle.Traces.Driver.Data.Null, as: NullData
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
           config: traces_config,
           handler_id: {Trifle.Traces.Oban, :trifle_internal},
           meta: &oban_meta/1},
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
    case options |> Keyword.get(:traces_storage_path) |> normalize_path() do
      nil ->
        %NullData{}

      path ->
        driver_options = [path: path, gzip: Keyword.get(options, :traces_gzip, true)]
        :ok = FileData.setup!(driver_options)
        FileData.new(driver_options)
    end
  end

  @doc "Deletes trace indexes and filesystem payloads past their retention window."
  def cleanup! do
    if enabled?() do
      traces_config = Trifle.Traces.configuration()
      deleted = PostgresIndex.cleanup!(traces_config.index_driver)

      case traces_config.data_driver do
        %FileData{} = driver -> FileData.cleanup!(driver)
        _driver -> :ok
      end

      {:ok, deleted}
    else
      {:ok, 0}
    end
  end

  @doc false
  def oban_meta(job) do
    %{
      id: field(job, :id),
      queue: field(job, :queue),
      worker: field(job, :worker),
      attempt: field(job, :attempt)
    }
  end

  @doc false
  def trace_context(%{meta: meta}) when is_map(meta) do
    meta
    |> Map.take([:queue, :worker])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  def trace_context(_tracer), do: %{}

  @doc false
  def record_trace(tracer) do
    values = %{
      count: 1,
      states: %{to_string(tracer.state) => 1},
      entries: %{count: length(tracer.data || [])}
    }

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

  defp configure_traces do
    options = config()

    Trifle.Traces.configure(
      index_driver: PostgresIndex.new(Trifle.Repo, table_name: @traces_table),
      data_driver: trace_data_driver(options),
      bump_every: Keyword.get(options, :traces_bump_every, 15),
      payload_size_limit: Keyword.get(options, :traces_payload_size_limit, 100 * 1024),
      retention: Keyword.get(options, :traces_retention_days, 7),
      context: &trace_context/1,
      error_handler: &trace_error/3,
      on_wrapup: &record_trace/1
    )
  end

  defp config do
    Application.get_env(:trifle, __MODULE__, [])
  end

  defp metric_key(key) do
    suffix = key |> to_string() |> String.replace("/", "::")
    "internal::traces::#{suffix}"
  end

  defp field(job, key), do: Map.get(job, key, Map.get(job, to_string(key)))

  defp normalize_path(path) when path in [nil, ""], do: nil

  defp normalize_path(path) when is_binary(path) do
    case String.trim(path) do
      "" -> nil
      trimmed -> Path.expand(trimmed)
    end
  end
end
