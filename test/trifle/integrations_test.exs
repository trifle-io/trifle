defmodule Trifle.IntegrationsTest do
  use Trifle.DataCase

  alias Trifle.AccountsFixtures
  alias Trifle.Integrations
  alias Trifle.Integrations.DiscordChannel
  alias Trifle.Integrations.SlackChannel
  alias Trifle.Organizations

  describe "Slack installations" do
    setup do
      user = AccountsFixtures.user_fixture()

      {:ok, organization, _membership} =
        Organizations.create_organization_with_owner(%{name: "Acme Widgets"}, user)

      %{user: user, organization: organization}
    end

    test "create_or_update_slack_installation/3 inserts a record", %{
      organization: organization,
      user: user
    } do
      payload = slack_payload(team_id: "T123", team_name: "Growth Ops")

      assert {:ok, installation} =
               Integrations.create_or_update_slack_installation(
                 organization.id,
                 user.id,
                 payload
               )

      assert installation.organization_id == organization.id
      assert installation.team_id == "T123"
      assert installation.team_name == "Growth Ops"
      assert installation.reference == "growth_ops"
      assert installation.bot_access_token == "xoxb-test-token"
      assert installation.settings["incoming_webhook"]["channel_id"] == "C123"
    end

    test "create_or_update_slack_installation/3 updates existing installation", %{
      organization: organization,
      user: user
    } do
      payload =
        slack_payload(team_id: "T200", team_name: "Marketing Crew", access_token: "xoxb-old")

      {:ok, installation} =
        Integrations.create_or_update_slack_installation(organization.id, user.id, payload)

      update_payload =
        slack_payload(
          team_id: "T200",
          team_name: "Marketing All Hands",
          access_token: "xoxb-new-token",
          bot_user_id: "B999"
        )

      assert {:ok, updated} =
               Integrations.create_or_update_slack_installation(
                 organization.id,
                 user.id,
                 update_payload
               )

      assert updated.id == installation.id
      assert updated.team_name == "Marketing All Hands"
      assert updated.bot_access_token == "xoxb-new-token"
      assert updated.reference == installation.reference
      assert updated.bot_user_id == "B999"
    end

    test "create_or_update_slack_installation/3 derives unique references", %{
      organization: organization,
      user: user
    } do
      {:ok, first} =
        Integrations.create_or_update_slack_installation(
          organization.id,
          user.id,
          slack_payload(team_id: "T300", team_name: "Operations")
        )

      {:ok, second} =
        Integrations.create_or_update_slack_installation(
          organization.id,
          user.id,
          slack_payload(team_id: "T301", team_name: "Operations")
        )

      {:ok, numeric_prefix} =
        Integrations.create_or_update_slack_installation(
          organization.id,
          user.id,
          slack_payload(team_id: "T302", team_name: "123 Response")
        )

      assert first.reference == "operations"
      assert second.reference == "operations_1"
      assert numeric_prefix.reference == "slack_123_response"
    end
  end

  describe "Discord installations" do
    setup do
      user = AccountsFixtures.user_fixture()

      {:ok, organization, _membership} =
        Organizations.create_organization_with_owner(%{name: "Acme Widgets"}, user)

      %{user: user, organization: organization}
    end

    test "create_or_update_discord_installation/3 inserts a record", %{
      organization: organization,
      user: user
    } do
      payload = discord_payload(guild_id: "12345", guild_name: "Notifications")

      assert {:ok, installation} =
               Integrations.create_or_update_discord_installation(
                 organization.id,
                 user.id,
                 payload
               )

      assert installation.organization_id == organization.id
      assert installation.guild_id == "12345"
      assert installation.guild_name == "Notifications"
      assert installation.reference == "notifications"
      assert installation.permissions == "52224"
    end

    test "create_or_update_discord_installation/3 updates existing installation", %{
      organization: organization,
      user: user
    } do
      payload = discord_payload(guild_id: "777", guild_name: "Incidents")

      {:ok, installation} =
        Integrations.create_or_update_discord_installation(organization.id, user.id, payload)

      update_payload =
        discord_payload(guild_id: "777", guild_name: "Incident Response", permissions: "1024")

      assert {:ok, updated} =
               Integrations.create_or_update_discord_installation(
                 organization.id,
                 user.id,
                 update_payload
               )

      assert updated.id == installation.id
      assert updated.guild_name == "Incident Response"
      assert updated.reference == installation.reference
      assert updated.permissions == "1024"
    end

    test "create_or_update_discord_installation/3 derives unique references", %{
      organization: organization,
      user: user
    } do
      {:ok, first} =
        Integrations.create_or_update_discord_installation(
          organization.id,
          user.id,
          discord_payload(guild_id: "900", guild_name: "Operations")
        )

      {:ok, second} =
        Integrations.create_or_update_discord_installation(
          organization.id,
          user.id,
          discord_payload(guild_id: "901", guild_name: "Operations")
        )

      {:ok, numeric_prefix} =
        Integrations.create_or_update_discord_installation(
          organization.id,
          user.id,
          discord_payload(guild_id: "902", guild_name: "123 Response")
        )

      assert first.reference == "operations"
      assert second.reference == "operations_1"
      assert numeric_prefix.reference == "discord_123_response"
    end
  end

  describe "Discord channels" do
    setup do
      user = AccountsFixtures.user_fixture()

      {:ok, organization, _membership} =
        Organizations.create_organization_with_owner(%{name: "Alerts"}, user)

      {:ok, installation} =
        Integrations.create_or_update_discord_installation(
          organization.id,
          user.id,
          discord_payload(guild_id: "9999", guild_name: "Incident Desk")
        )

      channel =
        %DiscordChannel{
          discord_installation_id: installation.id,
          channel_id: "1234567890",
          name: "alerts",
          channel_type: "text",
          is_thread: false,
          enabled: false
        }
        |> Repo.insert!()

      %{organization: organization, channel: channel}
    end

    test "update_discord_channel_enabled/3 toggles the enabled flag", %{
      organization: organization,
      channel: channel
    } do
      assert {:ok, updated} =
               Integrations.update_discord_channel_enabled(organization.id, channel.id, true)

      assert updated.enabled

      assert {:ok, disabled} =
               Integrations.update_discord_channel_enabled(organization.id, channel.id, false)

      refute disabled.enabled
    end

    test "update_discord_channel_enabled/3 enforces organization ownership", %{channel: channel} do
      other_user = AccountsFixtures.user_fixture()

      {:ok, other_org, _} =
        Organizations.create_organization_with_owner(%{name: "Other Org"}, other_user)

      assert {:error, :not_found} ==
               Integrations.update_discord_channel_enabled(other_org.id, channel.id, true)
    end
  end

  describe "Slack channels" do
    setup do
      user = AccountsFixtures.user_fixture()

      {:ok, organization, _membership} =
        Organizations.create_organization_with_owner(%{name: "Alerts"}, user)

      {:ok, installation} =
        Integrations.create_or_update_slack_installation(
          organization.id,
          user.id,
          slack_payload(team_id: "T400", team_name: "Incident Desk")
        )

      channel =
        %SlackChannel{
          slack_installation_id: installation.id,
          channel_id: "C-alerts",
          name: "alerts",
          channel_type: "public_channel",
          is_private: false,
          enabled: false
        }
        |> Repo.insert!()

      %{organization: organization, channel: channel}
    end

    test "update_slack_channel_enabled/3 toggles the enabled flag", %{
      organization: organization,
      channel: channel
    } do
      assert {:ok, updated} =
               Integrations.update_slack_channel_enabled(organization.id, channel.id, true)

      assert updated.enabled

      assert {:ok, disabled} =
               Integrations.update_slack_channel_enabled(organization.id, channel.id, false)

      refute disabled.enabled
    end

    test "update_slack_channel_enabled/3 enforces organization ownership", %{channel: channel} do
      other_user = AccountsFixtures.user_fixture()

      {:ok, other_org, _} =
        Organizations.create_organization_with_owner(%{name: "Other Org"}, other_user)

      assert {:error, :not_found} ==
               Integrations.update_slack_channel_enabled(other_org.id, channel.id, true)
    end
  end

  defp slack_payload(opts) do
    team_id = Keyword.fetch!(opts, :team_id)
    team_name = Keyword.fetch!(opts, :team_name)

    %{
      "access_token" => Keyword.get(opts, :access_token, "xoxb-test-token"),
      "bot_user_id" => Keyword.get(opts, :bot_user_id, "B123"),
      "scope" => Keyword.get(opts, :scope, "chat:write,channels:read"),
      "team" => %{
        "id" => team_id,
        "name" => team_name,
        "domain" => Keyword.get(opts, :team_domain, "example")
      },
      "incoming_webhook" => %{
        "channel" => Keyword.get(opts, :incoming_channel, "#general"),
        "channel_id" => Keyword.get(opts, :incoming_channel_id, "C123"),
        "configuration_url" => "https://example.com/config",
        "url" => "https://example.com/webhook"
      },
      "authed_user" => %{"id" => "U123"},
      "app_id" => "A123"
    }
  end

  defp discord_payload(opts) do
    guild_id = Keyword.fetch!(opts, :guild_id)
    guild_name = Keyword.fetch!(opts, :guild_name)

    %{
      "guild_id" => guild_id,
      "guild_name" => guild_name,
      "guild" => %{
        "id" => guild_id,
        "name" => guild_name,
        "icon" => Keyword.get(opts, :guild_icon)
      },
      "scope" => Keyword.get(opts, :scope, "bot identify guilds"),
      "permissions" => Keyword.get(opts, :permissions, "52224")
    }
  end

  describe "Slack bot token storage" do
    import Ecto.Query, only: [from: 2]

    defp raw_token(installation) do
      {:ok, id} = Ecto.UUID.dump(installation.id)

      Trifle.Repo.one(
        from(i in "slack_installations", where: i.id == ^id, select: i.bot_access_token)
      )
    end

    defp slack_installation!(token) do
      user = Trifle.AccountsFixtures.user_fixture()

      {:ok, organization, _} =
        Trifle.Organizations.create_organization_with_owner(
          %{name: "Slack Org #{System.unique_integer([:positive])}"},
          user
        )

      %Trifle.Integrations.SlackInstallation{}
      |> Trifle.Integrations.SlackInstallation.changeset(%{
        organization_id: organization.id,
        team_id: "T#{System.unique_integer([:positive])}",
        team_name: "Team",
        reference: "ref-#{System.unique_integer([:positive])}",
        bot_access_token: token
      })
      |> Trifle.Repo.insert!()
    end

    test "is encrypted at rest and never shown by inspect" do
      installation = slack_installation!("xoxb-secret-value")

      raw = raw_token(installation)
      refute raw == "xoxb-secret-value"
      refute String.contains?(raw, "xoxb")
      assert Trifle.Encrypted.MigratingBinary.encrypted?(raw)

      reloaded = Trifle.Repo.get!(Trifle.Integrations.SlackInstallation, installation.id)
      assert reloaded.bot_access_token == "xoxb-secret-value"
      refute inspect(reloaded) =~ "xoxb-secret-value"
    end

    test "legacy plaintext rows stay readable and can be encrypted in bulk" do
      installation = slack_installation!("xoxb-new")
      {:ok, id} = Ecto.UUID.dump(installation.id)

      # Simulate a row written before the column was encrypted.
      Trifle.Repo.update_all(from(i in "slack_installations", where: i.id == ^id),
        set: [bot_access_token: "xoxb-legacy-plain"]
      )

      reloaded = Trifle.Repo.get!(Trifle.Integrations.SlackInstallation, installation.id)
      assert reloaded.bot_access_token == "xoxb-legacy-plain"

      assert Trifle.Integrations.encrypt_legacy_slack_tokens() == 1
      assert Trifle.Integrations.encrypt_legacy_slack_tokens() == 0

      refute raw_token(installation) == "xoxb-legacy-plain"

      assert Trifle.Repo.get!(Trifle.Integrations.SlackInstallation, installation.id).bot_access_token ==
               "xoxb-legacy-plain"
    end
  end

  test "database credentials are redacted from inspect output" do
    database = %Trifle.Organizations.Database{
      host: "db.example.com",
      username: "admin-user",
      password: "hunter2-password",
      ssh_private_key: "-----BEGIN KEY-----"
    }

    output = inspect(database)

    assert output =~ "db.example.com"
    refute output =~ "hunter2-password"
    refute output =~ "admin-user"
    refute output =~ "BEGIN KEY"
  end
end
