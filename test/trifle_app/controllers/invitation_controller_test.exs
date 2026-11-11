defmodule TrifleApp.InvitationControllerTest do
  use TrifleApp.ConnCase

  import Trifle.AccountsFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations

  setup do
    owner = user_fixture()

    organization =
      organization_fixture(%{
        user: owner,
        name: "Inviting Org #{System.unique_integer([:positive])}"
      })

    invitee = user_fixture()

    {:ok, invitation} =
      Organizations.create_invitation(
        organization,
        %{email: invitee.email, role: "member"},
        owner
      )

    %{
      organization: organization,
      invitee: invitee,
      invitation: invitation,
      token: invitation.token
    }
  end

  test "the invitation page renders for the signed-in recipient and posts back to the same token",
       %{conn: conn, invitee: invitee, token: token} do
    conn = conn |> log_in_user(invitee) |> get(~p"/invitations/#{token}")

    html = html_response(conn, 200)
    assert html =~ ~s(action="/invitations/#{token}/accept")
  end

  test "accepting from the page adds the recipient to the organization", %{
    conn: conn,
    organization: organization,
    invitee: invitee,
    token: token
  } do
    conn = conn |> log_in_user(invitee) |> post(~p"/invitations/#{token}/accept")

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Invitation accepted"
    assert Organizations.get_membership_for_user(invitee).organization_id == organization.id
  end

  test "someone else signed in cannot accept it", %{conn: conn, token: token} do
    bystander = user_fixture()
    conn = conn |> log_in_user(bystander) |> post(~p"/invitations/#{token}/accept")

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "different email address"
    assert is_nil(Organizations.get_membership_for_user(bystander))
  end

  test "a visitor who is not signed in is sent to sign in, keeping the token", %{
    conn: conn,
    token: token
  } do
    conn = get(conn, ~p"/invitations/#{token}")

    assert redirected_to(conn) =~ "invitation_token=#{token}"
  end

  test "an unknown token is rejected", %{conn: conn, invitee: invitee} do
    conn = conn |> log_in_user(invitee) |> get(~p"/invitations/not-a-real-token")

    assert redirected_to(conn) == ~p"/users/log_in"
  end
end
