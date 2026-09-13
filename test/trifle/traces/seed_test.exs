defmodule Trifle.Traces.SeedTest do
  use ExUnit.Case, async: true
  require Phoenix.LiveViewTest

  @endpoint TrifleWeb.Endpoint

  alias Trifle.{Stats, Traces}
  alias Trifle.Traces.{Configuration, Seed}
  alias Trifle.Traces.Driver.Data.Memory, as: MemoryData
  alias Trifle.Traces.Driver.Index.Memory, as: MemoryIndex

  setup do
    conn = start_supervised!({Exqlite, database: ":memory:"})
    :ok = Stats.Driver.Sqlite.setup!(conn, "seed_metrics")

    stats =
      Stats.Configuration.configure(Stats.Driver.Sqlite.new(conn, "seed_metrics"),
        time_zone: "Etc/UTC",
        track_granularities: ["1h"],
        buffer_enabled: false
      )

    config = Configuration.new(index_driver: MemoryIndex.new(), data_driver: MemoryData.new())
    %{config: config, stats: stats}
  end

  test "seeds exactly X real traces with nested blocks, states, metadata and cumulative stats",
       ctx do
    original_config = Traces.configuration()

    summary =
      Seed.run(ctx.config, ctx.stats, count: 13, min_lines: 2, max_lines: 2, max_delay_ms: 0)

    assert summary.count == 13
    assert length(summary.samples) == 5
    assert Traces.configuration() == original_config

    records =
      Traces.search(config: ctx.config, tags: %{all: ["seed-run:#{summary.run_id}"]}, limit: 20).traces

    assert length(records) == 13
    assert MapSet.new(Enum.map(records, & &1.state)) == MapSet.new([:success, :warning, :error])
    assert Enum.all?(records, &(String.starts_with?(&1.key, "seed/") && &1.context.synthetic))
    assert Enum.all?(records, &(&1.context.seed_run == summary.run_id))
    assert Enum.any?(records, &(&1.key == "seed/orders/import/Demo.Nested.Worker"))
    assert Enum.any?(records, &(&1.key == "seed/checkout/submit/payment/authorize"))

    assert MapSet.new(Enum.map(records, &(String.split(&1.key, "/") |> Enum.at(1)))) ==
             MapSet.new(~w(checkout orders reports media))

    assert summary.entries == Enum.sum(Enum.map(records, & &1.length))
    assert summary.parts == Enum.sum(Enum.map(records, & &1.parts))
    assert summary.attachments == Enum.sum(Enum.map(records, & &1.counters.types.media))

    for record <- records do
      entries = Traces.payload(record, config: ctx.config)
      assert record.length == length(entries)
      assert record.counters.max_level >= 3
      assert Enum.any?(entries, &(&1.type == :head))
      assert Enum.any?(entries, &(&1.type == :raw && String.contains?(&1.message, "accepted")))
      assert Enum.any?(entries, &(&1.state == :debug && String.contains?(&1.message, "東京")))
      assert Enum.any?(entries, &(&1.type == :raw && &1.message == "↳ null"))
      assert Enum.sum(Map.values(record.counters.states)) == record.length
      assert Enum.sum(Map.values(record.counters.types)) == record.length

      %{values: [values]} =
        Stats.values(record.key, record.first_at, record.last_at, "1h", ctx.stats,
          skip_blanks: true
        )

      assert values["count"] == 1
      assert values["states"] == %{to_string(record.state) => 1}
      assert values["entries"]["count"] == record.length
      assert values["duration"]["count"] == 1
      assert values["duration"]["sum"] == record.duration
      assert values["duration"]["square"] == record.duration * record.duration
      assert values["duration"]["states"][to_string(record.state)]["sum"] == record.duration
    end

    now = DateTime.utc_now()

    %{values: [catalog]} =
      Stats.values("__system__key__", DateTime.add(now, -60), now, "1h", ctx.stats,
        skip_blanks: true
      )

    assert Enum.sum(Map.values(catalog["keys"])) == 13
  end

  test "showcase really offloads oversized text and block results without unrelated media",
       ctx do
    summary =
      Seed.run(ctx.config, ctx.stats, count: 1, min_lines: 0, max_lines: 0, max_delay_ms: 0)

    record = Traces.find(hd(summary.samples).reference, config: ctx.config)
    entries = Traces.payload(record, config: ctx.config)
    assert record.parts > 10
    assert length(record.tags) >= 120
    assert "showcase" in record.tags
    assert "multipart" in record.tags
    media = Enum.filter(entries, &(&1.type == :media))
    assert length(media) == 2
    offloaded = Enum.filter(media, &String.starts_with?(&1.message, "part_row_"))
    assert length(offloaded) == 2

    bodies =
      for entry <- offloaded do
        body = Traces.read_artifact(record, entry.message, config: ctx.config)
        assert byte_size(body) == entry.size
        assert entry.size > ctx.config.payload_size_limit
        assert body =~ "Lorem ipsum"
        body
      end

    assert Enum.any?(bodies, &String.starts_with?(&1, "↳ {"))
    assert Enum.any?(bodies, &String.starts_with?(&1, "Oversized text row:"))
    assert Enum.any?(entries, &(&1.type == :raw && byte_size(&1.message) > 8_000))

    root =
      entries
      |> Enum.filter(&(&1.type == :raw))
      |> Enum.map(&Jason.decode!(String.replace_prefix(&1.message, "↳ ", "")))
      |> Enum.find(&(is_map(&1) && &1["branch"] == "root"))

    assert_branching_tree(root, 3)
  end

  test "media matches scenario paths on every cycle, independently of showcase frequency", ctx do
    for frequency <- [1, 10_000] do
      summary =
        Seed.run(ctx.config, ctx.stats,
          count: 26,
          large_every: frequency,
          min_lines: 0,
          max_lines: 0,
          max_delay_ms: 0
        )

      records =
        Traces.search(
          config: ctx.config,
          tags: %{all: ["seed-run:#{summary.run_id}"]},
          limit: 100
        ).traces

      assert length(records) == 26

      for record <- records do
        media =
          Traces.payload(record, config: ctx.config)
          |> Enum.filter(&(&1.type == :media))
          |> Enum.reject(&String.starts_with?(&1.message, "part_row_"))

        case record.key do
          "seed/media/render/screenshot" ->
            assert [%{message: "checkout.png"}] = media
            assert record.context.scenario.media == :screenshot

            assert <<137, 80, 78, 71, 13, 10, 26, 10, _::binary>> =
                     Traces.read_artifact(record, "checkout.png", config: ctx.config)

          "seed/media/render/video" ->
            assert [%{message: "fulfillment.webm"}] = media
            assert record.context.scenario.media == :video

            assert <<0x1A, 0x45, 0xDF, 0xA3, _::binary>> =
                     Traces.read_artifact(record, "fulfillment.webm", config: ctx.config)

            assert Traces.read_artifact(record, "fulfillment.webm", config: ctx.config) =~ "V_VP8"

          _ ->
            assert media == []
            assert record.context.scenario.media == nil
        end
      end
    end
  end

  test "seeds short and long positional/named arguments directly in meta, with scenario in context",
       ctx do
    summary =
      Seed.run(ctx.config, ctx.stats, count: 4, min_lines: 0, max_lines: 0, max_delay_ms: 0)

    records = Enum.map(summary.samples, &Traces.find(&1.reference, config: ctx.config))
    [short_map, short_array, long_map, long_array] = records

    assert %{order_id: "DEMO-1001", region: _, dry_run: true} = short_map.meta
    assert ["DEMO-1002", _, true] = short_array.meta

    assert %{order_id: "DEMO-1003", order: order, options: options, diagnostics: diagnostics} =
             long_map.meta

    assert [
             "DEMO-1004",
             %{order: ^order, options: ^options, diagnostics: ^diagnostics},
             false,
             nil,
             0
           ] = long_array.meta

    assert [%{options: %{sizes: ["S", "M"], gift: false}}] = order.items
    assert order.delivery.address.city == "東京"
    assert byte_size(order.delivery.address.instructions) == 1_200
    assert %{retries: 0, optional: nil} = options

    for {record, index} <- Enum.with_index(records, 1) do
      assert record.context.synthetic
      assert record.context.seed_run == summary.run_id
      assert record.context.seed == 42
      assert record.context.sequence == index
      assert record.context.scenario.media == nil
      refute Map.has_key?(record.context, :args)

      if is_map(record.meta) do
        for key <- [:args, :synthetic, :seed_run, :seed, :sequence, :scenario] do
          refute Map.has_key?(record.meta, key)
        end
      end

      # The request-arguments block returns exactly the same data as the header.
      assert Enum.any?(Traces.payload(record, config: ctx.config), fn entry ->
               entry.type == :raw && entry.message == "↳ " <> Jason.encode!(record.meta)
             end)

      doc =
        Phoenix.LiveViewTest.render_component(&TrifleApp.Components.Traces.arguments/1,
          id: "arguments-#{index}",
          meta: record.meta
        )
        |> Floki.parse_document!()

      if index <= 2 do
        assert String.length(Jason.encode!(record.meta)) <= 240
        assert Floki.find(doc, "details") == []
      else
        assert String.length(Jason.encode!(record.meta)) > 240
        assert Floki.find(doc, "details[open]") == []
        assert Floki.find(doc, "[data-arguments-expand]") != []

        assert Floki.find(doc, "[data-arguments-full]") |> Floki.text() |> Jason.decode!() ==
                 record.meta |> Jason.encode!() |> Jason.decode!()
      end
    end
  end

  test "ordinary traces stay compact and use the configured offload threshold", ctx do
    config = %{ctx.config | payload_size_limit: 16 * 1024}
    summary = Seed.run(config, ctx.stats, count: 2, min_lines: 1, max_lines: 1, max_delay_ms: 0)
    [first, second] = Enum.map(summary.samples, &Traces.find(&1.reference, config: config))
    assert first.parts > 10
    assert second.parts == 2
    assert second.counters.types.media == 0

    assert Enum.count(
             Traces.payload(first, config: config),
             &(&1.type == :media && Map.get(&1, :size, 0) > config.payload_size_limit)
           ) >= 2
  end

  test "reruns add new references and run tags without overwriting previous data", ctx do
    options = [count: 1, min_lines: 0, max_lines: 0, max_delay_ms: 0]
    first = Seed.run(ctx.config, ctx.stats, options)
    second = Seed.run(ctx.config, ctx.stats, options)
    refute first.run_id == second.run_id
    refute hd(first.samples).reference == hd(second.samples).reference
    assert length(Traces.search(config: ctx.config, tags: %{all: ["seed"]}).traces) == 2
  end

  test "rejects invalid counts, unsafe sizes and missing fixtures before writing", ctx do
    for options <- [
          [count: 0],
          [count: -1],
          [count: 10_001],
          [large_every: 0],
          [max_lines: 1_001],
          [min_lines: 5, max_lines: 1],
          [seed: -1],
          [max_delay_ms: 1_001],
          [screenshot: "/does/not/exist.png"],
          [bogus: true]
        ] do
      assert_raise ArgumentError, fn -> Seed.run(ctx.config, ctx.stats, options) end
    end

    assert Traces.search(config: ctx.config).traces == []

    assert_raise ArgumentError, ~r/storage must both be configured/, fn ->
      Seed.run(Configuration.new(), ctx.stats, count: 1)
    end

    assert_raise ArgumentError, ~r/at most 10 MiB/, fn ->
      Seed.run(%{ctx.config | payload_size_limit: 11 * 1024 * 1024}, ctx.stats, count: 1)
    end
  end

  test "seed task is unavailable outside development" do
    assert_raise Mix.Error, ~r/development-only/, fn -> Mix.Tasks.SeedTraces.run([]) end
  end

  defp assert_branching_tree(node, 0) do
    assert is_list(node["result"]["inventory"]["locations"])
    assert [%{"type" => "demo"}] = node["result"]["pricing"]["adjustments"]
    assert node["result"]["validation"]["passed"]
  end

  defp assert_branching_tree(node, depth) do
    assert map_size(node["children"]) in 2..4
    assert node["summary"]["branches"] == map_size(node["children"])
    Enum.each(Map.values(node["children"]), &assert_branching_tree(&1, depth - 1))
  end
end
