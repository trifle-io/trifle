defmodule Trifle.Accounts.UserNotifier do
  import Swoosh.Email

  alias Trifle.Mailer
  alias Trifle.Mailer.Template

  @default_from {"Trifle", "contact@example.com"}

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, %{html: html, text: text}) do
    email =
      new()
      |> to(recipient)
      |> from(from_address())
      |> subject(subject)
      |> text_body(text)
      |> html_body(html)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp from_address do
    Application.get_env(:trifle, :mailer_from, @default_from)
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    body =
      Template.action_email(
        headline: "Confirm your account",
        greeting: "Hi #{user.email},",
        intro_lines: ["You can confirm your account using the link below."],
        action_label: "Confirm account",
        action_url: url,
        footer_lines: ["If you didn't create an account with us, please ignore this email."]
      )

    deliver(user.email, "Confirmation instructions", body)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    body =
      Template.action_email(
        headline: "Reset your password",
        greeting: "Hi #{user.email},",
        intro_lines: ["You can reset your password using the link below."],
        action_label: "Reset password",
        action_url: url,
        footer_lines: ["If you didn't request this change, please ignore this email."]
      )

    deliver(user.email, "Reset password instructions", body)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    body =
      Template.action_email(
        headline: "Confirm your new email address",
        greeting: "Hi #{user.email},",
        intro_lines: ["You can confirm your email change using the link below."],
        action_label: "Confirm email change",
        action_url: url,
        footer_lines: ["If you didn't request this change, please ignore this email."]
      )

    deliver(user.email, "Update email instructions", body)
  end
end
