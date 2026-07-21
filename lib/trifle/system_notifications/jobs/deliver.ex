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

  @default_from {"Trifle", "contact@example.com"}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "recipient_id" => recipient_id,
          "event" => event,
          "payload" => payload
        }
      }) do
    case Repo.get_by(User, id: recipient_id, is_admin: true) do
      %User{email: email} when is_binary(email) ->
        with {:ok, content} <- Email.render(event, payload),
             {:ok, _metadata} <-
               content
               |> build_email(email)
               |> Mailer.deliver() do
          :ok
        end

      _ ->
        :discard
    end
  end

  def perform(%Oban.Job{}), do: :discard

  defp build_email(content, recipient) do
    new()
    |> to(recipient)
    |> from(Application.get_env(:trifle, :mailer_from, @default_from))
    |> subject(content.subject)
    |> text_body(content.text)
    |> html_body(content.html)
  end
end
