defmodule Trifle.Billing.Jobs.ProcessStripeEvent do
  use Oban.Worker,
    queue: :billing,
    max_attempts: 10,
    unique: [period: 60, fields: [:args]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"webhook_event_id" => webhook_event_id}}) do
    case Trifle.Billing.process_webhook_event(webhook_event_id) do
      {:ok, _event} -> :ok
      {:error, :not_found} -> :discard
      {:error, reason} -> {:error, reason}
    end
  end
end
