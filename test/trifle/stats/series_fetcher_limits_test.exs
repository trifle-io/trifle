defmodule Trifle.Stats.SeriesFetcherLimitsTest do
  # Changes the global point limit.
  use Trifle.DataCase, async: false

  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations
  alias Trifle.Stats.SeriesFetcher
  alias Trifle.Stats.Source

  describe "bounded_timeline/4" do
    @config %{
      time_zone: "Etc/UTC",
      time_zone_database: Tzdata.TimeZoneDatabase,
      beginning_of_week: :monday
    }

    setup do
      on_exit(fn -> Application.delete_env(:trifle, :series_max_points) end)
    end

    # The bounded walk has to produce exactly what trifle_stats will query,
    # including granularities that do not divide their parent unit.
    test "matches the trifle_stats timeline" do
      from = ~U[2026-01-01 00:00:00Z]

      for {to, granularity} <- [
            {~U[2026-01-01 06:00:00Z], "1m"},
            {~U[2026-01-03 00:00:00Z], "15m"},
            {~U[2026-01-31 00:00:00Z], "59m"},
            {~U[2026-02-01 00:00:00Z], "7h"},
            {~U[2026-03-01 12:30:00Z], "1h"},
            {~U[2027-01-01 00:00:00Z], "1d"},
            {~U[2027-01-01 00:00:00Z], "5d"},
            {~U[2027-06-01 00:00:00Z], "1w"},
            {~U[2028-01-01 00:00:00Z], "1mo"},
            {~U[2030-01-01 00:00:00Z], "1q"},
            {~U[2036-01-01 00:00:00Z], "1y"},
            {from, "1h"}
          ] do
        parser = Trifle.Stats.Nocturnal.Parser.new(granularity)

        expected =
          Trifle.Stats.Nocturnal.timeline(
            from: from,
            to: to,
            offset: parser.offset,
            unit: parser.unit,
            config: @config
          )

        assert {:ok, ^expected} = SeriesFetcher.bounded_timeline(from, to, granularity, @config),
               "timeline differs at #{granularity}"
      end
    end

    test "counts the real points of an uneven granularity, not range / bucket length" do
      from = ~U[2026-01-01 00:00:00Z]
      to = ~U[2026-01-31 00:00:00Z]

      # 30 days / 59 minutes is 733, but the timeline restarts every hour: 1441.
      Application.put_env(:trifle, :series_max_points, 1_441)
      assert {:ok, timeline} = SeriesFetcher.bounded_timeline(from, to, "59m", @config)
      assert length(timeline) == 1_441

      Application.put_env(:trifle, :series_max_points, 1_440)

      assert {:error, {:point_limit_exceeded, message}} =
               SeriesFetcher.bounded_timeline(from, to, "59m", @config)

      assert message =~ "more than 1440 data points"
    end

    test "stops walking once the limit is passed" do
      Application.put_env(:trifle, :series_max_points, 100)

      {micros, result} =
        :timer.tc(fn ->
          SeriesFetcher.bounded_timeline(
            ~U[2000-01-01 00:00:00Z],
            ~U[2026-01-01 00:00:00Z],
            "1s",
            @config
          )
        end)

      assert {:error, {:point_limit_exceeded, _}} = result
      # 26 years of seconds is 820 million points; walking them would take minutes.
      assert micros < 1_000_000
    end
  end

  describe "error_text/1" do
    test "returns reader-facing messages whatever the caller wrapped them in" do
      assert SeriesFetcher.error_text("plain") == "plain"
      assert SeriesFetcher.error_text({:point_limit_exceeded, "too many"}) == "too many"

      assert SeriesFetcher.error_text({:specific_key_failed, {:point_limit_exceeded, "too many"}}) ==
               "too many"

      assert SeriesFetcher.error_text(:econnrefused) == ":econnrefused"
    end
  end

  describe "point limit" do
    setup do
      on_exit(fn -> Application.delete_env(:trifle, :series_max_points) end)

      database = database_fixture()
      {:ok, _} = Organizations.setup_database(database)
      %{source: Source.from_database(database)}
    end

    test "a request over the limit is refused before the source is queried", %{source: source} do
      Application.put_env(:trifle, :series_max_points, 1_000)

      assert {:error, {:point_limit_exceeded, message}} =
               SeriesFetcher.fetch_series(
                 source,
                 "any.key",
                 ~U[2026-01-01 00:00:00Z],
                 ~U[2026-02-01 00:00:00Z],
                 "1m",
                 []
               )

      assert message =~ "more than 1000 data points"
      assert message =~ "shorter timeframe or a coarser granularity"
    end

    test "a request within the limit is served", %{source: source} do
      Application.put_env(:trifle, :series_max_points, 1_000)

      assert {:ok, _} =
               SeriesFetcher.fetch_series(
                 source,
                 "any.key",
                 ~U[2026-01-01 00:00:00Z],
                 ~U[2026-01-01 06:00:00Z],
                 "1m",
                 []
               )
    end

    test "an uneven granularity that passes the limit is refused", %{source: source} do
      Application.put_env(:trifle, :series_max_points, 1_000)

      assert {:error, {:point_limit_exceeded, _}} =
               SeriesFetcher.fetch_series(
                 source,
                 "any.key",
                 ~U[2026-01-01 00:00:00Z],
                 ~U[2026-01-31 00:00:00Z],
                 "59m",
                 []
               )
    end

    test "the default limit allows a month at one-minute granularity" do
      assert {:ok, timeline} =
               SeriesFetcher.bounded_timeline(
                 ~U[2026-01-01 00:00:00Z],
                 ~U[2026-02-01 00:00:00Z],
                 "1m",
                 %{
                   time_zone: "Etc/UTC",
                   time_zone_database: Tzdata.TimeZoneDatabase,
                   beginning_of_week: :monday
                 }
               )

      assert length(timeline) == 44_641
    end
  end
end
