defmodule Trifle.SystemNotificationsTest do
  use Trifle.DataCase, async: false
  use Oban.Testing, repo: Trifle.Repo

  import Swoosh.TestAssertions
  import Trifle.AccountsFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Accounts
  alias Trifle.Organizations
  alias Trifle.SystemNotifications

  setup do
    admin = user_fixture(%{email: "system-admin@example.com"})
    {:ok, admin} = Accounts.update_user_admin_status(admin.id, true)
    %{admin: admin}
  end

  test "delivers an extensible event to a current system admin", %{admin: admin} do
    assert :ok =
             SystemNotifications.enqueue(:database_checked, %{
               database_id: Ecto.UUID.generate(),
               database_name: "Analytics",
               organization_name: "Acme",
               driver: "postgres",
               status: "success",
               occurred_at: DateTime.utc_now()
             })

    assert_email_sent(
      to: admin.email,
      subject: "[Trifle System] Database check success: Analytics",
      text_body: ~r/Organization: Acme.*Result: success/s
    )
  end

  test "deduplicates dispatch by notification identity even when payload changes" do
    notification_id = "event:stable-id"

    Oban.Testing.with_testing_mode(:manual, fn ->
      for occurred_at <- [~U[2026-07-21 10:00:00Z], ~U[2026-07-21 10:01:00Z]] do
        assert :ok =
                 SystemNotifications.enqueue(
                   :user_created,
                   %{
                     user_id: Ecto.UUID.generate(),
                     email: "deduplicated@example.com",
                     occurred_at: occurred_at
                   },
                   idempotency_key: notification_id
                 )
      end

      assert [_job] =
               all_enqueued(
                 worker: Trifle.SystemNotifications.Jobs.Dispatch,
                 args: %{"notification_id" => notification_id}
               )
    end)
  end

  test "notifies for user, invitation, project, database, and database-check events", %{
    admin: admin
  } do
    {:ok, created_user} =
      Accounts.register_user(%{
        email: "new-user@example.com",
        password: "secure password"
      })

    assert_email_sent(
      to: admin.email,
      subject: "[Trifle System] User created: #{created_user.email}"
    )

    organization = organization_fixture(%{user: admin, name: "Acme"})

    {:ok, _invitation} =
      Organizations.create_invitation(
        organization,
        %{email: "invitee@example.com", role: "member"},
        admin
      )

    assert_email_sent(subject: "You're invited to join Acme on Trifle")

    assert_email_sent(
      to: admin.email,
      subject: "[Trifle System] User invited: invitee@example.com"
    )

    project = project_fixture(%{user: admin, organization: organization, name: "Events"})

    assert_email_sent(
      to: admin.email,
      subject: "[Trifle System] Project created: #{project.name}"
    )

    database =
      database_fixture(%{
        organization: organization,
        display_name: "Warehouse"
      })

    assert_email_sent(
      to: admin.email,
      subject: "[Trifle System] Database created: #{database.display_name}"
    )

    assert {:ok, checked_database, _setup_exists} =
             Organizations.check_database_status(database)

    assert_email_sent(
      to: admin.email,
      subject:
        "[Trifle System] Database check #{checked_database.last_check_status}: #{database.display_name}"
    )
  end

  test "invitation refresh sends the invitee email without another system event", %{admin: admin} do
    organization = organization_fixture(%{user: admin, name: "Acme"})

    {:ok, invitation} =
      Organizations.create_invitation(
        organization,
        %{email: "invitee@example.com", role: "member"},
        admin
      )

    assert_email_sent(subject: "You're invited to join Acme on Trifle")
    assert_email_sent(subject: "[Trifle System] User invited: invitee@example.com")

    assert {:ok, _refreshed} = Organizations.refresh_invitation(invitation)
    assert_email_sent(subject: "You're invited to join Acme on Trifle")
    refute_email_sent(subject: "[Trifle System] User invited: invitee@example.com")
  end
end
