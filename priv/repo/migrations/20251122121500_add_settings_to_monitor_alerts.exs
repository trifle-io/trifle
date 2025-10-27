defmodule Trifle.Repo.Migrations.AddSettingsToMonitorAlerts do
  use Ecto.Migration

  def up do
    alter table(:monitor_alerts) do
      add :settings, :map, null: false, default: %{}
    end

    execute(
      "UPDATE monitor_alerts SET analysis_strategy = 'hampel' WHERE analysis_strategy = 'anomaly_detection'"
    )
  end

  def down do
    execute(
      "UPDATE monitor_alerts SET analysis_strategy = 'anomaly_detection' WHERE analysis_strategy = 'hampel'"
    )

    alter table(:monitor_alerts) do
      remove :settings
    end
  end
end
