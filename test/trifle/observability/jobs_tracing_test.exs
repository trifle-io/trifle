defmodule Trifle.Observability.JobsTracingTest do
  use Trifle.DataCase, async: false

  import Ecto.Query

  alias Trifle.Accounts.User
  alias Trifle.Billing.Jobs.ProcessStripeEvent
  alias Trifle.Monitors.Jobs.{DispatchRunner, EvaluateMonitor}
  alias Trifle.Observability.Jobs.CleanupTraces
  alias Trifle.SystemNotifications.Jobs.{Deliver, Dispatch}
  alias Trifle.Traces
  alias Trifle.Traces.Configuration

  test "Stripe jobs trace invalid input without copying job arguments" do
    {result, trace} =
      capture_trace(ProcessStripeEvent, fn ->
        ProcessStripeEvent.perform(job(%{"token" => "secret"}))
      end)

    assert result == :discard
    assert trace.key == "jobs/Trifle.Billing.Jobs.ProcessStripeEvent"
    assert trace.state == :warning
    assert_message(trace, "Required webhook event identifier is missing")
    refute trace_text(trace) =~ "secret"
  end

  test "monitor dispatch traces selection and its enqueue summary" do
    scheduled_at = DateTime.utc_now() |> DateTime.truncate(:second)

    {result, trace} =
      capture_trace(DispatchRunner, fn ->
        DispatchRunner.perform(job(%{}, scheduled_at: scheduled_at))
      end)

    assert result == :ok
    assert trace.key == "jobs/Trifle.Monitors.Jobs.DispatchRunner"
    assert_message(trace, "Eligible monitors: 0")
    assert_message(trace, "Due: 0; enqueued: 0; skipped: 0; failed: 0")
  end

  test "monitor evaluation traces a missing monitor as a warning" do
    monitor_id = Ecto.UUID.generate()

    {result, trace} =
      capture_trace(EvaluateMonitor, fn ->
        EvaluateMonitor.perform(job(%{"monitor_id" => monitor_id}))
      end)

    assert result == :discard
    assert trace.key == "jobs/Trifle.Monitors.Jobs.EvaluateMonitor"
    assert trace.state == :warning
    assert "monitor:#{monitor_id}" in trace.tags
    assert_message(trace, "Monitor no longer exists; discarding")
  end

  test "notification dispatch traces recipient selection without its payload" do
    Repo.update_all(from(user in User, where: user.is_admin == true), set: [is_admin: false])

    args = %{
      "notification_id" => Ecto.UUID.generate(),
      "event" => "billing_failed",
      "payload" => %{"access_token" => "never-trace-this"}
    }

    {result, trace} = capture_trace(Dispatch, fn -> Dispatch.perform(job(args)) end)

    assert result == :ok
    assert trace.key == "jobs/Trifle.SystemNotifications.Jobs.Dispatch"
    assert_message(trace, "Eligible administrator recipients: 0")
    refute trace_text(trace) =~ "never-trace-this"
  end

  test "notification delivery traces an unavailable recipient without email content" do
    recipient_id = Ecto.UUID.generate()

    args = %{
      "recipient_id" => recipient_id,
      "event" => "billing_failed",
      "payload" => %{"body" => "never-trace-this"}
    }

    {result, trace} = capture_trace(Deliver, fn -> Deliver.perform(job(args)) end)

    assert result == :discard
    assert trace.key == "jobs/Trifle.SystemNotifications.Jobs.Deliver"
    assert trace.state == :warning
    assert "notification-recipient:#{recipient_id}" in trace.tags
    assert_message(trace, "Administrator recipient is unavailable; discarding")
    refute trace_text(trace) =~ "never-trace-this"
  end

  test "trace cleanup records the number of deleted indexes" do
    {result, trace} = capture_trace(CleanupTraces, fn -> CleanupTraces.perform(job(%{})) end)

    assert result == :ok
    assert trace.key == "jobs/Trifle.Observability.Jobs.CleanupTraces"
    assert_message(trace, "Expired trace indexes deleted: 0")
  end

  defp capture_trace(worker, fun) do
    parent = self()
    config = Configuration.new(on_wrapup: &send(parent, {:captured_trace, &1}))
    result = Traces.with_tracer("jobs/#{inspect(worker)}", [config: config], fun)
    assert_receive {:captured_trace, trace}
    {result, trace}
  end

  defp job(args, options \\ []) do
    struct!(Oban.Job, Keyword.merge([args: args], options))
  end

  defp assert_message(trace, expected) do
    assert Enum.any?(trace.data, &(&1.message == expected)),
           "expected trace message #{inspect(expected)}, got: #{trace_text(trace)}"
  end

  defp trace_text(trace), do: Enum.map_join(trace.data, "\n", & &1.message)
end
