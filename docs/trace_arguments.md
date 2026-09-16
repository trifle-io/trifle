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

## Testing unreleased plugin changes locally

The development compose file mounts the sibling `trifle_traces` checkout at
`/workspaces/trifle_traces`. Set `TRIFLE_TRACES_PATH=/workspaces/trifle_traces` in
the ignored `.env.local` to use it for development and tests. Recreate the app
container after changing this environment setting and start Phoenix again.
Production always uses the GitHub dependency.

After pushing the plugin, remove this local override, recreate the app container,
run `mix deps.update trifle_traces` inside the app container to update `mix.lock`,
and restart Phoenix. Commit/release the plugin before deploying the app changes.
