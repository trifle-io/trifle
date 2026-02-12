defmodule Trifle.Billing.Jobs.ProcessStripeEventTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Trifle.Billing.Jobs.ProcessStripeEvent

  test "discards jobs when webhook_event_id is missing" do
    log =
      capture_log(fn ->
        assert :discard == ProcessStripeEvent.perform(%Oban.Job{args: %{"unexpected" => "value"}})
      end)

    assert log =~ "invalid args"
  end

  test "discards jobs when args are not a map" do
    log =
      capture_log(fn ->
        assert :discard == ProcessStripeEvent.perform(%Oban.Job{args: "invalid"})
      end)

    assert log =~ "non-map args"
  end
end
