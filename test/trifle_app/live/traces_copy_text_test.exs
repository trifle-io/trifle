defmodule TrifleApp.TracesLive.CopyTextTest do
  use ExUnit.Case, async: true
  alias Trifle.Traces.TraceRecord
  alias TrifleApp.TracesLive.CopyText

  test "plain text includes trace details and recorded arguments before the loaded log entries" do
    record = %TraceRecord{
      reference: "example",
      key: "jobs/App.Worker",
      state: :warning,
      first_at: ~U[2026-09-14 10:00:00Z],
      last_at: ~U[2026-09-14 10:00:01Z],
      duration: 1000,
      tags: ["queue:default", "東京"],
      meta: %{args: %{id: 42}},
      context: %{queue: "default"},
      parts: 3
    }

    entries = [
      %{entry: %{type: :head, state: :success, at: 1_700_000_000, message: "Start"}},
      %{
        entry: %{
          "type" => "text",
          "state" => "warning",
          "message" => "First\nSecond",
          "level" => 1
        }
      },
      %{entry: %{type: :raw, state: :success, message: "↳ %{answer: 42}"}},
      %{entry: %{type: :media, message: "attachment.png"}}
    ]

    text = CopyText.format(record, entries, 1)
    assert text =~ "Trace: jobs/App.Worker\nReference: example\nState: warning"
    assert text =~ "Started: 2026-09-14T10:00:00Z"
    assert text =~ "Last: 2026-09-14T10:00:01Z\nDuration: 1000 ms"
    assert text =~ "Loaded parts: 1/3\nLoaded entries: 4"
    assert text =~ ~s(Tags: ["queue:default","東京"])
    assert text =~ ~s("args": {\n    "id": 42)
    assert text =~ ~s(Context:\n{\n  "queue": "default"\n})
    assert text =~ "2023-11-14T22:13:20Z [success/head] Start"
    assert text =~ "[warning/text]   First\nSecond"
    assert text =~ "[success/raw] ↳ %{answer: 42}"
    refute text =~ "attachment.png"

    assert :binary.match(text, "Metadata / arguments:") <
             :binary.match(text, "[success/head] Start")

    assert :binary.match(text, "[success/head] Start") < :binary.match(text, "[success/raw]")
  end

  test "empty or partially loaded traces are explicitly identified without fabricating entries" do
    record = %TraceRecord{reference: "empty", key: "jobs/empty", parts: 5}
    text = CopyText.format(record, [], 0)
    assert text =~ "Loaded parts: 0/5\nLoaded entries: 0"
    assert text =~ "Started: —\nLast: —"
    assert text =~ "Metadata / arguments:\nnull"
    assert text =~ "Context:\n{}"
    refute text =~ "[success/text]"
  end
end
