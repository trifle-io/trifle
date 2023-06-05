defmodule Trifle.Stats.Operations.Timeseries.Increment do
  def perform(key, at, values, config \\ nil) do
    config.driver.__struct__.inc(
      Enum.map(config.ranges, fn range -> key_for(key, range, at, config) end),
      values, config.driver
    )
  end

  def key_for(key, range, at, config) do
    {:ok, at} = apply(Trifle.Stats.Nocturnal, range, [at, config])

    [key, range, DateTime.to_unix(at)]
  end
end
