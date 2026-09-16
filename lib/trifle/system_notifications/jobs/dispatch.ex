defmodule Trifle.SystemNotifications.Jobs.Dispatch do
  @moduledoc false

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    unique: [period: 604_800, fields: [:worker, :args], keys: [:notification_id]]

  import Ecto.Query

  alias Trifle.Accounts.User
  alias Trifle.Repo
  alias Trifle.SystemNotifications.Jobs.Deliver
  alias Trifle.Traces

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "notification_id" => notification_id,
          "event" => event,
          "payload" => payload
        }
      }) do
    Traces.trace("Dispatch system notification", head: true)
    Traces.tag("system-notification:#{notification_id}")
    Traces.tag("notification-event:#{event}")

    recipient_ids =
      User
      |> where([user], user.is_admin == true)
      |> select([user], user.id)
      |> Repo.all()

    Traces.trace("Eligible administrator recipients: #{length(recipient_ids)}")

    recipient_ids
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {recipient_id, position}, :ok ->
      Traces.trace("Recipient #{position} of #{length(recipient_ids)}", head: true)
      Traces.tag("notification-recipient:#{recipient_id}")

      args = %{
        "notification_id" => notification_id,
        "recipient_id" => recipient_id,
        "event" => event,
        "payload" => payload
      }

      case Oban.insert(Deliver.new(args)) do
        {:ok, job} ->
          Traces.tag("delivery-job:#{job.id}")
          Traces.trace("Delivery job enqueued")
          {:cont, :ok}

        {:error, reason} ->
          Traces.trace("Delivery job enqueue failed", state: :error)
          Traces.fail()
          {:halt, {:error, reason}}
      end
    end)
  end

  def perform(%Oban.Job{}) do
    Traces.trace("Validate system notification job", head: true)
    Traces.trace("Required notification fields are missing", state: :warning)
    Traces.warn()
    :discard
  end
end
