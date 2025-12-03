defmodule Trifle.Stats.Transponder.Expression do
  @moduledoc """
  Expression-based transponder.

  Accepts a list of paths, auto-assigns variables a, b, c... in order, and
  evaluates an arithmetic expression to produce a value at `response_path`.
  """

  alias Trifle.Stats.Transponder.ExpressionEngine
  alias Trifle.Stats.Precision

  def transform(series, paths, expression, response_path, _slices \\ 1) do
    trimmed_response_path = trim_path(response_path)

    with {:ok, normalized_paths} <- normalize_paths(paths),
         :ok <- ensure_response_path(trimmed_response_path),
         {:ok, ast} <- ExpressionEngine.parse(expression, normalized_paths) do
      apply_expression(series, normalized_paths, ast, trimmed_response_path)
    end
  end

  def validate(paths, expression, response_path) do
    with :ok <- ensure_response_path(response_path),
         :ok <- ExpressionEngine.validate(paths, expression) do
      :ok
    end
  end

  defp normalize_paths(paths) when is_list(paths) do
    cleaned =
      paths
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if Enum.empty?(cleaned) do
      {:error, %{message: "At least one path is required."}}
    else
      {:ok, cleaned}
    end
  end

  defp normalize_paths(_), do: {:error, %{message: "Paths must be a list."}}

  defp ensure_response_path(path) when is_binary(path) do
    case String.trim(path) do
      "" -> {:error, %{message: "Response path is required."}}
      _ -> :ok
    end
  end

  defp ensure_response_path(_), do: {:error, %{message: "Response path is required."}}

  defp apply_expression(%{at: []} = series, _paths, _ast, _response_path), do: {:ok, series}

  defp apply_expression(series, paths, ast, response_path) do
    vars = ExpressionEngine.allowed_vars(length(paths))
    response_keys = String.split(response_path, ".")

    reducer = fn value_map, {:ok, acc} ->
      env = build_env(value_map, paths, vars)

      case ExpressionEngine.evaluate(ast, env) do
        {:ok, result} ->
          case put_response(value_map, response_keys, result) do
            {:ok, updated} -> {:cont, {:ok, [updated | acc]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end

    case Enum.reduce_while(series[:values] || [], {:ok, []}, reducer) do
      {:ok, values} ->
        {:ok, Map.put(series, :values, Enum.reverse(values))}

      {:error, error} ->
        {:error, error}
    end
  end

  defp build_env(value_map, paths, vars) do
    paths
    |> Enum.zip(vars)
    |> Enum.reduce(%{}, fn {path, var}, acc ->
      keys = String.split(path, ".")
      Map.put(acc, var, get_path_value(value_map, keys))
    end)
  end

  defp put_response(value_map, response_keys, value) do
    case can_create_path?(value_map, response_keys) do
      true ->
        {:ok, put_path_value(value_map, response_keys, normalize_value(value))}

      false ->
        {:error, %{message: "Cannot write to response path #{Enum.join(response_keys, ".")}."}}
    end
  end

  defp normalize_value(%Decimal{} = decimal) do
    if Precision.enabled?(), do: decimal, else: Precision.to_float(decimal)
  end
  defp normalize_value(value), do: value

  defp trim_path(path) when is_binary(path), do: String.trim(path)
  defp trim_path(path), do: path

  # Helpers borrowed from existing transponders for path handling
  defp get_path_value(value_map, keys) do
    case get_in(value_map, keys) do
      nil ->
        atom_keys = Enum.map(keys, &String.to_atom/1)
        get_in(value_map, atom_keys)

      value ->
        value
    end
  end

  defp put_path_value(value_map, keys, value) do
    do_put_path_value(value_map, keys, value, map_uses_atom_keys?(value_map))
  end

  defp do_put_path_value(value_map, [key], value, atom_keys?) do
    Map.put(value_map, normalize_key(key, atom_keys?), value)
  end

  defp do_put_path_value(value_map, [key | rest], value, atom_keys?) do
    actual_key = normalize_key(key, atom_keys?)
    current = Map.get(value_map, actual_key)

    {nested_map, nested_atom_keys?} =
      cond do
        is_map(current) -> {current, map_uses_atom_keys?(current)}
        current == nil -> {%{}, atom_keys?}
        true -> {%{}, atom_keys?}
      end

    updated_nested = do_put_path_value(nested_map, rest, value, nested_atom_keys?)
    Map.put(value_map, actual_key, updated_nested)
  end

  defp normalize_key(key, true), do: String.to_atom(key)
  defp normalize_key(key, false), do: key

  defp map_uses_atom_keys?(value_map) when is_map(value_map) do
    keys = Map.keys(value_map)
    atom_count = Enum.count(keys, &is_atom/1)
    string_count = Enum.count(keys, &is_binary/1)
    atom_count >= string_count
  end

  defp can_create_path?(_map, [], _atom_keys?), do: true
  defp can_create_path?(_map, [_key], _atom_keys?), do: true

  defp can_create_path?(map, [key | rest], atom_keys?) do
    actual_key = if atom_keys?, do: String.to_atom(key), else: key

    case Map.get(map, actual_key) do
      nil -> true
      nested_map when is_map(nested_map) -> can_create_path?(nested_map, rest, map_uses_atom_keys?(nested_map))
      _non_map -> false
    end
  end

  defp can_create_path?(value_map, response_keys) do
    can_create_path?(value_map, response_keys, map_uses_atom_keys?(value_map))
  end
end
