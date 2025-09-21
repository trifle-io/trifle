defmodule Trifle.Organizations.InvitationNotifier do
  @moduledoc """
  Handles outgoing email notifications for organization invitations.
  Uses the configured `Trifle.Mailer`, which defaults to the local mailbox
  adapter in development so messages appear under `/dev/mailbox`.
  """

  import Swoosh.Email
  require Logger

  alias Trifle.Mailer
  alias Trifle.Organizations.OrganizationInvitation
  alias Trifle.Repo

  @default_from {"Trifle", "contact@example.com"}

  @doc """
  Deliver an invitation email to the invitee.

  The invitation struct is preloaded with the related organization and
  inviting user to populate the message. Errors from the mailer are logged
  but do not raise, allowing the calling workflow to continue.
  """
  @spec deliver_invitation(OrganizationInvitation.t()) :: :ok | {:error, term()}
  def deliver_invitation(%OrganizationInvitation{} = invitation) do
    invitation = Repo.preload(invitation, [:organization, :invited_by])

    email =
      new()
      |> to(invitation.email)
      |> from(from_address())
      |> subject(subject_line(invitation))
      |> text_body(text_body(invitation))
      |> html_body(html_body(invitation))

    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Failed to deliver organization invitation email to #{invitation.email}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp from_address do
    Application.get_env(:trifle, :mailer_from, @default_from)
  end

  defp subject_line(%OrganizationInvitation{organization: organization}) do
    org_name = (organization && organization.name) || "an organization"
    "You're invited to join #{org_name} on Trifle"
  end

  defp text_body(%OrganizationInvitation{} = invitation) do
    org_name = (invitation.organization && invitation.organization.name) || "the organization"
    inviter = inviter_name(invitation)
    accept_url = acceptance_url(invitation)
    expires = expiration_sentence(invitation)

    """
    Hi,

    #{inviter} invited you to join #{org_name} on Trifle.

    Accept your invitation using the link below:
    #{accept_url}

    #{expires}

    If you weren't expecting this invitation, you can safely ignore this email.
    """
  end

  defp html_body(%OrganizationInvitation{} = invitation) do
    org_name = (invitation.organization && invitation.organization.name) || "the organization"
    inviter = inviter_name(invitation)
    accept_url = acceptance_url(invitation)
    expires = expiration_sentence(invitation)

    """
    <p>Hi,</p>
    <p>#{inviter} invited you to join #{org_name} on Trifle.</p>
    <p><a href="#{accept_url}">Click here to accept your invitation</a>.</p>
    <p>#{expires}</p>
    <p>If you weren't expecting this invitation, you can safely ignore this email.</p>
    """
  end

  defp inviter_name(%OrganizationInvitation{invited_by: nil}), do: "Someone"

  defp inviter_name(%OrganizationInvitation{invited_by: invited_by}) do
    Map.get(invited_by, :email) || "Someone"
  end

  defp acceptance_url(%OrganizationInvitation{token: token}) do
    base_url =
      cond do
        function_exported?(TrifleWeb.Endpoint, :url, 0) -> TrifleWeb.Endpoint.url()
        base = Application.get_env(:trifle, :app_base_url) -> base
        true -> "http://localhost:4000"
      end

    base_url
    |> String.trim_trailing("/")
    |> Kernel.<>("/invitations/#{token}")
  end

  defp expiration_sentence(%OrganizationInvitation{expires_at: nil}) do
    "This link expires in 3 days."
  end

  defp expiration_sentence(%OrganizationInvitation{expires_at: %DateTime{} = expires_at}) do
    formatted = Calendar.strftime(expires_at, "%B %-d, %Y at %H:%M %Z")

    "This link expires on #{formatted}."
  rescue
    _ -> "This link expires in 3 days."
  end
end
