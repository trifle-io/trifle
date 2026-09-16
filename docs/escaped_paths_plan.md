# Escaped Stats paths: implementation and release handoff

Updated: 2026-09-12. The user has committed and pushed the library implementation and follow-up corrections, without publishing releases. App and CLI integration is verified against their fetched Git dependencies with no local overrides. No commits, pushes, releases, or deployments were made by the agent.

## Accepted scope

Ordinary `a.b` still means nested `a → b`, including flat input keys. New `a\.b` means one literal `a.b` key. Literal backslashes and stars use `\\` and `\*`. Public percent sequences are literal text.

The user waived historical compatibility. All updated storage drivers use one unconditional codec. There is no source opt-in, per-record metadata, schema migration, automatic conversion, or separate storage scope. Historical percent-containing names and saved backslash paths may be interpreted differently. Upgrade all readers and writers sharing storage together.

The user controls all commits, pushes, tags, version numbers, package releases, and deployments. Pushed Git commits are explicitly approved for integration testing before releases. Final integration verification must use fetched dependencies with no local override.

## Implemented

- [x] Ruby, Elixir, Go, and JavaScript path parsing, literal rendering, wildcard classification, and shared fixtures.
- [x] Uniform segment codec: NUL → %00, double quote → %22, dollar → %24, percent → %25, star → %2A, dot → %2E, backslash → %5C. Decode exactly once.
- [x] Packers parse public input keys, encode storage fields, and return decoded literal names.
- [x] Separate decoded-tree flattening into public selectors and recursive key-escaping helpers for resubmission. Array leaf payloads stay opaque.
- [x] Buffers canonicalize equivalent input spellings before merging without reparsing literal names.
- [x] Aggregators, formatters, and transponder input/response paths use the new syntax.
- [x] Whole unescaped star segments expand in formatters. Concrete star keys render escaped. Expression transponders reject unescaped stars, including partial globs; arithmetic multiplication is unchanged.
- [x] Mongo reads decode native nested fields. SQL/Redis reads decode packed fields.
- [x] SQLite JSON paths address packed fields as single names. Double quotes are encoded uniformly because SQLite could insert quoted fields but fail to update them using native JSON paths.
- [x] PostgreSQL JSONB updates use a properly quoted single-element text array. MySQL JSON paths are bound parameters.
- [x] Automatic system key counters escape the entire metric identifier when embedding it in values. Outer metric identifiers remain opaque.
- [x] App query discovery, tables, Explore, grouping, metric-series evaluation, aliases/order, monitor paths, and JavaScript autocomplete/grouping use path helpers.
- [x] App project-scoped Mongo driver encodes partial updates, decodes reads, forwards buffered counts, and uses the current separated-identifier API. Mocked tests protect project scoping in bulk/non-bulk modes.
- [x] API/CLI single-path validation accepts escaped stars but rejects actual wildcard selectors. API drivers transport public escaping unchanged.
- [x] App dev/test local dependency override and CLI temporary Go workspace instructions.
- [x] Audit internal trace Stats callback: worker module names stay literal, without a namespace-replacement workaround or new Rails/Sidekiq integration. A later app-only follow-up removes the redundant metric prefix; see below.
- [x] New path guides and unreleased changelogs for all three Stats libraries; app API/OpenAPI/widgets, CLI/MCP, and trace callback examples updated.
- [x] Website dot-packing explanation updated with a link to the guide.

The shared specification is [stats-paths-v1.md](../../docs-trifle-io/contracts/stats-paths-v1.md). Identical JSON fixtures live in docs, Ruby, Elixir, Go, and app JavaScript tests.

## Verification actually performed

The table below records the original September 10 verification. See the September 12 integration follow-up for checks against the actual pushed dependencies.

| Area | Result |
| --- | --- |
| App | Full suite: 759 tests, zero failures. Final label changes: 118 widget/path tests, zero failures. |
| App frontend | 19 Node tests pass; Tailwind/esbuild asset build passes. |
| App custom Mongo | 14 mocked tests, including all identifier modes, bulk/non-bulk inc/set, count forwarding, scoped get and beam/scan. No real Mongo operations from these tests. |
| Elixir Stats | 244 unit/in-memory SQLite/API transport tests, zero failures, two pre-existing skipped tests. Run through the container with required OTP apps started. |
| Ruby Stats | 405 examples, zero failures, one opt-in interoperability example pending in the broad run. Includes Process, PostgreSQL, and API transport; unavailable/service-unsafe drivers excluded from that run. |
| Go Stats | Full suite passes with PostgreSQL, MongoDB, Redis, in-memory Process, miniredis, and SQLite. MySQL SQL-mock tests pass; live MySQL tests skipped. |
| CLI | Full Go suite passes against the local updated Stats library through a temporary Go workspace. |
| Cross-language storage | Ruby → Go/Elixir, Elixir → Ruby/Go, Go → Ruby/Elixir all pass on PostgreSQL with the final codec. Tests assert physical encoded keys, decoded values, cumulative increments, and unchanged system metric identifiers. |
| Docs | Five fixture copies match; 37 local links checked across 27 changed Markdown pages; OpenAPI YAML parses. Guides/navigation render as HTML and Markdown. Generated per-library llms-full output contains the new guides. Website ERB compiles. |
| Formatting | Changed Elixir files formatted, Go files gofmt'd, all repository diffs pass whitespace checks. Five core new/rewritten Ruby parser/packer/formatter files pass installed RuboCop 1.80. |

The shared storage fixture exercises nested/dotted siblings, stars, percent names, dollars, backslashes, double quotes, slashes, Unicode, NUL, repeated updates, and partial sets. Additional tests cover opaque array leaf payloads and decoded-tree resubmission. Ruby shared driver examples are attached to all existing storage-driver spec groups so their normal service CI runs them.

### September 12 integration follow-up

- App `mix.lock` now selects pushed Elixir Stats commit `3a8a913aed720020e4df9038e7ebbdbf7b5df47f`. The full 759-test app suite and development compilation passed with `TRIFLE_STATS_PATH` unset. Loaded module source was verified under `deps/trifle_stats`, not the sibling checkout.
- Added an app PostgreSQL regression using a private connection and a temporary table in the configured test database. It checks public track/read calls, physical encoded fields, decoded values, query discovery, aggregates, dashboard tables, and unchanged system metric identifiers. The final full app suite passes: 760 tests, zero failures, with `TRIFLE_STATS_PATH` unset.
- Ruby Redis shared-example expectations now preserve its existing string-valued raw-read contract. Tested with CI's Redis 4.3.1 and RSpec 3.10 against a disposable dedicated Redis service: 66 examples, zero failures. The user committed the correction as `edf05cf`; the test service and its disposable volume were removed.
- Go CI's unused `hasWildcard` helper was removed. The Node runtime notice was not the lint failure; no insecure Node-version opt-out was added.
- Actual CLI SQLite write/query testing exposed another Go library issue: `Series.AvailablePaths()` did not escape literal keys when discovering numeric paths. Fixed segment rendering and added a regression for literal dots, stars, backslashes, percent names, and array paths. Go 1.24.2 with golangci-lint 1.64.8 passes lint and `go test -race ./...`.
- The user pushed Go correction commit `6ead1ebac6423758abd94b4b56ee423833bc34e4`. CLI `go.mod`/`go.sum` now select that fetched commit, resolved by Go as `v2.7.1-0.20260912090545-6ead1ebac642`. This is a real Git pseudo-version, not a fabricated release. `go mod tidy` removed obsolete Stats checksums; unrelated dependencies are unchanged.
- A new CLI SQLite write/query regression covers aggregate, timeline, and category selection for nested dots, literal dots, literal stars, and percent names. It failed against the initial `cf364558d6ae` Git revision and now passes against the corrected fetched dependency.
- Final CLI verification uses Go 1.24.2 with `GOWORK=off`: full tests, race tests, vet, and golangci-lint 1.64.8 all pass. Module resolution and the built binary's dependency metadata confirm the fetched correction, with no local replacement.
- A fresh isolated SQLite smoke test passes setup, push, decoded reads, opaque metric-key discovery, and all 12 aggregate/timeline/category selector combinations. Dotted, nested, literal-star, and percent paths select their own values. No shared development storage was modified.

### Oban metric-key follow-up

The user subsequently chose `jobs::JOB_NAME` for the app's per-worker Stats metric keys, without additional namespace prefixes (the source name already supplies that context). Trace keys are `jobs/JOB_NAME`; worker dots and the `count`, `states`, and `entries` payload stay unchanged. Only new writes use the shorter metric key. Historical data and saved selections are not rewritten. Regression tests exercise Oban success, warning, and exception wrapup through the real Stats callback and verify literal key discovery. Job-tracing tests assert each worker's trace name, and both PostgreSQL and CLI integration fixtures use the shorter metric key.

### Limits and release gates

After the Oban metric-key follow-up, the full app suite passes with 763 tests and zero failures against the fetched Elixir Stats dependency. Development compilation also passes.

- [ ] Run the complete locked Ruby bundle and driver suite in isolated CI. Host execution used Ruby 3.3 and available gems, not the repository's full locked bundle. Redis-specific follow-up passed with CI's Redis/RSpec versions; Mongo/MySQL/SQLite Ruby gems remain unavailable locally.
- [ ] Run the full Elixir external-service driver matrix in CI; local Elixir verification covered SQLite and PostgreSQL interoperability, plus mocked app Mongo behavior.
- [ ] Verify live MySQL updates with the changed native JSON-path bindings for Ruby/Elixir/Go. No MySQL service was available locally.
- [ ] Browser-level dashboard/monitor save-and-reload smoke test after app dependencies are updated. Automated tests cover path/widget logic and existing app flows, but no manual browser walkthrough was performed.
- [x] Update the app's actual Git dependency lock and verify without its local override.
- [x] Finish the CLI's Git dependency pin after the Go correction commit is pushed; verify with `GOWORK=off`. No package release is needed for this test integration.
- [ ] User assigns real versions and removes/updates unreleased banners when publishing.

No requirement to provision a Hex package, create repositories, publish packages, or commit on the user's behalf is introduced by this work.

## Local testing

App commands must run inside its container:

```sh
docker compose exec -T -e MIX_ENV=test \
  -e TRIFLE_STATS_PATH=/workspaces/trifle_stats app mix test
docker compose exec -T app node --test assets/test/stats_path_test.mjs
docker compose exec -T -e MIX_ENV=test \
  -e TRIFLE_STATS_PATH=/workspaces/trifle_stats app mix assets.build
```

The app override only applies in dev/test. To verify the fetched app Git dependency, use `docker compose exec -T -e MIX_ENV=test app env -u TRIFLE_STATS_PATH mix test`. CLI local verification uses a temporary Go workspace containing `trifle-cli` and `trifle_stats_go`; no `replace` directive was written to go.mod. Use `GOWORK=off go test ./...` to verify the pinned fetched dependency without a local workspace override.

Check fixture parity from docs-trifle-io with `ruby contracts/check_stats_paths.rb`.

Cross-language tests are opt-in: use `TRIFLE_PATH_INTEROP_SCOPE` (matching `paths_[a-z0-9_]+`), `TRIFLE_PATH_INTEROP_COUNT`, and optional `TRIFLE_PATH_INTEROP_WRITE=1`. Always select a fresh scope in an isolated test database. Each write increments once; subsequent reads must use the cumulative count. Ruby/Go require POSTGRES_DSN; the Elixir test uses PGHOST and the isolated trifle_stats_paths_test database.

Test-storage safety: existing Ruby Redis specs call FLUSHDB. Do not run them against a shared development Redis instance. Use a disposable dedicated test service. An earlier run cleared development DB0; the user declined recovery and no restore was performed.

## Release sequence

1. User reviews and commits the library changes and runs the remaining service CI checks.
2. Before releases, pin the app and CLI to the user's pushed Git revisions and rerun integration tests without local overrides.
3. After integration is confirmed, the user publishes Ruby, Elixir, and Go Stats releases; update dependency pins to the actual release refs as appropriate and rerun integration tests.
4. Smoke-test escaped selectors through app dashboards, Explore, and monitors, including saved configurations and literal-star selection.
5. User commits/deploys the app, CLI, docs, and website together with the library rollout.

No historical rewrite or mixed-version compatibility guarantee is included.
