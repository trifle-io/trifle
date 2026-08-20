defmodule Trifle.Monitors.TestDeliveryTest do
  use Trifle.DataCase

  import Trifle.BillingFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Monitors
  alias Trifle.Monitors.{Alert, Monitor}
  alias Trifle.Monitors.Alert.Settings
  alias Trifle.Organizations
  alias Trifle.Monitors.Monitor.DeliveryChannel
  alias Swoosh.Email
  alias Swoosh.Attachment

  defmodule FakeLayoutBuilder do
    alias Trifle.Exports.Series.Result, as: SeriesResult
    alias TrifleApp.Exports.Layout

    def build(_monitor, opts) do
      send(self(), {:built_full_layout, opts})
      {:ok, Layout.new(id: "monitor", kind: :monitor)}
    end

    def build_widget(_monitor, _widget_id, _opts) do
      {:ok, Layout.new(id: "widget", kind: :widget)}
    end

    def build_alert_snapshot(_monitor, alert, source_paths, opts) do
      send(self(), {:built_alert_snapshot, alert.id, source_paths, opts})
      {:ok, Layout.new(id: "alert-snapshot", kind: :monitor)}
    end

    def series_export(_monitor, _opts) do
      export = %SeriesResult{series: %{at: [], values: []}, raw: %{series: %{}}}
      {:ok, %{export: export, timeframe: %{}}}
    end
  end

  defmodule FakeExporter do
    def export_layout_pdf(_layout), do: {:ok, "PDF"}
    def export_layout_pdf(_layout, _opts), do: {:ok, "PDF"}
    def export_layout_png(_layout), do: {:ok, "PNG"}
    def export_layout_png(_layout, _opts), do: {:ok, "PNG"}
  end

  defmodule FakeMailer do
    def deliver(%Email{} = email) do
      send(self(), {:delivered_email, email})
      {:ok, %{id: "stub"}}
    end
  end

  setup do
    user = AccountsFixtures.user_fixture()

    {:ok, organization, membership} =
      Organizations.create_organization_with_owner(%{name: "Acme Inc"}, user)

    app_entitlement_fixture(organization)

    {:ok, database} =
      Organizations.create_database_for_org(organization, %{
        display_name: "Primary DB",
        driver: "sqlite",
        file_path: "metrics.sqlite"
      })

    %{user: user, membership: membership, database: database}
  end

  test "returns error when no delivery channels configured", %{
    membership: membership,
    user: user,
    database: database
  } do
    monitor = simple_monitor_fixture(user, membership, database)

    monitor = %Monitor{monitor | delivery_channels: []}

    assert {:error, message} = Monitors.test_deliver_monitor(monitor)
    assert message =~ "No delivery targets"
  end

  test "sends preview via email when channel configured", %{
    membership: membership,
    user: user,
    database: database
  } do
    monitor = simple_monitor_fixture(user, membership, database)

    assert {:ok, result} =
             Monitors.test_deliver_monitor(monitor,
               export_params: %{"timeframe" => "24h"},
               layout_builder: FakeLayoutBuilder,
               exporter: FakeExporter,
               mailer: FakeMailer
             )

    assert [
             %{
               handle: handle,
               type: :email,
               attachments: [
                 %{
                   medium: :pdf,
                   content_type: "application/pdf",
                   size: 3,
                   filename: result_filename
                 }
               ]
             }
           ] = result.successes

    assert handle =~ "email#"
    assert result.failures == []

    assert_received {:delivered_email, %Email{} = email}
    assert email.subject =~ "Monitor preview"
    assert is_binary(email.text_body)
    assert is_binary(email.html_body)

    assert [%Attachment{filename: attachment_filename, content_type: "application/pdf"}] =
             email.attachments

    assert is_binary(attachment_filename)
    assert result_filename == attachment_filename

    assert [
             %{
               handle: ^handle,
               type: :email,
               files: [
                 %{
                   medium: :pdf,
                   content_type: "application/pdf",
                   size: 3,
                   filename: filename
                 }
               ]
             }
           ] = result.summary.attachments

    assert is_binary(filename)
    assert filename == result_filename
  end

  test "supports CSV and JSON delivery media", %{
    membership: membership,
    user: user,
    database: database
  } do
    monitor = simple_monitor_fixture(user, membership, database)

    {:ok, monitor} =
      Monitors.update_monitor_for_membership(monitor, membership, %{
        delivery_media: [%{medium: :file_csv}, %{medium: :file_json}]
      })

    assert {:ok, result} =
             Monitors.test_deliver_monitor(monitor,
               export_params: %{"timeframe" => "7d"},
               layout_builder: FakeLayoutBuilder,
               exporter: FakeExporter,
               mailer: FakeMailer
             )

    assert [
             %{
               attachments: attachments,
               type: :email
             }
           ] = result.successes

    assert Enum.any?(attachments, &match?(%{medium: :file_csv, content_type: "text/csv"}, &1))

    assert Enum.any?(
             attachments,
             &match?(%{medium: :file_json, content_type: "application/json"}, &1)
           )

    assert_received {:delivered_email, %Email{} = email}

    filenames = Enum.map(email.attachments, & &1.filename)
    assert Enum.count(email.attachments) == 2
    assert Enum.any?(email.attachments, &(&1.content_type == "text/csv"))
    assert Enum.any?(email.attachments, &(&1.content_type == "application/json"))
    assert Enum.all?(filenames, &is_binary/1)
  end

  test "triggered alert delivery filters visual exports and includes series context", %{
    membership: membership,
    user: user,
    database: database
  } do
    monitor = simple_monitor_fixture(user, membership, database)
    alert = threshold_alert()

    triggered_series = [
      %{
        name: "Success Rate: commodity__resellers__schedule_job",
        source_path: "__expression__.2.commodity__resellers__schedule_job",
        summary:
          "Latest reading 𝑥=0 at 2026-08-20 07:00:00; threshold demands 𝑥 ≤ 98. Threshold breached in the latest window.",
        data: [[1_776_927_600_000, 0.0]]
      }
    ]

    assert {:ok, _result} =
             Monitors.test_deliver_alert(monitor, alert,
               trigger_type: :triggered,
               triggered_series: triggered_series,
               export_params: %{
                 from: ~U[2026-08-20 03:30:00Z],
                 to: ~U[2026-08-20 07:30:00Z]
               },
               media_types: [:png_light],
               layout_builder: FakeLayoutBuilder,
               exporter: FakeExporter,
               mailer: FakeMailer
             )

    assert_received {:built_alert_snapshot, "alert-1",
                     ["__expression__.2.commodity__resellers__schedule_job"], _opts}

    assert_received {:delivered_email, %Email{} = email}
    assert email.subject =~ "🚨 Triggered"
    assert email.text_body =~ "Triggered series (1):"
    assert email.text_body =~ "Success Rate: commodity__resellers__schedule_job"
    assert email.text_body =~ "Latest reading 𝑥=0 at 2026-08-20 07:00:00"
    assert email.text_body =~ "Window: 2026-08-20 03:30:00 → 2026-08-20 07:30:00"
  end

  test "triggered CSV and JSON exports contain only triggered resolved outputs", %{
    membership: membership,
    user: user,
    database: database
  } do
    monitor = simple_monitor_fixture(user, membership, database)
    alert = threshold_alert()

    triggered_series = [
      %{
        name: "Success Rate: schedule_job",
        source_path: "__expression__.2.schedule_job",
        summary: "Threshold breached.",
        data: [
          [1_776_927_000_000, 100.0],
          [1_776_927_600_000, 0.0]
        ]
      }
    ]

    assert {:ok, _result} =
             Monitors.test_deliver_alert(monitor, alert,
               trigger_type: :triggered,
               triggered_series: triggered_series,
               media_types: [:file_csv, :file_json],
               layout_builder: FakeLayoutBuilder,
               exporter: FakeExporter,
               mailer: FakeMailer
             )

    assert_received {:delivered_email, %Email{} = email}
    csv = Enum.find(email.attachments, &(&1.content_type == "text/csv"))
    json = Enum.find(email.attachments, &(&1.content_type == "application/json"))

    assert csv.data =~ "Success Rate: schedule_job"
    refute csv.data =~ "latency.p95"

    assert %{"values" => values} = Jason.decode!(json.data)
    assert Enum.all?(values, &(Map.keys(&1) == ["Success Rate: schedule_job"]))
    assert Enum.map(values, &Map.fetch!(&1, "Success Rate: schedule_job")) == [100.0, 0.0]
  end

  test "previewed and recovered alerts keep full exports without triggered-series copy", %{
    membership: membership,
    user: user,
    database: database
  } do
    monitor = simple_monitor_fixture(user, membership, database)
    alert = threshold_alert()

    triggered_series = [
      %{
        name: "Success Rate: schedule_job",
        source_path: "__expression__.2.schedule_job",
        summary: "Threshold breached.",
        data: [[1_776_927_600_000, 0.0]]
      }
    ]

    for trigger_type <- [:previewed, :recovered] do
      assert {:ok, _result} =
               Monitors.test_deliver_alert(monitor, alert,
                 trigger_type: trigger_type,
                 triggered_series: triggered_series,
                 media_types: [:png_light],
                 layout_builder: FakeLayoutBuilder,
                 exporter: FakeExporter,
                 mailer: FakeMailer
               )

      assert_received {:built_full_layout, _opts}
      refute_received {:built_alert_snapshot, _alert_id, _source_paths, _opts}

      assert_received {:delivered_email, %Email{} = email}
      refute email.text_body =~ "Triggered series"
    end
  end

  defp simple_monitor_fixture(user, membership, database) do
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
      Monitors.create_monitor_for_membership(user, membership, defaults)

    %Monitor{
      monitor
      | delivery_channels: Enum.map(monitor.delivery_channels, &normalize_channel/1)
    }
  end

  defp threshold_alert do
    %Alert{
      id: "alert-1",
      analysis_strategy: :threshold,
      settings: %Settings{threshold_direction: :below, threshold_value: 98.0}
    }
  end

  defp normalize_channel(%DeliveryChannel{} = channel), do: channel
  defp normalize_channel(other), do: struct(DeliveryChannel, other)
end
