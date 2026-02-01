defmodule TrifleApi.NumberNormalizer do
  @moduledoc false

  alias Decimal, as: D

  def normalize(%D{} = decimal), do: D.to_float(decimal)
  def normalize(value) when is_binary(value) do
    case D.parse(value) do
      {decimal, ""} -> D.to_float(decimal)
      _ -> value
    end
  end
  def normalize(%DateTime{} = dt), do: dt
  def normalize(%NaiveDateTime{} = ndt), do: ndt

  def normalize(%{} = map) when not is_struct(map) do
    map
    |> Enum.map(fn {key, value} -> {key, normalize(value)} end)
    |> Map.new()
  end

  def normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  def normalize(other), do: other
end
