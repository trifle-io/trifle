defmodule TrifleApp.InvitationController do
  use TrifleApp, :controller

  import TrifleApp.UserAuth, only: [require_authenticated_user: 2]

  alias Ecto.Changeset
  alias Trifle.Organizations
  alias Trifle.Organizations.OrganizationInvitation
  alias TrifleApp.RegistrationConfig

  plug TrifleWeb.Plugs.RateLimit, policy: :invitation
  plug :put_root_layout, html: {TrifleApp.Layouts, :page}
  # The app layout (sidebar) only works inside a LiveView: it needs @socket. This
  # page is rendered by a controller, so it uses the standalone page layout alone.
  plug :put_layout, false
  plug :require_authenticated_user when action in [:accept]

  def show(conn, %{"token" => token}) do
    case Organizations.get_invitation_by_token(token) do
      %OrganizationInvitation{} = invitation ->
        maybe_require_login(conn, invitation, token)

      _ ->
        conn
        |> put_flash(:error, "This invitation link is invalid or has expired.")
        |> redirect(to: ~p"/users/log_in")
    end
  end

  def accept(conn, %{"token" => token}) do
    current_user = conn.assigns.current_user

    with %OrganizationInvitation{} = invitation <- Organizations.get_invitation_by_token(token),
         false <- Organizations.invitation_expired?(invitation),
         {:ok, _membership} <- Organizations.accept_invitation(invitation, current_user) do
      conn
      |> put_flash(:info, "Invitation accepted. Welcome aboard!")
      |> redirect(to: ~p"/")
    else
      {:error, :expired} ->
        conn
        |> put_flash(:error, "This invitation has expired. Please request a new invite.")
        |> redirect(to: ~p"/users/log_in")

      {:error, :belongs_to_another_organization} ->
        conn
        |> put_flash(:error, "You already belong to a different organization.")
        |> redirect(to: ~p"/")

      {:error, :invalid_status} ->
        conn
        |> put_flash(:error, "This invitation cannot be accepted.")
        |> redirect(to: ~p"/")

      {:error, :email_mismatch} ->
        conn
        |> put_flash(
          :error,
          "This invitation was sent to a different email address. Sign in with that address, or ask for an invitation to this one."
        )
        |> redirect(to: ~p"/")

      {:error, :seat_limit_reached} ->
        conn
        |> put_flash(
          :error,
          "This organization has no free seats on its plan. Ask an owner to upgrade or free a seat, then open the invitation again."
        )
        |> redirect(to: ~p"/")

      {:error, %Changeset{} = changeset} ->
        conn
        |> put_flash(:error, "Could not accept invitation: #{changeset_error(changeset)}")
        |> redirect(to: ~p"/")

      _ ->
        conn
        |> put_flash(:error, "Unable to process this invitation.")
        |> redirect(to: ~p"/")
    end
  end

  defp maybe_require_login(%{assigns: %{current_user: nil}} = conn, _invitation, token) do
    conn
    |> put_session(:user_return_to, ~p"/invitations/#{token}")
    |> redirect(
      to:
        if RegistrationConfig.enabled?() do
          ~p"/users/log_in?invitation_token=#{token}"
        else
          ~p"/users/register?invitation_token=#{token}"
        end
    )
  end

  # The stored invitation only has the token's hash, so the form posts back to
  # the token that came in the URL.
  defp maybe_require_login(conn, invitation, token) do
    render(conn, :show,
      invitation: invitation,
      token: token,
      expired?: Organizations.invitation_expired?(invitation)
    )
  end

  defp changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.into([], fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
    |> Enum.join(". ")
  end
end
