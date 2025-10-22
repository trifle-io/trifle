defmodule Trifle.IntegrationsTest do
  use Trifle.DataCase

  alias Trifle.AccountsFixtures
  alias Trifle.Integrations
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
end
