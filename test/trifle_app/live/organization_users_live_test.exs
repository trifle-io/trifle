defmodule TrifleApp.OrganizationUsersLiveTest do
  # The billing tests flip the global deployment mode.
  use TrifleApp.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Trifle.AccountsFixtures
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations
  alias Trifle.Organizations.OrganizationInvitation
  alias Trifle.Repo

  setup do
    owner = user_fixture()

    organization =
      organization_fixture(%{user: owner, name: "Roles #{System.unique_integer([:positive])}"})

    app_entitlement_fixture(organization)

    admin = user_fixture()
    {:ok, admin_membership} = Organizations.create_membership(organization, admin, "admin")

    member = user_fixture()
    {:ok, member_membership} = Organizations.create_membership(organization, member, "member")

    owner_membership = Organizations.get_membership_for_user(owner)

    %{
      organization: organization,
      owner: owner,
      owner_membership: owner_membership,
      admin: admin,
      admin_membership: admin_membership,
      member: member,
      member_membership: member_membership
    }
  end

  defp open_as(conn, user) do
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/organization/users")
    lv
  end

  defp role(membership), do: Repo.reload!(membership).role

  describe "the owner role" do
    test "an admin cannot promote anyone to owner", ctx do
      lv = open_as(ctx.conn, ctx.admin)

      html =
        render_hook(lv, "update_role", %{"id" => ctx.member_membership.id, "role" => "owner"})

      assert html =~ "Only an organization owner"
      assert role(ctx.member_membership) == "member"
    end

    test "an admin cannot demote or remove an owner", ctx do
      lv = open_as(ctx.conn, ctx.admin)

      render_hook(lv, "update_role", %{"id" => ctx.owner_membership.id, "role" => "member"})
      assert role(ctx.owner_membership) == "owner"

      html = render_hook(lv, "remove_member", %{"id" => ctx.owner_membership.id})
      assert html =~ "Only an organization owner"
      assert Repo.reload(ctx.owner_membership)
    end

    test "an admin cannot invite someone as owner", ctx do
      lv = open_as(ctx.conn, ctx.admin)

      html =
        render_hook(lv, "invite_member", %{
          "invitation" => %{"email" => "new-owner@example.com", "role" => "owner"}
        })

      assert html =~ "Only an organization owner"
      refute Repo.get_by(OrganizationInvitation, email: "new-owner@example.com")
    end

    test "an admin can still manage members and admins", ctx do
      lv = open_as(ctx.conn, ctx.admin)

      render_hook(lv, "update_role", %{"id" => ctx.member_membership.id, "role" => "admin"})
      assert role(ctx.member_membership) == "admin"
    end

    test "an owner can grant the owner role", ctx do
      lv = open_as(ctx.conn, ctx.owner)

      render_hook(lv, "update_role", %{"id" => ctx.member_membership.id, "role" => "owner"})
      assert role(ctx.member_membership) == "owner"
    end
  end

  describe "invitations" do
    setup ctx do
      {:ok, invitation} =
        Organizations.create_invitation(
          ctx.organization,
          %{email: "pending@example.com", role: "member"},
          ctx.owner
        )

      %{invitation: invitation}
    end

    test "a plain member cannot cancel or re-send them", ctx do
      lv = open_as(ctx.conn, ctx.member)

      render_hook(lv, "cancel_invitation", %{"id" => ctx.invitation.id})
      assert Repo.reload!(ctx.invitation).status == "pending"

      before = Repo.reload!(ctx.invitation).token_hash
      render_hook(lv, "resend_invitation", %{"id" => ctx.invitation.id})
      assert Repo.reload!(ctx.invitation).token_hash == before
    end

    test "an admin can cancel them", ctx do
      lv = open_as(ctx.conn, ctx.admin)

      render_hook(lv, "cancel_invitation", %{"id" => ctx.invitation.id})
      assert Repo.reload!(ctx.invitation).status == "cancelled"
    end
  end

  describe "billing actions" do
    setup do
      previous_mode = Application.get_env(:trifle, :deployment_mode)
      Application.put_env(:trifle, :deployment_mode, :saas)

      on_exit(fn ->
        if is_nil(previous_mode),
          do: Application.delete_env(:trifle, :deployment_mode),
          else: Application.put_env(:trifle, :deployment_mode, previous_mode)
      end)

      :ok
    end

    test "plain members cannot open checkout or the billing portal", ctx do
      conn = log_in_user(ctx.conn, ctx.member)

      for response <- [
            post(conn, ~p"/organization/billing/checkout/app", %{}),
            post(conn, ~p"/organization/billing/portal", %{})
          ] do
        assert redirected_to(response) == ~p"/organization/billing"
        assert Phoenix.Flash.get(response.assigns.flash, :error) =~ "owners and admins"
      end
    end
  end

  test "billing URLs return a plain 404 when billing is not available", %{
    conn: conn,
    member: member
  } do
    previous_mode = Application.get_env(:trifle, :deployment_mode)
    Application.put_env(:trifle, :deployment_mode, :self_hosted)

    on_exit(fn ->
      if is_nil(previous_mode),
        do: Application.delete_env(:trifle, :deployment_mode),
        else: Application.put_env(:trifle, :deployment_mode, previous_mode)
    end)

    conn = conn |> log_in_user(member) |> post(~p"/organization/billing/portal", %{})
    assert conn.status == 404
  end
end
