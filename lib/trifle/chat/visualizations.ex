defmodule Trifle.Chat.Visualizations do
  @moduledoc false

  alias Trifle.Chat.InlineDashboard

  @spec normalize_list(term()) :: [map()]
  def normalize_list(visualizations) when is_list(visualizations) do
    visualizations
    |> Enum.map(&normalize/1)
    |> Enum.reject(&is_nil/1)
  end

  def normalize_list(_other), do: []

  @spec normalize(term()) :: map() | nil
  def normalize(%{} = visualization) do
    type =
      visualization
      |> map_get(:type)
      |> to_string()
      |> String.downcase()

    id =
      visualization
      |> map_get(:id)
      |> case do
        value when is_binary(value) and value != "" -> value
        _ -> "viz-" <> Integer.to_string(System.unique_integer([:positive]))
      end

    normalized =
      %{
        id: id,
        type: type,
        title: map_get(visualization, :title),
        dashboard: normalize_map(map_get(visualization, :dashboard)),
        source: normalize_map(map_get(visualization, :source)),
        timeframe: normalize_map(map_get(visualization, :timeframe)),
        series_snapshot: normalize_map(map_get(visualization, :series_snapshot)),
        metric_key: map_get(visualization, :metric_key),
        payload: normalize_map(map_get(visualization, :payload)),
        tool_name: map_get(visualization, :tool_name)
      }
      |> Enum.reject(fn {_key, value} ->
        value in [nil, %{}]
      end)
      |> Map.new()

    case Map.get(normalized, :type) do
      "dashboard" -> normalized
      _ -> nil
    end
  end

  def normalize(_other), do: nil

  @spec from_tool_message(map()) :: [map()]
  def from_tool_message(message) do
    content =
      map_get(message, :content)

    tool_name = map_get(message, :name)
    tool_call_id = map_get(message, :tool_call_id)

    with true <- is_binary(content),
         {:ok, payload} <- Jason.decode(content) do
      cond do
        is_map(payload["visualization"]) ->
          [
            payload["visualization"]
            |> Map.put_new("tool_name", tool_name)
            |> Map.put_new("id", tool_call_id || payload["visualization"]["id"])
            |> normalize()
          ]
          |> Enum.reject(&is_nil/1)

        true ->
          []
      end
    else
      _ -> []
    end
  end

  @spec pending_from_messages([map()]) :: [map()]
  def pending_from_messages(messages) when is_list(messages) do
    messages
    |> Enum.reverse()
    |> Enum.reduce_while([], fn message, acc ->
      role = map_get(message, :role) |> to_string()
      tool_calls = map_get(message, :tool_calls) |> List.wrap()
      content = map_get(message, :content) |> to_string() |> String.trim()

      cond do
        role == "tool" ->
          {:cont, from_tool_message(message) ++ acc}

        role == "assistant" and tool_calls != [] ->
          {:cont, acc}

        role == "assistant" and content == "" ->
          {:cont, acc}

        true ->
          {:halt, acc}
      end
    end)
  end

  def pending_from_messages(_other), do: []

  @spec has_data?(map()) :: boolean()
  def has_data?(visualization) do
    case normalize(visualization) do
      %{type: "dashboard"} = normalized ->
        InlineDashboard.has_data?(normalized)

      _ ->
        false
    end
  end

  defp normalize_map(%{} = map), do: stringify_keys(map)
  defp normalize_map(_other), do: %{}

  defp map_get(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp map_get(_map, _key), do: nil

  defp stringify_keys(value) when is_map(value) do
    value
    |> Enum.map(fn {key, inner} -> {to_string(key), stringify_keys(inner)} end)
    |> Map.new()
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
