defmodule Trifle.Billing.Jobs.ProcessStripeEvent do
  use Oban.Worker,
    queue: :billing,
    max_attempts: 10,
    unique: [period: 60, fields: [:args]]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"webhook_event_id" => webhook_event_id}}) do
    case Trifle.Billing.process_webhook_event(webhook_event_id) do
      {:ok, _event} -> :ok
      {:error, :not_found} -> :discard
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{args: args}) when is_map(args) do
    Logger.warning("Discarding Stripe webhook job with invalid args: #{inspect(args)}")
    :discard
  end

  def perform(%Oban.Job{} = job) do
    Logger.warning("Discarding Stripe webhook job with non-map args: #{inspect(job.args)}")
    :discard
  end
end
