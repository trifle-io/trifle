defmodule Mix.Tasks.SeedTraces do
  use Mix.Task

  @shortdoc "Seed rich synthetic traces into development observability storage"
  @moduledoc """
  Generate development traces with nested blocks, return values, long text, real
  automatic offloading, screenshot/video attachments, and multipart payloads.

      mix seed_traces --count 100
      mix seed_traces --count 500 --seed 123 --min-lines 50 --max-lines 200

  Uses the app's configured internal Postgres index/Stats and S3 or File storage.
  Development only. Adds data; never deletes existing traces or runs real jobs.

  Options:

    * `--count`: Number of traces, 1..10000 (default 100)
    * `--seed`: Reproducible random data (default 42)
    * `--min-lines`: Minimum extra text rows per trace (default 20)
    * `--max-lines`: Maximum extra text rows per trace (default 80)
    * `--large-every`: Showcase frequency: large results and extra tags (default 5)
    * `--multipart-every`: Frequent-flush trace frequency (default 10)
    * `--max-delay-ms`: Maximum simulated delay per trace (default 50)
    * `--screenshot`: Optional PNG/JPEG/WebP path inside the container
    * `--video`: Optional WebM/MP4 path inside the container

  The first trace always includes showcase and multipart features. Parts are
  produced by the real tracer (seed-local bump_every=0 for multipart examples).
  Media is scenario-specific: media/render/screenshot always includes the image,
  and media/render/video always includes the video, regardless of --large-every.
  Use --count 13 or more to cover all paths, including both media scenarios.
  All timestamps are current; this does not backfill historical activity.
  See docs/trace_seeds.md for storage, threshold, and fixture details.
  """

  def run(args) do
    if Mix.env() != :dev, do: Mix.raise("seed_traces is development-only; use MIX_ENV=dev")

    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          count: :integer,
          seed: :integer,
          min_lines: :integer,
          max_lines: :integer,
          large_every: :integer,
          multipart_every: :integer,
          max_delay_ms: :integer,
          screenshot: :string,
          video: :string
        ]
      )

    if rest != [] or invalid != [], do: Mix.raise("Invalid options. See mix help seed_traces")
    Mix.Task.run("app.config")
    opts = Trifle.Traces.Seed.options!(opts)

    # This command is not an additional job runner or HTTP server.
    Application.put_env(
      :trifle,
      Oban,
      Application.fetch_env!(:trifle, Oban)
      |> Keyword.merge(queues: false, plugins: false, peer: false)
    )

    Application.put_env(
      :trifle,
      TrifleWeb.Endpoint,
      Application.fetch_env!(:trifle, TrifleWeb.Endpoint) |> Keyword.put(:server, false)
    )

    Mix.Task.run("app.start")

    unless Trifle.Observability.enabled?(),
      do: Mix.raise("Enable internal observability (TRIFLE_OBSERVABILITY_ENABLED=true) first")

    config = Trifle.Traces.configuration()
    stats = Trifle.Stats.Configuration.get_global()
    Mix.shell().info("Seeding #{opts[:count]} traces into internal observability (seed/…).")

    Mix.shell().info(
      "Row offload threshold: #{config.payload_size_limit} bytes; seed serializer: JSON."
    )

    summary =
      without_query_logs(fn ->
        Trifle.Traces.Seed.run(config, stats, opts, fn index, _record ->
          if rem(index, 10) == 0 or index == opts[:count],
            do: Mix.shell().info("Seeded #{index}/#{opts[:count]} traces")
        end)
      end)

    Mix.shell().info(
      "Done: #{summary.count} traces, #{summary.parts} parts, #{summary.entries} entries, #{summary.attachments} attachments."
    )

    Mix.shell().info(
      "In Traces, select internal observability; filter path=seed or tag=seed-run:#{summary.run_id}."
    )

    for sample <- summary.samples, do: Mix.shell().info("  #{sample.key} — #{sample.reference}")
  end

  defp without_query_logs(fun) do
    level = Logger.level()
    if level == :debug, do: Logger.configure(level: :info)

    try do
      fun.()
    after
      Logger.configure(level: level)
    end
  end
end
