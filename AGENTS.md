# Repository Guidelines

This application is running inside of Docker container, but you are running on a host. Prefix all application related commands (ie tests, linters, scripts) with `docker compose exec -T app COMMAND` to run them within the container.

## Project Structure & Module Organization
Trifle is a Phoenix LiveView analytics app. Application code lives under `lib/` grouped by OTP app: `lib/trifle_web` for web UI, `lib/trifle_api` for ingest endpoints, `lib/trifle_admin` for admin dashboards, and `lib/trifle` for shared contexts. Assets (Tailwind, esbuild bundles) live in `assets/`, while compiled/static output is staged in `priv/static`. Database migrations and seeds sit in `priv/repo`. Tests mirror the lib layout in `test/`, with helpers in `test/support`. Docs, Helm charts, and deployment scripts reside in `docs/` and `.devops/`.

## Build, Test, and Development Commands
Run `mix setup` once per machine to fetch deps, prepare databases, and build assets. Use `mix phx.server` for the Phoenix dev server (visit http://localhost:4000). Regenerate client assets with `mix assets.build`; ship-ready assets use `mix assets.deploy`. Database lifecycle helpers: `mix ecto.migrate`, `mix ecto.reset`, and `mix ecto.setup`. For smoke data, call `mix populate_metrics --token=...` or `./populate_batch.sh TOKEN TOTAL HOURS`.
Container dev uses named volumes for `deps` and `_build` to avoid host/native build mismatches; if native deps fail, run `mix deps.clean --all` and `mix deps.get` inside the app container.

## Coding Style & Naming Conventions
Follow the Elixir formatter (`mix format`); the project’s `.formatter.exs` also formats LiveView HEEx templates. Use two-space indentation, modules in `CamelCase`, functions/macros in `snake_case`, and atoms in `:snake_case`. Branch-specific config stays in `config/*.exs`; avoid committing secrets. Front-end assets should match Tailwind utility patterns; keep custom CSS under `assets/css` when possible.

## Testing Guidelines
All tests end with `_test.exs` and sit beside the code they exercise. Run the suite with `mix test`; the alias creates and migrates the test DB automatically. Target a single area via `mix test test/trifle_web/live/dashboard_live_test.exs`. Use `mix test --cover` before shipping significant changes and populate fixtures via `test/support/data_case.ex`. Tests that hit MongoDB or metrics APIs should stub via `Trifle.*Mock` modules rather than live services.

## Commit & Pull Request Guidelines
Commit messages follow `<type>: <present-tense summary>` (see recent `feat:` and `fix:` entries). Group related changes per commit; run `mix format` and `mix test` before pushing. Pull requests need: 1) a changelog-style summary, 2) linked issue or context, and 3) screenshots or recordings for UI updates. Call out schema changes so reviewers can run migrations, and note any new env vars in the PR body.

## Environment & Data Tips
Use `.devops/docker/local_db/docker-compose.yml` to launch Postgres and Mongo locally (`docker-compose up -d`). Version bumps belong in the root `VERSION` file. Keep large sample datasets in SQLite snapshots under the project root; regenerate from production sources only with approval.

---

When a shell command fails with “failed in sandbox”, use the permission request tool (with `with_escalated_permissions`) to ask the user for approval before retrying.
