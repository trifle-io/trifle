defmodule Trifle.DatabasePools.Limits do
  @moduledoc """
  Bounds for per-tenant connection pools.

  `pool_size` comes from a database's user-editable config. It is parsed
  defensively (junk falls back to the default instead of crashing the pool
  supervisor) and clamped, so one tenant cannot make the server open hundreds of
  connections.

      config :trifle, :max_tenant_pool_size, 10
  """

  @default_pool_size 5
  @default_max_pool_size 10

  def default_pool_size, do: @default_pool_size

  def max_pool_size do
    case Application.get_env(:trifle, :max_tenant_pool_size, @default_max_pool_size) do
      value when is_integer(value) and value > 0 -> value
      _ -> @default_max_pool_size
    end
  end

  @doc "Pool size to use for a configured value: an integer in `1..max_pool_size()`."
  def pool_size(value, default \\ @default_pool_size) do
    value
    |> parse(default)
    |> min(max_pool_size())
  end

  # Anything that is not a positive whole number falls back to the default.
  defp parse(value, _default) when is_integer(value) and value > 0, do: value

  defp parse(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} when number > 0 -> number
      _ -> default
    end
  end

  defp parse(_value, default), do: default
end
