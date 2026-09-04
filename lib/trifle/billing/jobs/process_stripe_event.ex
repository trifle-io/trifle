defmodule Trifle.Billing.Jobs.ProcessStripeEvent do
  use Oban.Worker,
    queue: :billing,
    max_attempts: 10,
    unique: [period: 60, fields: [:args]]

  require Logger

  alias Trifle.Traces

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"webhook_event_id" => webhook_event_id}}) do
    Traces.trace("Process Stripe webhook event", head: true)
    Traces.tag("stripe-webhook-event:#{webhook_event_id}")
    Traces.trace("Webhook event identified")

    case Trifle.Billing.process_webhook_event(webhook_event_id) do
      {:ok, _event} ->
        Traces.trace("Webhook event processed")
        :ok

      {:error, :not_found} ->
        Traces.trace("Webhook event no longer exists; discarding", state: :warning)
        Traces.warn()
        :discard

      {:error, reason} ->
        Traces.trace("Webhook event processing failed (#{reason_kind(reason)})", state: :error)
        Traces.fail()
        {:error, reason}
    end
  end

  def perform(%Oban.Job{args: args}) when is_map(args) do
    Logger.warning("Discarding Stripe webhook job with invalid args: #{inspect(args)}")
    trace_invalid_args()
    :discard
  end

  def perform(%Oban.Job{} = job) do
    Logger.warning("Discarding Stripe webhook job with non-map args: #{inspect(job.args)}")
    trace_invalid_args()
    :discard
  end

  defp trace_invalid_args do
    Traces.trace("Validate Stripe webhook job", head: true)
    Traces.trace("Required webhook event identifier is missing", state: :warning)
    Traces.warn()
  end

  defp reason_kind(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_kind(%{__struct__: module}), do: inspect(module)
  defp reason_kind(_reason), do: "error"
end
