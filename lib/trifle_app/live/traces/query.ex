defmodule TrifleApp.TracesLive.Query do
  @moduledoc false
  alias Trifle.Organizations.Database
  alias Trifle.Stats.Source
  alias TrifleApp.TimeframeParsing

  @fields ~w(source_id reference detail path state tags tag_mode duration_min timeframe granularity from to)
  @range_fields ~w(source_id timeframe from to)
  @list_fields ~w(reference tags tag_mode duration_min)

  def list_params(params), do: Map.take(params, @list_fields)

  def list_filters_active?(params) do
    tags(params["tags"]) != [] or not is_nil(blank(params["duration_min"])) or
      not is_nil(blank(params["reference"]))
  end

  def params(params) do
    params
    |> Map.take(@fields)
    |> Enum.filter(fn {_, value} -> is_binary(value) and byte_size(value) <= 2048 end)
    |> Map.new()
    |> normalize_detail()
  end

  def parse(params, source, previous \\ nil) do
    granularities =
      case source.record.granularities do
        list when is_list(list) and list != [] -> list
        _ -> Database.default_granularities()
      end

    config = %Trifle.Stats.Configuration{
      time_zone: Source.time_zone(source),
      beginning_of_week: Database.beginning_of_week_for(source.record) || :monday
    }

    default = Source.default_granularity(source) || "1h"
    granularity = params["granularity"] || default
    granularity = if granularity in granularities, do: granularity, else: hd(granularities)
    timeframe = params["timeframe"] || Source.default_timeframe(source) || "1d"

    with {:ok, from, to, fixed} <- range(params, timeframe, config, previous),
         true <- DateTime.compare(from, to) == :lt,
         {:ok, duration} <- duration(params["duration_min"]) do
      reference = blank(params["reference"])

      {:ok,
       %{
         params: params,
         config: config,
         granularities: granularities,
         granularity: granularity,
         timeframe: timeframe,
         from: from,
         to: to,
         fixed: fixed,
         path: blank(params["path"]),
         reference: reference,
         detail_expanded: not is_nil(reference) and params["detail"] == "expanded",
         filters:
           [
             from: from,
             to: to,
             segment: blank(params["path"]),
             state: blank(params["state"]),
             duration_min: duration,
             tags: %{tag_mode(params) => tags(params["tags"])}
           ]
           |> Enum.reject(fn {_, value} -> is_nil(value) end)
       }}
    else
      _ ->
        {:error,
         "Check the timeframe and minimum duration (a non-negative number of milliseconds)."}
    end
  end

  defp normalize_detail(params) do
    if params["detail"] == "expanded" and not is_nil(blank(params["reference"])) do
      params
    else
      Map.delete(params, "detail")
    end
  end

  defp range(params, timeframe, config, previous) do
    cond do
      previous && Map.take(previous.params, @range_fields) == Map.take(params, @range_fields) ->
        {:ok, previous.from, previous.to, previous.fixed}

      params["from"] not in [nil, ""] or params["to"] not in [nil, ""] ->
        with {:ok, from} <- date(params["from"], config.time_zone),
             {:ok, to} <- date(params["to"], config.time_zone),
             do: {:ok, from, to, true}

      true ->
        case TimeframeParsing.parse_smart_timeframe(timeframe, config) do
          {:ok, from, to, _, fixed} -> {:ok, from, to, fixed}
          _ -> {:error, :invalid}
        end
    end
  end

  defp date(value, zone) when is_binary(value), do: TimeframeParsing.parse_date(value, zone)
  defp date(_, _), do: {:error, :invalid}
  defp duration(value) when value in [nil, ""], do: {:ok, nil}

  defp duration(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> {:ok, number}
      _ -> {:error, :invalid}
    end
  end

  defp tag_mode(%{"tag_mode" => "all"}), do: :all
  defp tag_mode(_), do: :any

  defp tags(value),
    do:
      (value || "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

  defp blank(value) do
    case String.trim(value || "") do
      "" -> nil
      value -> value
    end
  end

  def url(params), do: "/traces?" <> URI.encode_query(params)

  def path_url(params, path), do: filtered_url(params, %{"path" => path})
  def tag_url(params, tag), do: filtered_url(params, %{"tags" => tag, "tag_mode" => "any"})

  defp filtered_url(params, filters) do
    params
    |> Map.drop(["reference", "detail"])
    |> Map.merge(filters)
    |> url()
  end
end
