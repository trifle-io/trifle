defmodule Trifle.Stats.Operations.Timeseries.Values do
  def perform(key, from, to, range, config \\ nil) do
    timeline = Trifle.Stats.Nocturnal.timeline(from, to, range, config)

    %{
      at: timeline,
      values: config.driver.__struct__.get(
        Enum.map(timeline, fn at -> [key, range, DateTime.to_unix(at)] end),
        config.driver
      )
    }
  end
end
