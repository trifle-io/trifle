defmodule Trifle.Stats.Tabler do
  @doc """
  Flattens a stats series into `%{at: timestamps, paths: sorted_paths,
  values: %{{path, at} => value}}`. Single pass over the series; `:at`
  comes back newest-first (reverse input order), matching how callers
  consume it.
  """
  def tabulize(%{at: at, values: values}) do
    {at_acc, paths, value_map} = do_tabulize(at, values, [], MapSet.new(), %{})

    %{
      at: at_acc,
      paths: paths |> MapSet.to_list() |> Enum.sort(),
      values: value_map
    }
  end

  defp do_tabulize([], _values, at_acc, paths, value_map), do: {at_acc, paths, value_map}

  defp do_tabulize([a | at_rest], values, at_acc, paths, value_map) do
    {value, values_rest} =
      case values do
        [v | rest] -> {v, rest}
        [] -> {nil, []}
      end

    packed = Trifle.Stats.Packer.pack(value)

    paths = Enum.reduce(Map.keys(packed), paths, &MapSet.put(&2, &1))

    value_map =
      Enum.reduce(packed, value_map, fn {k, v}, acc ->
        Map.put(acc, {k, a}, v)
      end)

    do_tabulize(at_rest, values_rest, [a | at_acc], paths, value_map)
  end

  def seriesize(stats) do
    tabulized = Trifle.Stats.Tabler.tabulize(stats)

    Enum.reduce(tabulized[:paths], %{}, fn path, acc ->
      data =
        Enum.map(tabulized[:at], fn a ->
          v = tabulized[:values][{path, a}]
          # Convert to naive datetime to preserve the local time representation  
          naive = DateTime.to_naive(a)
          # Create UTC datetime with the same time values to display correctly in charts
          utc_dt = DateTime.from_naive!(naive, "Etc/UTC")
          [DateTime.to_unix(utc_dt) * 1000, v || 0]
        end)

      Map.merge(acc, %{path => data})
    end)
  end

  def sample do
    project = Trifle.Organizations.get_project!(6)
    config = Trifle.Organizations.Project.stats_config(project)
    now = DateTime.utc_now()

    Trifle.Stats.values(
      "tester",
      DateTime.add(now, -14, :day, config.time_zone_database),
      now,
      :day,
      config
    )
  end
end
