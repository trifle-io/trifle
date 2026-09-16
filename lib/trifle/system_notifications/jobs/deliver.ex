defmodule Trifle.SystemNotifications.Jobs.Deliver do
  @moduledoc false

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    unique: [
      period: 604_800,
      fields: [:worker, :args],
      keys: [:notification_id, :recipient_id]
    ]

  import Swoosh.Email

  alias Trifle.Accounts.User
  alias Trifle.Mailer
  alias Trifle.Repo
  alias Trifle.SystemNotifications.Email
  alias Trifle.Traces

  @default_from {"Trifle", "contact@example.com"}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "recipient_id" => recipient_id,
          "event" => event,
          "payload" => payload
        }
      }) do
    Traces.trace("Deliver system notification", head: true)
    Traces.tag("notification-recipient:#{recipient_id}")
    Traces.tag("notification-event:#{event}")
    Traces.trace("Load administrator recipient")

    case Repo.get_by(User, id: recipient_id, is_admin: true) do
      %User{email: email} when is_binary(email) ->
        Traces.trace("Administrator recipient found")
        Traces.trace("Render notification email")

        case Email.render(event, payload) do
          {:ok, content} ->
            Traces.trace("Notification email rendered")
            Traces.trace("Send notification email")

            case content |> build_email(email) |> Mailer.deliver() do
              {:ok, _metadata} ->
                Traces.trace("Notification email delivered")
                :ok

              {:error, reason} ->
                Traces.trace("Notification email delivery failed", state: :error)
                Traces.fail()
                {:error, reason}
            end

          {:error, reason} ->
            Traces.trace("Notification email rendering failed", state: :error)
            Traces.fail()
            {:error, reason}
        end

      _ ->
        Traces.trace("Administrator recipient is unavailable; discarding", state: :warning)
        Traces.warn()
        :discard
    end
  end

  def perform(%Oban.Job{}) do
    Traces.trace("Validate notification delivery job", head: true)
    Traces.trace("Required delivery fields are missing", state: :warning)
    Traces.warn()
    :discard
  end

  defp build_email(content, recipient) do
    new()
    |> to(recipient)
    |> from(Application.get_env(:trifle, :mailer_from, @default_from))
    |> subject(content.subject)
    |> text_body(content.text)
    |> html_body(content.html)
  end
end
