defmodule Trifle.Metrics do
  @moduledoc false

  alias Trifle.Stats.Source

  def fetch_series(source, key, from, to, granularity, opts \\ []) do
    Source.fetch_series(source, key, from, to, granularity, opts)
  end

  def track(key, at, values, stats_config) do
    Trifle.Stats.track(key, at, values, stats_config)
  end
end
