defmodule Trifle.Billing.Jobs.ProcessStripeEventTest do
  use Trifle.DataCase, async: true

  import ExUnit.CaptureLog

  alias Trifle.Billing.Jobs.ProcessStripeEvent
  alias Trifle.Billing.WebhookEvent
  alias Trifle.Repo

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

  test "returns an error and marks the webhook event as failed when processing fails" do
    event =
      Repo.insert!(%WebhookEvent{
        stripe_event_id: "evt_#{System.unique_integer([:positive])}",
        event_type: "customer.subscription.created",
        payload: %{
          "type" => "customer.subscription.created",
          "data" => %{
            "object" => %{
              "id" => "sub_#{System.unique_integer([:positive])}",
              "status" => "active",
              "metadata" => %{}
            }
          }
        }
      })

    assert {:error, :organization_id_missing} ==
             ProcessStripeEvent.perform(%Oban.Job{args: %{"webhook_event_id" => event.id}})

    updated_event = Repo.get!(WebhookEvent, event.id)
    assert updated_event.status == "failed"
    assert updated_event.processed_at
    assert updated_event.error == ":organization_id_missing"
  end

  test "returns ok for already processed webhook events" do
    event =
      Repo.insert!(%WebhookEvent{
        stripe_event_id: "evt_#{System.unique_integer([:positive])}",
        event_type: "customer.subscription.created",
        status: "processed",
        processed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        payload: %{"type" => "customer.subscription.created", "data" => %{"object" => %{}}}
      })

    assert :ok == ProcessStripeEvent.perform(%Oban.Job{args: %{"webhook_event_id" => event.id}})
  end
end
