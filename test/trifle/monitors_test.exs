defmodule Trifle.MonitorsTest do
  use Trifle.DataCase

  alias Trifle.AccountsFixtures
  alias Trifle.Monitors
  alias Trifle.Monitors.{Alert, Monitor}
  alias Trifle.Organizations
  alias Trifle.Integrations.SlackChannel
  alias Trifle.Integrations.SlackInstallation
  alias Trifle.Repo

  setup do
    user = AccountsFixtures.user_fixture()

    {:ok, organization, membership} =
      Organizations.create_organization_with_owner(%{name: "Acme Inc"}, user)

    {:ok, database} =
      Organizations.create_database_for_org(organization, %{
        display_name: "Primary DB",
        driver: "sqlite",
        file_path: "metrics.sqlite"
      })

    %{user: user, organization: organization, membership: membership, database: database}
  end

  describe "monitors" do
    test "list_monitors_for_membership/3 returns monitors for membership", %{
      user: user,
      membership: membership,
      database: database
    } do
      monitor = monitor_fixture(user, membership, database)

      assert [result] = Monitors.list_monitors_for_membership(user, membership)
      assert result.id == monitor.id
    end

    test "get_monitor_for_membership!/3 retrieves monitor scoped to membership", %{
      user: user,
      membership: membership,
      database: database
    } do
      monitor = monitor_fixture(user, membership, database)

      result = Monitors.get_monitor_for_membership!(membership, monitor.id)
      assert result.id == monitor.id
    end

    test "create_monitor_for_membership/3 persists alert monitor", %{
      user: user,
      membership: membership,
      database: database
    } do
      attrs = %{
        "name" => "Error Spike",
        "type" => "alert",
        "description" => "Alerts when error count spikes",
        "alert_metric_key" => "errors.total",
        "alert_metric_path" => "$.service.api",
        "alert_timeframe" => "30m",
        "alert_granularity" => "5m",
        "delivery_channels" => [
          %{"channel" => "email", "label" => "On-call", "target" => "oncall@example.com"}
        ],
        "source_type" => "database",
        "source_id" => database.id
      }

      assert {:ok, %Monitor{} = monitor} =
               Monitors.create_monitor_for_membership(user, membership, attrs)

      assert monitor.name == "Error Spike"
      assert monitor.alert_metric_key == "errors.total"
      assert monitor.delivery_channels |> List.first() |> Map.get(:target) == "oncall@example.com"
      assert monitor.organization_id == membership.organization_id
      assert monitor.source_type == :database
      assert monitor.source_id == database.id
      assert monitor.user_id == user.id
      refute monitor.locked
      assert monitor.alert_notify_every == 1
      assert Monitors.delivery_media_types_from_media(monitor.delivery_media) == [:pdf]
    end

    test "create_monitor_for_membership/3 returns error changeset when data invalid", %{
      user: user,
      membership: membership
    } do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Monitors.create_monitor_for_membership(user, membership, %{})

      refute changeset.valid?
      assert %{name: {"can't be blank", _}} = errors_on(changeset)
    end

    test "update_monitor_for_membership/3 modifies an existing monitor", %{
      user: user,
      membership: membership,
      database: database
    } do
      monitor = monitor_fixture(user, membership, database)

      assert {:ok, %Monitor{} = updated} =
               Monitors.update_monitor_for_membership(monitor, membership, %{
                 name: "Latency Guard",
                 delivery_media: [%{medium: :png_dark}]
               })

      assert updated.name == "Latency Guard"
      assert Monitors.delivery_media_types_from_media(updated.delivery_media) == [:png_dark]
    end

    test "update_monitor_for_membership/3 returns forbidden when monitor locked for non owner", %{
      user: user,
      membership: membership,
      organization: organization,
      database: database
    } do
      monitor = monitor_fixture(user, membership, database)

      {:ok, monitor} =
        Monitors.update_monitor_for_membership(monitor, membership, %{locked: true})

      other_user = AccountsFixtures.user_fixture()

      {:ok, other_membership} =
        Organizations.create_membership(organization, other_user, "member")

      assert {:error, :forbidden} =
               Monitors.update_monitor_for_membership(monitor, other_membership, %{
                 name: "Blocked"
               })
    end

    test "update_monitor_for_membership/3 allows owner to modify when locked", %{
      user: user,
      membership: membership,
      database: database
    } do
      monitor = monitor_fixture(user, membership, database)

      {:ok, monitor} =
        Monitors.update_monitor_for_membership(monitor, membership, %{locked: true})

      assert {:ok, %Monitor{} = updated} =
               Monitors.update_monitor_for_membership(monitor, membership, %{
                 description: "Still editable"
               })

      assert updated.description == "Still editable"
      assert updated.locked
    end

    test "update_monitor_for_membership/3 updates alert notification cadence", %{
      user: user,
      membership: membership,
      database: database
    } do
      monitor = monitor_fixture(user, membership, database)

      assert {:ok, %Monitor{} = updated} =
               Monitors.update_monitor_for_membership(monitor, membership, %{
                 alert_notify_every: 5
               })

      assert updated.alert_notify_every == 5
    end

    test "update_monitor_for_membership/3 rejects out of range alert cadence", %{
      user: user,
      membership: membership,
      database: database
    } do
      monitor = monitor_fixture(user, membership, database)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Monitors.update_monitor_for_membership(monitor, membership, %{
                 alert_notify_every: 0
               })

      assert %{alert_notify_every: {"must be greater than or equal to %{number}", _}} =
               errors_on(changeset)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Monitors.update_monitor_for_membership(monitor, membership, %{
                 alert_notify_every: 101
               })

      assert %{alert_notify_every: {"must be less than or equal to %{number}", _}} =
               errors_on(changeset)
    end

    test "delete_monitor_for_membership/2 removes monitor", %{
      user: user,
      membership: membership,
      database: database
    } do
      monitor = monitor_fixture(user, membership, database)

      assert {:ok, %Monitor{}} = Monitors.delete_monitor_for_membership(monitor, membership)

      assert_raise Ecto.NoResultsError, fn ->
        Monitors.get_monitor_for_membership!(membership, monitor.id)
      end
    end

    test "delete_monitor_for_membership/2 removes associated alerts", %{
      user: user,
      membership: membership,
      database: database
    } do
      monitor = monitor_fixture(user, membership, database)

      {:ok, _alert} =
        Monitors.create_alert(monitor, membership, %{
          "analysis_strategy" => "range",
          "settings" => %{
            "range_min_value" => "10",
            "range_max_value" => "20"
          }
        })

      assert {:ok, %Monitor{}} = Monitors.delete_monitor_for_membership(monitor, membership)

      refute Repo.get_by(Alert, monitor_id: monitor.id)
    end

    test "delete_monitor_for_membership/2 returns forbidden when monitor locked for another member",
         %{
           user: user,
           membership: membership,
           organization: organization,
           database: database
         } do
      monitor = monitor_fixture(user, membership, database)

      {:ok, monitor} =
        Monitors.update_monitor_for_membership(monitor, membership, %{locked: true})

      other_user = AccountsFixtures.user_fixture()

      {:ok, other_membership} =
        Organizations.create_membership(organization, other_user, "member")

      assert {:error, :forbidden} =
               Monitors.delete_monitor_for_membership(monitor, other_membership)
    end

    test "create_alert/3 returns forbidden when monitor locked for another member", %{
      user: user,
      membership: membership,
      organization: organization,
      database: database
    } do
      monitor = monitor_fixture(user, membership, database)

      {:ok, monitor} =
        Monitors.update_monitor_for_membership(monitor, membership, %{locked: true})

      other_user = AccountsFixtures.user_fixture()

      {:ok, other_membership} =
        Organizations.create_membership(organization, other_user, "member")

      params = %{
        "analysis_strategy" => "threshold",
        "settings" => %{"threshold_direction" => "above", "threshold_value" => "10"}
      }

      assert {:error, :forbidden} = Monitors.create_alert(monitor, other_membership, params)
    end
  end

  describe "delivery options" do
    test "delivery_options_for_membership/1 includes organization members", %{
      membership: membership,
      user: user
    } do
      options = Monitors.delivery_options_for_membership(membership)

      assert Enum.any?(options, fn option -> option.handle == "email#" <> user.email end)
    end

    test "delivery_channels_from_handles/2 builds channel maps", %{
      membership: membership,
      organization: organization,
      user: user
    } do
      installation =
        %SlackInstallation{}
        |> SlackInstallation.changeset(%{
          organization_id: organization.id,
          team_id: "T123",
          team_name: "Trifle Team",
          reference: "slack_trifle",
          bot_access_token: "xoxb-test",
          installed_by_user_id: user.id
        })
        |> Repo.insert!()

      channel =
        %SlackChannel{}
        |> SlackChannel.changeset(%{
          slack_installation_id: installation.id,
          channel_id: "C456",
          name: "robots",
          channel_type: "public_channel",
          enabled: true
        })
        |> Repo.insert!()

      handles = ["email#" <> user.email, "slack_#{installation.reference}##{channel.name}"]

      {channels, invalid} =
        Monitors.delivery_channels_from_handles(handles, membership, [])

      assert invalid == []
      assert Enum.count(channels) == 2

      assert Enum.any?(channels, fn channel_map ->
               Map.get(channel_map, "target") == user.email
             end)

      slack_entry = Enum.find(channels, fn map -> Map.get(map, "channel") == "slack_webhook" end)
      assert slack_entry
      assert Map.get(slack_entry, "target") == channel.channel_id

      handles_roundtrip = Monitors.delivery_handles_from_channels(channels)
      assert Enum.sort(handles_roundtrip) == Enum.sort(handles)
    end
  end

  describe "monitor executions" do
    test "create_execution/2 stores trigger and list_recent_executions/2 fetches it", %{
      user: user,
      membership: membership,
      database: database
    } do
      monitor = monitor_fixture(user, membership, database)

      {:ok, execution} =
        Monitors.create_execution(monitor, %{
          status: "triggered",
          summary: "Threshold breached",
          details: %{"threshold" => 120, "observed" => 145}
        })

      assert execution.monitor_id == monitor.id

      [recent] = Monitors.list_recent_executions(monitor)
      assert recent.id == execution.id
      assert recent.summary == "Threshold breached"
    end
  end

  defp monitor_fixture(user, membership, database, attrs \\ %{}) do
    defaults = %{
      "name" => "Latency Watch",
      "type" => "alert",
      "description" => "Keeps an eye on API latency",
      "alert_metric_key" => "latency.p95",
      "alert_metric_path" => "$.global",
      "alert_timeframe" => "15m",
      "alert_granularity" => "5m",
      "delivery_channels" => [
        %{"channel" => "email", "label" => "Primary", "target" => "alerts@example.com"}
      ],
      "source_type" => "database",
      "source_id" => database.id
    }

    {:ok, monitor} =
      defaults
      |> Map.merge(attrs)
      |> Monitors.create_monitor_for_membership(user, membership)

    monitor
  end
end
