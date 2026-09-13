defmodule Trifle.Traces.Seed do
  @moduledoc "Synthetic development traces written through the real tracing and storage APIs."

  alias Trifle.{Stats, Traces}
  alias Trifle.Traces.{Configuration, Driver}

  @paths [
    "checkout/validate/cart",
    "checkout/validate/address",
    "checkout/submit/payment/authorize",
    "checkout/submit/confirmation",
    "orders/fetch/suppliers",
    "orders/fetch/catalog",
    "orders/import/products",
    "orders/import/stock",
    "orders/import/Demo.Nested.Worker",
    "reports/export/csv",
    "reports/export/json",
    "media/render/screenshot",
    "media/render/video"
  ]
  @lorem "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. "
  @defaults [
    count: 100,
    seed: 42,
    min_lines: 20,
    max_lines: 80,
    large_every: 5,
    multipart_every: 10,
    max_delay_ms: 50
  ]

  def options!(options) do
    unknown = Keyword.keys(options) -- (Keyword.keys(@defaults) ++ [:screenshot, :video])
    if unknown != [], do: raise(ArgumentError, "Unknown seed options: #{inspect(unknown)}")

    options = Keyword.merge(@defaults, options)

    for {key, low, high} <- [
          {:count, 1, 10_000},
          {:seed, 0, 2_147_483_647},
          {:min_lines, 0, 1_000},
          {:max_lines, 0, 1_000},
          {:large_every, 1, 10_000},
          {:multipart_every, 1, 10_000},
          {:max_delay_ms, 0, 1_000}
        ] do
      value = options[key]

      unless is_integer(value) and value >= low and value <= high,
        do:
          raise(
            ArgumentError,
            "--#{String.replace(to_string(key), "_", "-")} must be #{low}..#{high}"
          )
    end

    if options[:min_lines] > options[:max_lines],
      do: raise(ArgumentError, "--min-lines cannot exceed --max-lines")

    for {key, filename, extensions} <- [
          {:screenshot, "checkout.png", ~w(.png .jpg .jpeg .webp)},
          {:video, "fulfillment.webm", ~w(.webm .mp4)}
        ],
        reduce: options do
      acc ->
        path = acc[key] || Application.app_dir(:trifle, "priv/trace_seeds/#{filename}")

        unless is_binary(path) and File.regular?(path) and
                 String.downcase(Path.extname(path)) in extensions,
               do:
                 raise(
                   ArgumentError,
                   "--#{key} must be an existing #{Enum.join(extensions, "/")} file"
                 )

        if File.stat!(path).size > 20 * 1024 * 1024,
          do:
            raise(
              ArgumentError,
              "--#{key} must be at most 20 MiB (it is copied into each matching media trace)"
            )

        Keyword.put(acc, key, Path.expand(path))
    end
  end

  def run(%Configuration{} = config, stats_config, options \\ [], progress \\ fn _, _ -> :ok end) do
    options = options!(options)
    validate_storage!(config)
    stats_config = %{stats_config | buffer_enabled: false, storage: nil}
    :rand.seed(:exsss, {options[:seed] + 1, options[:seed] + 2, options[:seed] + 3})
    run_id = Traces.Ref.generate() |> String.downcase()

    # Seed-local overrides: never change the app's serializer, callbacks, or bump interval.
    config = %{
      config
      | serializer: Traces.Serializer.Json,
        callbacks: %{liftoff: [], bump: [], wrapup: []},
        context: %{synthetic: true, seed_run: run_id},
        error_handler: fn error, _, _ -> {:raise, error} end
    }

    summary = %{count: 0, parts: 0, entries: 0, attachments: 0, samples: [], run_id: run_id}

    Enum.reduce(1..options[:count], summary, fn index, summary ->
      record = seed_trace(config, run_id, index, options)
      # Read cumulative persisted counters rather than the already-drained tracer buffer.
      track_stats!(record, stats_config)
      progress.(index, record)

      %{
        summary
        | count: index,
          parts: summary.parts + record.parts,
          entries: summary.entries + record.length,
          attachments: summary.attachments + record.counters.types.media,
          samples:
            Enum.take(summary.samples ++ [%{key: record.key, reference: record.reference}], 5)
      }
    end)
  end

  defp validate_storage!(config) do
    if !config.persistence or
         Driver.module(config.index_driver) == Traces.Driver.Index.Null or
         Driver.module(config.data_driver) == Traces.Driver.Data.Null do
      raise ArgumentError, "Trace index and payload storage must both be configured"
    end

    unless Driver.call(config.index_driver, :capabilities)[:update],
      do: raise(ArgumentError, "Seed traces need an index driver supporting live updates")

    if config.payload_size_limit > 10 * 1024 * 1024,
      do: raise(ArgumentError, "Seed payload threshold must be at most 10 MiB")
  end

  defp seed_trace(config, run_id, index, options) do
    showcase? = rem(index - 1, options[:large_every]) == 0
    multipart? = rem(index - 1, options[:multipart_every]) == 0
    state = Enum.at([:success, :warning, :error, :success, :success], rem(index - 1, 5))
    key = "seed/" <> Enum.at(@paths, rem(index - 1, length(@paths)))
    lines = random_between(options[:min_lines], options[:max_lines])
    arguments = seed_arguments(index)

    context = %{
      seed: options[:seed],
      sequence: index,
      scenario: %{
        showcase: showcase?,
        multipart: multipart?,
        outcome: state,
        text_rows: lines,
        media: media_kind(key)
      }
    }

    config = %{
      config
      | bump_every: if(multipart?, do: 0, else: 3_600),
        context: Map.merge(config.context, context)
    }

    {:ok, tracer} = Traces.start_tracer(key, config: config, mode: :live, meta: arguments)

    try do
      final =
        Traces.attach(tracer, fn ->
          for tag <- [
                "seed",
                "seed-run:#{run_id}",
                "scenario:#{Path.basename(key)}",
                "outcome:#{state}"
              ],
              do: Traces.tag(tag)

          if showcase? do
            Traces.tag("showcase")
            for n <- 1..120, do: Traces.tag("demo-resource:#{n}")
          end

          if multipart?, do: Traces.tag("multipart")

          Traces.trace("Synthetic scenario — no external requests or real job execution",
            head: true
          )

          Traces.trace("Validate request", [head: true], fn ->
            Traces.trace("Request arguments", fn -> arguments end)
            valid = Traces.trace("Required fields present?", fn -> true end)

            Traces.trace("Load and transform demo records", fn ->
              for n <- 1..3 do
                Traces.trace("Record #{n}/3", [head: true], fn ->
                  Traces.trace("Check inventory", fn ->
                    %{sku: "DEMO-#{n}", available: random_between(1, 100)}
                  end)

                  %{id: n, accepted: valid, amount: random_between(10, 999) / 10}
                end)
              end
            end)

            %{valid: valid, records: 3}
          end)

          Traces.trace("Simulated upstream response", [head: true], fn ->
            Traces.trace("GET https://api.example.invalid/demo (simulation only)", state: :debug)

            %{
              status: 200,
              headers: %{content_type: "application/json"},
              body: %{items: [1, 2, 3]}
            }
          end)

          # Sibling execution branches return nested maps/lists as well, rather
          # than just one deep chain of blocks.
          branching_result("root", if(showcase?, do: 3, else: 2))

          Traces.trace("Diagnostic output", head: true)

          if lines > 0 do
            for n <- 1..lines do
              message = "Row #{n}/#{lines}: " <> lorem(random_between(80, 360))
              Traces.trace(message, state: if(rem(n, 7) == 0, do: :debug, else: :success))
            end
          end

          Traces.trace(
            "Multiline diagnostic\n  Unicode: 東京 · café · مرحبا\n  Literal markup: <script>demo only</script>",
            state: :debug
          )

          Traces.trace("Empty result", fn -> nil end)
          Traces.trace("Empty collection", fn -> [] end)

          if showcase? do
            Traces.trace("Large inline result below the offload threshold", fn ->
              %{description: lorem(min(div(config.payload_size_limit, 4), 8_192)), accepted: true}
            end)

            Traces.trace("Oversized block result — automatically extracted", fn ->
              %{
                body: lorem(config.payload_size_limit + 4_096),
                content_type: "text/plain",
                synthetic: true
              }
            end)

            Traces.trace("Oversized text row: " <> lorem(config.payload_size_limit + 1_024),
              state: :debug
            )
          end

          # Media belongs to its named scenario, independently of how often we
          # generate large text/results for offloading and pagination tests.
          trace_media(media_kind(key), options)

          delay = random_between(0, options[:max_delay_ms])
          if delay > 0, do: Process.sleep(delay)
          outcome(state)
          Traces.trace("Final result", fn -> %{state: state, processed: 3, synthetic: true} end)
          Traces.wrapup()
        end)

      Traces.find(final.reference, config: config) || raise("Seed trace was not persisted")
    after
      if Process.alive?(tracer),
        do: DynamicSupervisor.terminate_child(Traces.TracerSupervisor, tracer)
    end
  end

  defp seed_arguments(index) do
    order_id = "DEMO-#{1_000 + index}"
    region = Enum.random(~w(eu us apac))

    case rem(index - 1, 4) do
      0 -> %{order_id: order_id, region: region, dry_run: true}
      1 -> [order_id, region, true]
      2 -> Map.merge(%{order_id: order_id, region: region, dry_run: true}, nested_arguments())
      3 -> [order_id, Map.put(nested_arguments(), :region, region), false, nil, 0]
    end
  end

  defp nested_arguments do
    %{
      order: %{
        items: [%{sku: "DEMO-1", quantity: 2, options: %{sizes: ["S", "M"], gift: false}}],
        delivery: %{address: %{city: "東京", instructions: lorem(1_200)}}
      },
      options: %{currency: "USD", retries: 0, optional: nil},
      diagnostics: %{
        request_id: String.duplicate("demo-segment-", 40),
        notes: "café · مرحبا · <script>demo only</script>"
      }
    }
  end

  defp media_kind("seed/media/render/screenshot"), do: :screenshot
  defp media_kind("seed/media/render/video"), do: :video
  defp media_kind(_key), do: nil

  defp trace_media(nil, _options), do: :ok

  defp trace_media(kind, options) do
    path = options[kind]
    basename = if kind == :screenshot, do: "checkout", else: "fulfillment"
    name = basename <> String.downcase(Path.extname(path))

    Traces.trace("Render synthetic #{kind}", [head: true], fn ->
      Traces.trace("Render output", fn ->
        %{kind: kind, filename: name, bytes: File.stat!(path).size, synthetic: true}
      end)

      Traces.artifact(name, path)
      %{artifact: name, stored: true}
    end)
  end

  defp outcome(:success), do: Traces.success()

  defp outcome(:warning) do
    Traces.trace("Demo upstream timed out; falling back to cached data", state: :warning)
    Traces.warn()
  end

  defp outcome(:error) do
    Traces.trace("Demo import rejected: invalid SKU", state: :error)

    Traces.trace("Synthetic backtrace\n  Demo.Import.validate/1\n  Demo.Import.perform/1",
      state: :debug
    )

    Traces.fail()
  end

  defp branching_result(name, remaining) do
    Traces.trace("Structured branch: #{name}", [head: true], fn ->
      if remaining == 0 do
        %{
          branch: name,
          result: %{
            inventory: %{available: random_between(1, 50), locations: ["demo-east", "demo-west"]},
            pricing: %{
              amount: random_between(10, 500),
              currency: "USD",
              adjustments: [%{type: "demo", amount: -2}]
            },
            validation: %{passed: true, warnings: [], optional: nil}
          }
        }
      else
        children =
          for n <- 1..random_between(2, 4), into: %{} do
            key = "branch_#{n}"
            {key, branching_result("#{name}/#{key}", remaining - 1)}
          end

        %{
          branch: name,
          children: children,
          summary: %{branches: map_size(children), accepted: true}
        }
      end
    end)
  end

  defp track_stats!(record, config) do
    duration = %{count: 1, sum: record.duration, square: record.duration * record.duration}

    values = %{
      count: 1,
      states: %{to_string(record.state) => 1},
      duration: Map.put(duration, :states, %{to_string(record.state) => duration}),
      entries: %{count: record.length},
      attachments: %{count: record.counters.types.media}
    }

    case Stats.track(record.key, record.last_at, values, config) do
      {:error, reason} -> raise "Seed trace persisted but Stats write failed: #{inspect(reason)}"
      _ -> :ok
    end
  end

  defp random_between(low, high), do: low + :rand.uniform(high - low + 1) - 1

  defp lorem(bytes),
    do: binary_part(String.duplicate(@lorem, div(bytes, byte_size(@lorem)) + 1), 0, bytes)
end
