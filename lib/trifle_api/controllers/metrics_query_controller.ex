defmodule TrifleApi.MetricsQueryController do
  use TrifleApi, :controller

  alias Trifle.Metrics.Query
  alias Trifle.Stats.Nocturnal.Parser
  alias Trifle.Stats.Source

  plug(TrifleApi.Plugs.AuthenticateBySourceToken, %{mode: :read} when action in [:create])

  def create(%{assigns: %{current_source: %Source{} = source}} = conn, params) do
    with {:ok, key} <- fetch_param(params, "key"),
         {:ok, from} <- parse_datetime(params["from"]),
         {:ok, to} <- parse_datetime(params["to"]),
         {:ok, granularity} <- parse_granularity(source, params["granularity"]),
         {:ok, mode} <- parse_mode(params),
         {:ok, slices} <- Query.resolve_slices(params),
         {:ok, payload} <- run_query(mode, source, key, from, to, granularity, params, slices) do
      render(conn, "show.json", payload: payload)
    else
      {:error, :invalid_params} ->
        render_error(conn, :bad_request, "400.json")

      {:error, :invalid_granularity} ->
        render_error(conn, :bad_request, "400.json")

      {:error, %{} = error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("error.json", error: error)

      {:error, _reason} ->
        render_error(conn, :internal_server_error, "500.json")
    end
  end

  defp run_query(:aggregate, source, key, from, to, granularity, params, slices) do
    with {:ok, value_path} <- fetch_param(params, "value_path"),
         {:ok, {aggregator_name, aggregator_fun}} <-
           Query.resolve_aggregator(params["aggregator"]),
         {:ok, result} <-
           Source.fetch_series(
             source,
             key,
             from,
             to,
             granularity,
             progressive: false
           ),
         paths = Query.normalize_paths(value_path),
         {:ok, resolved_path} <- Query.ensure_single_path(paths),
         {:ok, resolved_path} <- Query.ensure_no_wildcards(resolved_path),
         available <- Query.available_paths(result.series),
         :ok <- Query.ensure_paths_exist([resolved_path], available),
         {:ok, values} <-
           Query.aggregate_series(result.series, aggregator_fun, resolved_path, slices) do
      if values == [] do
        {:error,
         %{
           status: "error",
           error: "No data available for path #{resolved_path} in the selected timeframe.",
           available_paths: available
         }}
      else
        table = Query.tabularize_series(result.series, only_paths: [resolved_path])

        payload =
          %{
            status: "ok",
            aggregator: aggregator_name,
            metric_key: key,
            value_path: resolved_path,
            slices: slices,
            values: values,
            count: length(values),
            timeframe: timeframe_payload(from, to, granularity),
            available_paths: available,
            matched_paths: [resolved_path]
          }
          |> Query.maybe_put_primary_value(slices)
          |> maybe_put_table(table)

        {:ok, payload}
      end
    end
  end

  defp run_query(:timeline, source, key, from, to, granularity, params, slices) do
    with {:ok, value_path} <- fetch_param(params, "value_path"),
         {:ok, result} <-
           Source.fetch_series(
             source,
             key,
             from,
             to,
             granularity,
             progressive: false
           ),
         paths = Query.normalize_paths(value_path),
         {:ok, resolved_path} <- Query.ensure_single_path(paths),
         {:ok, resolved_path} <- Query.ensure_no_wildcards(resolved_path),
         available <- Query.available_paths(result.series),
         :ok <- Query.ensure_paths_exist([resolved_path], available),
         table_all <- Query.tabularize_series(result.series),
         {:ok, formatted, matched_paths} <-
           Query.format_timeline_result(result.series, resolved_path, slices),
         matched_paths <- Enum.filter(matched_paths, &Enum.member?(available, &1)),
         true <- matched_paths != [] || {:missing_timeline, available, resolved_path} do
      table = Query.subset_table(table_all, matched_paths)

      payload =
        %{
          status: "ok",
          formatter: "timeline",
          metric_key: key,
          value_path: resolved_path,
          slices: slices,
          timeframe: timeframe_payload(from, to, granularity),
          result: formatted,
          available_paths: available,
          matched_paths: matched_paths
        }
        |> maybe_put_table(table)

      {:ok, payload}
    else
      {:missing_timeline, available, missing_path} ->
        {:error,
         %{
           status: "error",
           error: "No matching data found for path #{missing_path} in the selected timeframe.",
           available_paths: available
         }}
    end
  end

  defp run_query(:category, source, key, from, to, granularity, params, slices) do
    with {:ok, value_path} <- fetch_param(params, "value_path"),
         {:ok, result} <-
           Source.fetch_series(
             source,
             key,
             from,
             to,
             granularity,
             progressive: false
           ),
         paths = Query.normalize_paths(value_path),
         {:ok, resolved_path} <- Query.ensure_single_path(paths),
         {:ok, resolved_path} <- Query.ensure_no_wildcards(resolved_path),
         available <- Query.available_paths(result.series),
         {:ok, formatted, matched_paths} <-
           Query.format_category_result(result.series, resolved_path, slices),
         matched_paths <- Enum.filter(matched_paths, &Enum.member?(available, &1)),
         true <- matched_paths != [] || {:missing_categories, available, resolved_path},
         table_all <- Query.tabularize_series(result.series) do
      table = Query.subset_table(table_all, matched_paths)

      payload =
        %{
          status: "ok",
          formatter: "category",
          metric_key: key,
          value_path: resolved_path,
          slices: slices,
          timeframe: timeframe_payload(from, to, granularity),
          result: formatted,
          available_paths: available,
          matched_paths: matched_paths
        }
        |> maybe_put_table(table)

      {:ok, payload}
    else
      {:missing_categories, available, missing_path} ->
        {:error,
         %{
           status: "error",
           error: "No matching data found for path #{missing_path} in the selected timeframe.",
           available_paths: available
         }}
    end
  end

  defp parse_mode(params) do
    params
    |> Map.get("mode")
    |> case do
      nil -> Map.get(params, "format")
      value -> value
    end
    |> normalize_mode()
  end

  defp normalize_mode(nil), do: {:error, :invalid_params}

  defp normalize_mode(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "aggregate" -> {:ok, :aggregate}
      "timeline" -> {:ok, :timeline}
      "category" -> {:ok, :category}
      _ -> {:error, :invalid_params}
    end
  end

  defp normalize_mode(value) when is_atom(value), do: normalize_mode(Atom.to_string(value))
  defp normalize_mode(_), do: {:error, :invalid_params}

  defp timeframe_payload(from, to, granularity) do
    %{
      from: DateTime.to_iso8601(from),
      to: DateTime.to_iso8601(to),
      label: "custom",
      granularity: granularity
    }
  end

  defp maybe_put_table(payload, nil), do: payload
  defp maybe_put_table(payload, table), do: Map.put(payload, :table, table)

  defp fetch_param(params, key) do
    case Map.get(params, key) do
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

  defp render_error(conn, status, template) do
    conn
    |> put_status(status)
    |> put_view(TrifleApi.ErrorJSON)
    |> render(template, %{})
  end
end
