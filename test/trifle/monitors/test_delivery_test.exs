defmodule Trifle.Monitors.TestDeliveryTest do
  use Trifle.DataCase

  alias Trifle.AccountsFixtures
  alias Trifle.Monitors
  alias Trifle.Monitors.Monitor
  alias Trifle.Organizations
  alias Trifle.Monitors.Monitor.DeliveryChannel
  alias Swoosh.Email
  alias Swoosh.Attachment

  defmodule FakeLayoutBuilder do
    alias TrifleApp.Exports.Layout

    def build(_monitor, _opts) do
      {:ok, Layout.new(id: "monitor", kind: :monitor)}
    end

    def build_widget(_monitor, _widget_id, _opts) do
      {:ok, Layout.new(id: "widget", kind: :widget)}
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

  defp normalize_channel(%DeliveryChannel{} = channel), do: channel
  defp normalize_channel(other), do: struct(DeliveryChannel, other)
end
