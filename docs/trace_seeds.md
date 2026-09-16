# Development trace seeds

Run from the app repository with the development containers already running:

```sh
docker compose exec -T app mix seed_traces --count 100
```

Select **internal observability** in Traces and filter the path to `seed`.
Every record has a `seed` tag and a unique `seed-run:<id>` tag, printed at the end
of the command. Each run adds new records; it never replaces or deletes existing
traces. Normal trace retention applies. Nothing is added to installation seeds.

The task is development-only, uses the existing internal Postgres index and Stats
configuration, and uploads payloads to the configured S3/MinIO or File driver.
Internal observability and payload storage must be enabled. It does not configure
new sources, run migrations, invoke real jobs, or make simulated API requests.
Its own BEAM process has Oban queues/plugins and the HTTP server disabled; the
already-running app is unaffected. No media-generation tools are needed to seed.

## Data included

- Thirteen stable paths under four branches (`checkout`, `orders`, `reports`,
  `media`), including deeper prefixes such as `seed/checkout/submit/payment/authorize`
  and a dotted worker name, with success/warning/error outcomes and debug entries.
- Request arguments, context, booleans, maps, arrays, empty results and nested
  blocks with actual serialized block return values. Structured trees have 2–4
  sibling branches per level, nested maps/lists at the leaves, and up to four
  execution levels (root plus three descendants), not just a single deep chain.
- Arguments are stored directly in `meta`, matching Ruby and Oban integrations.
  Every four traces cycle through a short named-argument map, a short positional
  array, a deeply nested map with long values, and a positional array with nested
  and long values. The long examples exercise the header's **Expand all** control.
  Seed/run/sequence/scenario details live separately in `context`. The request
  arguments block returns the same values displayed below the trace ID.
- Random amounts/inventory and variable-length lorem ipsum rows, multiline and
  Unicode messages, and harmless literal HTML for escaping checks.
- Showcase traces with 120 extra tags, large inline results, an oversized block
  result and an oversized text row.
- Scenario-specific media: `seed/media/render/screenshot` always attaches the
  screenshot; `seed/media/render/video` always attaches the video. Other paths
  do not receive image/video attachments. Oversized text can still become `.txt`
  attachments on any showcase path, including orders.
- Frequent-flush examples exercise sequential automatic loading of up to 100
  parts, with **Load next part** for any remaining parts. Use `--min-lines 100
  --max-lines 200` to reliably generate examples exceeding that limit.

Only terminal trace states are seeded. We do not leave orphaned running tracers.
All timestamps reflect the actual seeding run; there is no historical backfill.
Durations are measured by the real tracer, including persistence time and a small
random simulated delay. Count/duration/entry/attachment Stats come from the final
persisted record and use the activity chart's existing schema. No fabricated
counts or duration samples, and no duplicate normal wrapup metrics.

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `--count` | `100` | Number of traces, from 1 to 10,000 |
| `--seed` | `42` | Repeatable randomized scenario data; IDs/timestamps still differ |
| `--min-lines` | `20` | Minimum extra text rows per trace |
| `--max-lines` | `80` | Maximum extra text rows; at most 1,000 |
| `--large-every` | `5` | Every Nth trace includes large results and extra tags |
| `--multipart-every` | `10` | Every Nth trace flushes frequently |
| `--max-delay-ms` | `50` | Maximum extra simulated delay per trace; zero disables it |
| `--screenshot` | bundled PNG | Optional PNG/JPEG/WebP path inside the container |
| `--video` | bundled WebM | Optional WebM/MP4 path inside the container |

The first trace always includes showcase and multipart features. Use `--count 13`
or more to cover the complete path cycle, including both media scenarios. Media
selection does not depend on `--large-every`. Line limits apply to extra text
rows, not the structural/block rows. Media files are copied into each matching
trace, so use small fixtures (custom files are limited to 20 MiB each).
Seeding is sequential and can issue many Postgres/S3 writes for multipart traces.

```sh
# More and longer traces, with a different repeatable random seed:
docker compose exec -T app mix seed_traces --count 500 --seed 123 --min-lines 50 --max-lines 200

# Every trace includes oversized results and many parts; media stays on its own paths:
docker compose exec -T app mix seed_traces --count 13 --large-every 1 --multipart-every 1
```

Errors stop the run rather than printing success. Already-written traces/objects
remain; a failure is not an atomic rollback across Postgres and object storage.

## Row offloading

The library and app default is **100 KiB = 102,400 bytes**, configured by
`payload_size_limit` (`Trifle.Observability`'s `traces_payload_size_limit`). This is
the UTF-8 byte size of each **serialized row message**, not a part/file threshold.
The comparison is strictly `>`: a row equal to the limit stays inline.

The dispatcher writes an oversized message as `part_row_<reference>.txt`, changes
the entry type to `media`, and records its original byte size. This applies to
both ordinary text and serialized `raw` block results. Explicit PNG/WebM artifacts
are media regardless of their size.

The default Inspect serializer truncates large strings/collections before the
dispatcher sees them. These seed traces therefore use the JSON serializer locally
so oversized return values really get offloaded. Generated large bodies exceed
the **configured** threshold; the task prints that threshold before starting and
rejects thresholds above 10 MiB to avoid unexpectedly huge seed allocations.
Regular application tracing configuration is unchanged.

## Bundled media

`priv/trace_seeds/checkout.png` is a 960×760 synthetic checkout screenshot.
`priv/trace_seeds/fulfillment.webm` is a short 800×160 VP8 fulfillment animation.
Both are original, generated from `fixtures.html`, contain no customer data, and
require no external download. The video was decoded successfully in Chromium.

The optional `generate_fixtures.mjs` maintenance script regenerates them with a
local headless Chromium debugging endpoint. Chromium must see this directory at
`/fixtures`; Node 20 needs `--experimental-websocket`. For example, with that
browser reachable on the development network:

```sh
docker compose exec -T app node --experimental-websocket priv/trace_seeds/generate_fixtures.mjs http://chrome:9222
```

The seed task itself only reads the bundled binaries. No UI/inline-preview
behavior is changed by this script.

## Viewing media

Image and video attachments appear inline by default in loaded trace entries,
with file sizes and download links. Images are lazy-loaded near the viewport;
videos load metadata and offer native playback controls, without autoplay.
Hide/show controls release the media when hidden. Failed loads offer Retry and
Download. PNG, JPEG, GIF, WebP, MP4 and WebM are supported; video decoding depends
on the browser's codec support. SVG/HTML and unrecognized formats are not embedded.
Text offloads keep the existing bounded **Read text** preview.

Inline delivery uses the same authenticated, organization-scoped entry lookup as
downloads, with private/no-store responses and validated media types. Video byte
ranges support seeking, but payload drivers still read/decompress the complete
stored artifact for each request; this is not storage-level streaming.
Copying trace text still excludes all attachment bodies.
