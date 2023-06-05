defmodule Trifle.Stats.Nocturnal do
  def days_into_week, do: %{monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6, sunday: 7}

  def timeline(from, to, range, config) do
    {:ok, from} = apply(Trifle.Stats.Nocturnal, range, [from, config])
    {:ok, to} = apply(Trifle.Stats.Nocturnal, range, [to, config])

    timeline = Stream.unfold(from, fn at ->
      {:ok, next} = next(at, range, config)

      case DateTime.compare(next, to) do
        :lt -> {next, next}
        :eq -> {next, next}
        _ -> nil
      end
    end) |> Enum.to_list()

    [from] ++ timeline
  end

  def next(at, range, config) do
    {:ok, at} = apply(Trifle.Stats.Nocturnal, :"next_#{range}", [at, config])
  end

  def change(at, config, year \\ nil, month \\ nil, day \\ nil, hour \\ nil, minute \\ nil, second \\ 0) do
    with {:ok, date} <- Date.new(year || at.year, month || at.month, day || at.day),
         {:ok, time} <- Time.new(hour || at.hour, minute || at.minute, second || at.second)
    do
      DateTime.new(date, time, config.time_zone, config.time_zone_database)
    else
      err -> err
    end
  end

  def minute(at, config) do
    change(at, config)
  end

  def next_minute(at, config) do
    Trifle.Stats.Nocturnal.minute(
      DateTime.add(at, 1, :minute, config.time_zone_database), config
    )
  end

  def hour(at, config) do
    change(at, config, nil, nil, nil, nil, 0)
  end

  def next_hour(at, config) do
    Trifle.Stats.Nocturnal.hour(
      DateTime.add(at, 1, :hour, config.time_zone_database), config
    )
  end

  def day(at, config) do
    change(at, config, nil, nil, nil, 0, 0)
  end

  def next_day(at, config) do
    Trifle.Stats.Nocturnal.day(
      DateTime.add(at, 1, :day, config.time_zone_database), config
    )
  end

  def week(at, config) do
    at = DateTime.add(
      at, days_to_week_start(at, config), :day, config.time_zone_database
    )
    change(at, config, nil, nil, nil, 0, 0)
  end

  def next_week(at, config) do
    Trifle.Stats.Nocturnal.week(
      DateTime.add(at, 7, :day, config.time_zone_database), config
    )
  end

  def days_to_week_start(at, config) do
    beginning_of_week = days_into_week()[config.beginning_of_week]

    rem(Date.day_of_week(at) - beginning_of_week, 7)
  end

  def month(at, config) do
    change(at, config, nil, nil, 1, 0, 0)
  end

  def next_month(at, config) do
    Trifle.Stats.Nocturnal.month(
      DateTime.add(at, 31, :day, config.time_zone_database), config
    )
  end

  def quarter(at, config) do
    first_quarter_month = at.month - rem((2 + at.month), 3)
    change(at, config, nil, first_quarter_month, 1, 0, 0)
  end

  def next_quarter(at, config) do
    Trifle.Stats.Nocturnal.quarter(
      DateTime.add(at, 31 * 3, :day, config.time_zone_database), config
    )
  end

  def year(at, config) do
    change(at, config, nil, 1, 1, 0, 0)
  end

  def next_year(at, config) do
    Trifle.Stats.Nocturnal.year(
      DateTime.add(at, 366, :day, config.time_zone_database), config
    )
  end
end
