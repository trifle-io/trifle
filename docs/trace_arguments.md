# Trace arguments

Arguments are stored directly in `TraceRecord.meta`: an array of positional
arguments or an object of named arguments. Ruby Sidekiq/Rails already use this
convention. The Elixir Oban integration now stores `job.args` directly in `meta`
and job ID, queue, worker, and attempt in `context`. Configured context values
override those defaults. No argument redaction or truncation happens at capture.

The app uses the library's Oban defaults, with no app-specific metadata override.
The detail header displays `meta` below the reference without framework detection
or an `args` wrapper. Long values show a 240-character JSON preview; **Expand all**
reveals complete, pretty-printed JSON and **Collapse** restores the preview.
Raw Metadata and clipboard text retain the complete stored arguments.

There is no conversion of historical development records. New jobs use the new
format; arguments omitted from earlier traces cannot be recovered.

## Updating the plugins

Development, tests, and production use the GitHub dependencies pinned in
`mix.lock`. The temporary local SDK path overrides have been removed. After
pushing plugin changes, update the dependencies inside the app container:

```sh
docker compose -f .devops/docker/local/docker-compose.yml exec -T app \
  mix deps.update trifle_stats trifle_traces
```

Commit the updated lockfile with the app changes and restart Phoenix and workers.
The app can use a pushed Git commit before the library is released. Traces
receives the internal Stats configuration through `stats_config`; the library
records activity at wrapup without application lifecycle callbacks.

When adopting the bucket-name update, run the app's release migrations before
startup. They add nullable text `bucket_name` to app trace tables without
backfilling legacy indices.
