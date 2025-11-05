defmodule Trifle.Repo.Migrations.AddMonitorAlertNotificationControls do
  use Ecto.Migration

  def change do
    alter table(:monitors) do
      add :alert_notify_every, :integer, null: false, default: 1
    end

    alter table(:monitor_alerts) do
      add :continuous_trigger_count, :integer, null: false, default: 0
    end
  end
end
