defmodule Trifle.Stats.Configuration do
  defstruct driver: nil, ranges: [:minute, :hour, :day, :week, :month, :quarter, :year], separator: "::", time_zone: "GMT", time_zone_database: nil, beginning_of_week: :monday

  def configure(driver, time_zone \\ "GMT", time_zone_database \\ nil, beginning_of_week \\ :monday, track_ranges \\ [:minute, :hour, :day, :week, :month, :quarter, :year], separator \\ "::") do
    %Trifle.Stats.Configuration{
      driver: driver,
      time_zone: time_zone,
      time_zone_database: time_zone_database,
      beginning_of_week: beginning_of_week,
      ranges: MapSet.intersection(MapSet.new(track_ranges), MapSet.new([:minute, :hour, :day, :week, :month, :quarter, :year])),
      separator: separator
    }
  end

  def set_time_zone(%Trifle.Stats.Configuration{} = configuration, time_zone) do
    %{configuration | time_zone: time_zone}
  end

  def set_time_zone_database(%Trifle.Stats.Configuration{} = configuration, time_zone_database) do
    %{configuration | time_zone_database: time_zone_database}
  end

  def set_beginning_of_week(%Trifle.Stats.Configuration{} = configuration, beginning_of_week) do
    %{configuration | beginning_of_week: beginning_of_week}
  end

  def set_ranges(%Trifle.Stats.Configuration{} = configuration, track_ranges) do
    %{configuration | ranges: MapSet.intersection(MapSet.new(track_ranges), MapSet.new([:minute, :hour, :day, :week, :month, :quarter, :year]))}
  end

  def set_separator(%Trifle.Stats.Configuration{} = configuration, separator) do
    %{configuration | separator: separator}
  end
end
