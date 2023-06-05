defmodule Trifle.Stats.Packer do
  def pack(hash, prefix \\ nil) do
    Enum.reduce(hash, %{}, fn({k, v}, acc) ->
      key = [prefix, k] |> Enum.reject(&is_nil/1) |> Enum.join(".")
      if is_map(v) do
        Map.merge(acc, pack(v, key))
      else
        Map.merge(acc, %{key => v})
      end
    end)
  end

  def unpack(hash) do
    Enum.reduce(hash, %{}, fn({key, v}, acc) ->
      deep_merge(
        acc,
        String.split(key, ".") |> Enum.reverse |> Enum.reduce(v, fn k, a -> %{k => a} end)
      )
    end)
  end

  def deep_merge(this_hash, other_hash) do
    Map.merge(this_hash, other_hash, &deep_merge!/3)
  end

  defp deep_merge!(_key, this_hash = %{}, other_hash = %{}) do
    deep_merge(this_hash, other_hash)
  end

  defp deep_merge!(_key, _this_hash, other_hash) do
    other_hash
  end
end
