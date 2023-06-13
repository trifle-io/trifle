# Trifle.Stats

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `trifle_stats` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:trifle_stats, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/trifle_stats>.

## configuration
{:ok, connection} = Mongo.start_link(url: "mongodb://mongo:27017/trifle")
driver = Trifle.Stats.Driver.Mongo.new(connection)
config = Trifle.Stats.Configuration.configure(driver, [:hour, :day, :month, :year], "::", "Europe/Bratislava", Tzdata.TimeZoneDatabase, :monday)

Trifle.Stats.track("test", DateTime.utc_now(), %{duration: 34, count: 1}, config)


{:ok, now} = DateTime.now(config.time_zone, config.time_zone_database)
Trifle.Stats.Nocturnal.change(now, config)

Trifle.Stats.Nocturnal.minute(now, config)





{:ok, connection} = Mongo.start_link(url: "mongodb://mongo:27017/trifle")
driver = Trifle.Stats.Driver.Mongo.new(connection)
config = Trifle.Stats.Configuration.configure(driver, [:hour, :day, :month, :year], "::", "Europe/Bratislava", Tzdata.TimeZoneDatabase, :monday)

{:ok, now} = DateTime.now(config.time_zone, config.time_zone_database)
prev = DateTime.add(now, -1, :day, config.time_zone_database)

Trifle.Stats.values("test", prev, now, :day, config)



Trifle.Stats.Nocturnal.timeline(prev, now, :day, config)
