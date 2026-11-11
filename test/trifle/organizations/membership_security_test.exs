defmodule Trifle.Organizations.MembershipSecurityTest do
  # Flips the global deployment mode.
  use Trifle.DataCase, async: false

  import Trifle.AccountsFixtures
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Accounts
  alias Trifle.Organizations
  alias Trifle.Organizations.OrganizationApiToken

  setup do
    previous_mode = Application.get_env(:trifle, :deployment_mode)
    Application.put_env(:trifle, :deployment_mode, :saas)

    on_exit(fn ->
      if is_nil(previous_mode),
        do: Application.delete_env(:trifle, :deployment_mode),
        else: Application.put_env(:trifle, :deployment_mode, previous_mode)
    end)

    owner = user_fixture()
    organization = organization_fixture(%{user: owner})

    %{owner: owner, organization: organization}
  end

  defp invite(organization, owner, email \\ nil) do
    Organizations.create_invitation(
      organization,
      %{
        email: email || "invitee-#{System.unique_integer([:positive])}@example.com",
        role: "member"
      },
      owner
    )
  end

  describe "seat limits" do
    test "pending invitations hold seats", %{owner: owner, organization: organization} do
      app_entitlement_fixture(organization, %{seat_limit: 3})

      assert {:ok, _} = invite(organization, owner)
      assert {:ok, _} = invite(organization, owner)
      # owner + 2 pending = 3 seats taken
      assert {:error, :seat_limit_reached} = invite(organization, owner)
    end

    test "a cancelled invitation frees its seat", %{owner: owner, organization: organization} do
      app_entitlement_fixture(organization, %{seat_limit: 2})

      assert {:ok, invitation} = invite(organization, owner)
      assert {:error, :seat_limit_reached} = invite(organization, owner)

      {:ok, _} = Organizations.cancel_invitation(invitation)
      assert {:ok, _} = invite(organization, owner)
    end

    test "accepting an invitation is refused when the organization filled up meanwhile", %{
      owner: owner,
      organization: organization
    } do
      app_entitlement_fixture(organization, %{seat_limit: 2})
      invitee = user_fixture()
      assert {:ok, invitation} = invite(organization, owner, invitee.email)

      # The plan shrinks (or someone else joins) before the invitee accepts.
      app_entitlement_fixture(organization, %{seat_limit: 1})

      assert {:error, :seat_limit_reached} = Organizations.accept_invitation(invitation, invitee)
      assert is_nil(Organizations.get_membership_for_user(invitee))
    end

    test "joining directly respects the limit", %{organization: organization} do
      app_entitlement_fixture(organization, %{seat_limit: 1})

      assert {:error, :seat_limit_reached} =
               Organizations.join_organization(organization, user_fixture(), "member")
    end

    test "no limit on the plan, or billing disabled, means no restriction", %{
      owner: owner,
      organization: organization
    } do
      app_entitlement_fixture(organization, %{seat_limit: nil})
      for _ <- 1..3, do: assert({:ok, _} = invite(organization, owner))

      app_entitlement_fixture(organization, %{seat_limit: 1})
      Application.put_env(:trifle, :deployment_mode, :self_hosted)
      assert {:ok, _} = invite(organization, owner)
    end
  end

  describe "invitation links" do
    test "store only a hash of the token, and still resolve by the emailed token", %{
      owner: owner,
      organization: organization
    } do
      assert {:ok, invitation} = invite(organization, owner)
      assert is_binary(invitation.token)

      stored = Repo.get!(Organizations.OrganizationInvitation, invitation.id)
      assert is_nil(stored.token)
      assert stored.token_hash == :crypto.hash(:sha256, invitation.token)

      [raw] =
        Repo.all(
          from(i in "organization_invitations",
            where: i.token_hash == ^stored.token_hash,
            select: i.token
          )
        )

      assert is_nil(raw)

      assert %{id: id} = Organizations.get_invitation_by_token(invitation.token)
      assert id == invitation.id
      assert is_nil(Organizations.get_invitation_by_token("not-the-token"))
      refute inspect(invitation) =~ invitation.token
    end

    test "refreshing issues a new token and retires the old one", %{
      owner: owner,
      organization: organization
    } do
      {:ok, invitation} = invite(organization, owner)
      {:ok, refreshed} = Organizations.refresh_invitation(invitation)

      assert is_binary(refreshed.token)
      refute refreshed.token == invitation.token
      assert is_nil(Organizations.get_invitation_by_token(invitation.token))
      assert Organizations.get_invitation_by_token(refreshed.token)
    end

    test "can only be accepted by the invited email address", %{
      owner: owner,
      organization: organization
    } do
      invitee = user_fixture()
      bystander = user_fixture()
      {:ok, invitation} = invite(organization, owner, String.upcase(invitee.email))

      assert {:error, :email_mismatch} = Organizations.accept_invitation(invitation, bystander)
      assert is_nil(Organizations.get_membership_for_user(bystander))

      assert {:ok, membership} = Organizations.accept_invitation(invitation, invitee)
      assert membership.organization_id == organization.id
    end
  end

  describe "removing a member" do
    test "revokes the API tokens they created in the organization", %{
      owner: owner,
      organization: organization
    } do
      admin = user_fixture()
      {:ok, membership} = Organizations.create_membership(organization, admin, "admin")

      {:ok, admin_token, admin_value} =
        Organizations.create_organization_api_token(admin, %{
          name: "Admin's token",
          organization_id: organization.id,
          permissions: %{"wildcard" => %{"read" => true, "write" => true}}
        })

      {:ok, owner_token, _} =
        Organizations.create_organization_api_token(owner, %{
          name: "Owner's token",
          organization_id: organization.id
        })

      # Warm the auth cache, as a real request would.
      assert {:ok, _} = Organizations.get_api_token_auth(admin_value)

      assert {:ok, _} = Organizations.remove_member(membership)

      assert is_nil(Repo.get(OrganizationApiToken, admin_token.id))
      assert {:error, :not_found} = Organizations.get_api_token_auth(admin_value)
      assert Repo.get(OrganizationApiToken, owner_token.id)
    end
  end

  describe "password changes" do
    test "end CLI logins but keep service tokens", %{owner: owner, organization: organization} do
      {:ok, cli, _} =
        Organizations.create_organization_api_token(owner, %{
          name: "CLI",
          organization_id: organization.id,
          permissions: %{"manage" => true}
        })

      {:ok, ingest, _} =
        Organizations.create_organization_api_token(owner, %{
          name: "Ingest",
          organization_id: organization.id,
          permissions: %{"wildcard" => %{"read" => false, "write" => true}}
        })

      assert {:ok, _} =
               Accounts.reset_user_password(owner, %{
                 password: "a brand new password",
                 password_confirmation: "a brand new password"
               })

      assert is_nil(Repo.get(OrganizationApiToken, cli.id))
      assert Repo.get(OrganizationApiToken, ingest.id)
    end
  end

  describe "open sessions after a password change" do
    test "are told to disconnect on reset and on change", %{owner: owner} do
      for change <- [
            fn user ->
              Accounts.reset_user_password(user, %{
                password: "a brand new password",
                password_confirmation: "a brand new password"
              })
            end,
            fn user ->
              Accounts.update_user_password(user, "a brand new password", %{
                password: "yet another password",
                password_confirmation: "yet another password"
              })
            end
          ] do
        user = Repo.reload!(owner)
        token = Accounts.generate_user_session_token(user)
        topic = "users_sessions:#{Base.url_encode64(token)}"
        TrifleWeb.Endpoint.subscribe(topic)

        assert {:ok, _} = change.(user)

        assert_receive %Phoenix.Socket.Broadcast{topic: ^topic, event: "disconnect"}
        assert is_nil(Accounts.get_user_by_session_token(token))
      end
    end
  end

  describe "database cap under concurrency" do
    @tag timeout: 60_000
    test "parallel creates cannot exceed the cap" do
      alias Ecto.Adapters.SQL.Sandbox

      Application.put_env(:trifle, :max_databases_per_organization, 3)
      on_exit(fn -> Application.delete_env(:trifle, :max_databases_per_organization) end)

      # Real concurrency needs real connections and committed data, so this test
      # works outside the sandbox transaction and cleans up after itself.
      {organization, user} =
        Sandbox.unboxed_run(Repo, fn ->
          user = user_fixture()

          {organization_fixture(%{user: user, name: "Race #{System.unique_integer([:positive])}"}),
           user}
        end)

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.delete_all(
            from(d in Organizations.Database, where: d.organization_id == ^organization.id)
          )

          Repo.delete_all(
            from(m in Organizations.OrganizationMembership,
              where: m.organization_id == ^organization.id
            )
          )

          Repo.delete_all(from(o in Organizations.Organization, where: o.id == ^organization.id))
          Repo.delete_all(from(u in Trifle.Accounts.User, where: u.id == ^user.id))
        end)
      end)

      results =
        1..8
        |> Enum.map(fn n ->
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              Organizations.create_database(%{
                "organization_id" => organization.id,
                "display_name" => "race-#{n}",
                "driver" => "sqlite",
                "file_path" => "race-#{n}.sqlite"
              })
            end)
          end)
        end)
        |> Task.await_many(30_000)

      created = Enum.count(results, &match?({:ok, _}, &1))

      stored =
        Sandbox.unboxed_run(Repo, fn ->
          Repo.one(
            from(d in Organizations.Database,
              where: d.organization_id == ^organization.id,
              select: count(d.id)
            )
          )
        end)

      assert created == 3
      assert stored == 3
    end
  end

  describe "the manage permission on update" do
    setup %{owner: owner, organization: organization} do
      {:ok, token, _} =
        Organizations.create_organization_api_token(owner, %{
          name: "CLI",
          organization_id: organization.id,
          permissions: %{"manage" => true}
        })

      %{token: token}
    end

    test "an explicit false removes it", %{token: token} do
      for permissions <- [%{"manage" => false}, %{manage: false}, %{"manage" => "false"}] do
        {:ok, managing} =
          Organizations.update_organization_api_token(token, %{permissions: %{"manage" => true}})

        assert Organizations.token_can_manage?(managing)

        {:ok, updated} =
          Organizations.update_organization_api_token(managing, %{permissions: permissions})

        refute Organizations.token_can_manage?(updated),
               "manage survived #{inspect(permissions)}"
      end
    end

    test "leaving it out keeps it, as the web form does", %{token: token} do
      {:ok, updated} =
        Organizations.update_organization_api_token(token, %{
          permissions: %{"wildcard" => %{"read" => true, "write" => false}, "sources" => %{}}
        })

      assert Organizations.token_can_manage?(updated)
      assert updated.permissions["wildcard"]["read"] == true
    end
  end

  describe "database ownership" do
    test "an update cannot move a database to another organization", %{
      organization: organization
    } do
      database = database_fixture(%{organization: organization})
      other_org = organization_fixture(%{name: "Other Org"})

      for attrs <- [
            %{"organization_id" => other_org.id, "display_name" => "Renamed"},
            %{organization_id: other_org.id, display_name: "Renamed"}
          ] do
        assert {:ok, updated} = Organizations.update_database(database, attrs)
        assert updated.display_name == "Renamed"
        assert updated.organization_id == organization.id
        assert Repo.reload!(database).organization_id == organization.id
      end
    end
  end

  describe "database cap" do
    setup do
      Application.put_env(:trifle, :max_databases_per_organization, 1)
      on_exit(fn -> Application.delete_env(:trifle, :max_databases_per_organization) end)
      :ok
    end

    test "holds for every creation path", %{organization: organization} do
      attrs = fn name ->
        %{"display_name" => name, "driver" => "sqlite", "file_path" => "#{name}.sqlite"}
      end

      assert {:ok, _} = Organizations.create_database_for_org(organization, attrs.("first"))

      # The path used by the browser form and the bootstrap API.
      assert {:error, changeset} =
               Organizations.create_database(
                 Map.put(attrs.("second"), "organization_id", organization.id)
               )

      assert {message, _} = changeset.errors[:display_name]
      assert message =~ "maximum of 1 databases"

      assert {:error, _} = Organizations.create_database_for_org(organization, attrs.("third"))

      other_org = organization_fixture(%{name: "Roomy Org"})
      assert {:ok, _} = Organizations.create_database_for_org(other_org, attrs.("theirs"))
    end
  end

  describe "SSO sign-in to an account nobody confirmed" do
    test "discards the password, sessions and tokens of whoever registered it", %{
      organization: organization
    } do
      email = "victim-#{System.unique_integer([:positive])}@example.com"
      squatter = user_fixture(%{email: email})
      assert is_nil(squatter.confirmed_at)

      session_token = Accounts.generate_user_session_token(squatter)

      {:ok, token, _} =
        Organizations.create_organization_api_token(squatter, %{
          name: "Squatter",
          organization_id: organization.id
        })

      assert {:ok, user} = Accounts.get_or_create_user_for_sso(email, %{name: "Real Owner"})

      assert user.id == squatter.id
      assert user.confirmed_at
      assert is_nil(Accounts.get_user_by_email_and_password(email, valid_user_password()))
      assert is_nil(Accounts.get_user_by_session_token(session_token))
      assert is_nil(Repo.get(OrganizationApiToken, token.id))
    end

    test "leaves an already confirmed account's password alone" do
      user = user_fixture()
      {:ok, user} = user |> Trifle.Accounts.User.confirm_changeset() |> Repo.update()

      assert {:ok, _} = Accounts.get_or_create_user_for_sso(user.email, %{})
      assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "protected attributes" do
    test "a project update cannot move the project or touch billing fields", %{
      owner: owner,
      organization: organization
    } do
      project = project_fixture(%{user: owner, organization: organization})
      other_org = organization_fixture(%{name: "Other Org"})

      assert {:ok, updated} =
               Organizations.update_project(project, %{
                 "name" => "Renamed",
                 "organization_id" => other_org.id,
                 "project_cluster_id" => Ecto.UUID.generate(),
                 "billing_state" => "active",
                 "billing_required" => false
               })

      assert updated.name == "Renamed"
      assert updated.organization_id == project.organization_id
      assert updated.project_cluster_id == project.project_cluster_id
      assert updated.billing_state == project.billing_state
      assert updated.billing_required == project.billing_required
    end
  end
end
