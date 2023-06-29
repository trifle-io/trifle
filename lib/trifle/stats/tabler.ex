defmodule Trifle.Stats.Tabler do
  def tabulize(%{at: at, values: values} = stats) do
    Enum.with_index(at)
    |> Enum.reduce(%{at: [], paths: [], values: %{}}, fn({a, i}, acc) ->
      packed = Trifle.Stats.Packer.pack(Enum.at(values, i))
      acc = zip(acc, a, packed)
    end)
  end

  def zip(acc, at, packed) do
    %{
      at: [at | acc[:at]],
      paths: [Map.keys(packed) | acc[:paths]] |> List.flatten |> Enum.uniq |> Enum.sort,
      values: Map.merge(
        acc[:values],
        Map.new(packed, fn({k, v}) ->
          {{k, at}, v}
        end)
      )
    }
  end
end
