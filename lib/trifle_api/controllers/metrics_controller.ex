defmodule TrifleApi.MetricsController do
  use TrifleApi, :controller

  alias Trifle.Exports.Series, as: SeriesExport
  alias Trifle.Stats.Nocturnal.Parser
  alias Trifle.Stats.Source

  @system_key "__system__key__"

  plug(TrifleApi.Plugs.AuthenticateBySourceToken, %{mode: :read} when action in [:index])
  plug(TrifleApi.Plugs.AuthenticateBySourceToken, %{mode: :write} when action in [:create])

  def index(%{assigns: %{current_source: %Source{} = source}} = conn, params) do
    with {:ok, key} <- fetch_optional_param(params, "key"),
         {:ok, from} <- parse_datetime(params["from"]),
         {:ok, to} <- parse_datetime(params["to"]),
         {:ok, granularity} <- parse_granularity(source, params["granularity"]),
         {:ok, result} <- fetch_series(source, key, from, to, granularity) do
      series = SeriesExport.extract_series(result.series)

      conn
      |> render("index.json", series: series)
    else
      {:error, :invalid_params} ->
        conn
        |> put_status(:bad_request)
        |> render("400.json")

      {:error, :invalid_granularity} ->
        conn
        |> put_status(:bad_request)
        |> render("400.json")

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> render("500.json")
    end
  end

  def create(%{assigns: %{current_project: current_project}} = conn, params) do
    with key when is_binary(key) and byte_size(key) > 0 <- params["key"],
         at when is_binary(at) and byte_size(at) > 0 <- params["at"],
         values when not is_nil(values) <- params["values"],
         {:ok, at, _} <- DateTime.from_iso8601(at),
         stats_config <- Trifle.Organizations.Project.stats_config(current_project) do
      Trifle.Stats.track(key, at, values, stats_config)

      conn
      |> put_status(:created)
      |> render("created.json")
    else
      nil ->
        conn
        |> put_status(:bad_request)
        |> render("400.json")

      "" ->
        conn
        |> put_status(:bad_request)
        |> render("400.json")

      {:error, :invalid_format} ->
        conn
        |> put_status(:bad_request)
        |> render("400.json")
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> render("400.json")
  end

  def health(conn, _params) do
    conn
    |> put_status(:ok)
    |> render("health.json")
  end

  defp fetch_optional_param(params, key) do
    case Map.get(params, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, :invalid_params}
          trimmed -> {:ok, trimmed}
        end

      _ ->
        {:error, :invalid_params}
    end
  end

  defp parse_datetime(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" ->
        {:error, :invalid_params}

      trimmed ->
        case DateTime.from_iso8601(trimmed) do
          {:ok, datetime, _offset} -> {:ok, datetime}
          {:error, _} -> {:error, :invalid_params}
        end
    end
  end

  defp parse_datetime(_), do: {:error, :invalid_params}

  defp parse_granularity(%Source{} = source, value) when is_binary(value) do
    granularity = String.trim(value)

    if granularity == "" do
      {:error, :invalid_granularity}
    else
      parser = Parser.new(granularity)

      if Parser.valid?(parser) and granularity_allowed?(source, granularity) do
        {:ok, granularity}
      else
        {:error, :invalid_granularity}
      end
    end
  rescue
    _ -> {:error, :invalid_granularity}
  end

  defp parse_granularity(_source, _value), do: {:error, :invalid_granularity}

  defp granularity_allowed?(%Source{} = source, granularity) do
    case Source.available_granularities(source) do
      list when is_list(list) and list != [] -> granularity in list
      _ -> true
    end
  end

  defp fetch_series(%Source{} = source, key, from, to, granularity) do
    query_key = key || @system_key
    opts = if query_key == @system_key, do: [transponders: :none], else: []

    Source.fetch_series(source, query_key, from, to, granularity, opts)
  end
end
