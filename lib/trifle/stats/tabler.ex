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

  def seriesize(stats) do
    tabulized = Trifle.Stats.Tabler.tabulize(stats)
    Enum.reduce(tabulized[:paths], %{}, fn(path, acc) ->
      data = Enum.map(tabulized[:at], fn(a) ->
        v = tabulized[:values][{path, a}]
        [DateTime.to_unix(a) * 1000, (v || 0)]
      end)
      Map.merge(acc, %{path => data})
    end)
  end

  def sample do
    project = Trifle.Organizations.get_project!(6)
    config = Trifle.Organizations.Project.stats_config(project)
    now = DateTime.utc_now()
    stats = Trifle.Stats.values("tester", DateTime.add(now, -14, :day, config.time_zone_database), now, :day, config)
  end
end
