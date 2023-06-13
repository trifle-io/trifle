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
end
