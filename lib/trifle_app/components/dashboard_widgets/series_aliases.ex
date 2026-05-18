defmodule TrifleApp.Components.DashboardWidgets.SeriesAliases do
  @moduledoc false

  @raw_text_key "__series_aliases_text"
  @error_key "__series_aliases_error"

  def raw_text_key, do: @raw_text_key
  def error_key, do: @error_key

  def normalize(value)

  def normalize(value) when is_map(value) do
    value
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      with key when is_binary(key) and key != "" <- normalize_string(key),
           value when is_binary(value) and value != "" <- normalize_string(value) do
        Map.put(acc, key, value)
      else
        _ -> acc
      end
    end)
  end

  def normalize(nil), do: %{}

  def normalize(value) when is_binary(value) do
    case parse_text(value) do
      {:ok, aliases} -> aliases
      {:error, _message} -> %{}
    end
  end

  def normalize(_value), do: %{}

  def parse_text(nil), do: {:ok, %{}}
  def parse_text(value) when is_map(value), do: {:ok, normalize(value)}

  def parse_text(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:ok, %{}}
    else
      case Jason.decode(trimmed) do
        {:ok, decoded} when is_map(decoded) ->
          {:ok, normalize(decoded)}

        {:ok, _decoded} ->
          {:error, "Aliases must be a JSON object."}

        {:error, _error} ->
          {:error, "Aliases must be valid JSON."}
      end
    end
  end

  def parse_text(_value), do: {:ok, %{}}

  def aliases_map(widget_or_value) when is_map(widget_or_value) do
    widget_or_value
    |> Map.get("series_aliases", Map.get(widget_or_value, :series_aliases, %{}))
    |> normalize()
  end

  def aliases_map(value), do: normalize(value)

  def active?(widget_or_value), do: map_size(aliases_map(widget_or_value)) > 0

  def aliases_text(widget_or_value) when is_map(widget_or_value) do
    case Map.get(widget_or_value, @raw_text_key) do
      raw when is_binary(raw) ->
        raw

      _ ->
        widget_or_value
        |> aliases_map()
        |> format_aliases_text()
    end
  end

  def aliases_text(_value), do: ""

  def aliases_error(widget_or_value) when is_map(widget_or_value) do
    case Map.get(widget_or_value, @error_key) do
      error when is_binary(error) and error != "" -> error
      _ -> nil
    end
  end

  def aliases_error(_widget_or_value), do: nil

  def lookup(aliases, candidates) when is_map(aliases) do
    candidates
    |> List.wrap()
    |> Enum.find_value(fn candidate ->
      normalized = normalize_string(candidate)

      cond do
        is_nil(normalized) ->
          nil

        Map.has_key?(aliases, normalized) ->
          Map.get(aliases, normalized)

        true ->
          leaf = leaf_name(normalized)
          Map.get(aliases, leaf)
      end
    end)
  end

  def lookup(_aliases, _candidates), do: nil

  def put_aliases_from_param(widget, params, source_widget) do
    case fetch_param(params, "series_aliases") do
      {:ok, value} ->
        case parse_text(value) do
          {:ok, aliases} ->
            widget
            |> Map.put("series_aliases", aliases)
            |> Map.delete(@raw_text_key)
            |> Map.delete(@error_key)

          {:error, message} ->
            widget
            |> Map.put("series_aliases", aliases_map(source_widget))
            |> Map.put(@raw_text_key, to_string(value))
            |> Map.put(@error_key, message)
        end

      :error ->
        Map.put(widget, "series_aliases", aliases_map(source_widget))
    end
  end

  def drop_internal_fields(widget) when is_map(widget) do
    widget
    |> Map.delete(@raw_text_key)
    |> Map.delete(@error_key)
  end

  def drop_internal_fields(widget), do: widget

  defp fetch_param(params, key) when is_map(params) do
    cond do
      Map.has_key?(params, key) -> {:ok, Map.get(params, key)}
      Map.has_key?(params, "#{key}[]") -> {:ok, Map.get(params, "#{key}[]")}
      true -> :error
    end
  end

  defp fetch_param(_params, _key), do: :error

  defp normalize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_string(value) when is_float(value), do: :erlang.float_to_binary(value)
  defp normalize_string(value) when is_boolean(value), do: to_string(value)
  defp normalize_string(_value), do: nil

  defp format_aliases_text(aliases) when map_size(aliases) == 0, do: ""
  defp format_aliases_text(aliases), do: Jason.encode!(aliases, pretty: true)

  defp leaf_name(name) do
    name
    |> String.split(".")
    |> List.last()
    |> case do
      nil -> name
      value -> value
    end
  end
end
