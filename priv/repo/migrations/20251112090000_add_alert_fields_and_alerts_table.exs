defmodule Trifle.Repo.Migrations.AddAlertFieldsAndAlertsTable do
  use Ecto.Migration

  def change do
    alter table(:monitors) do
      add :alert_metric_key, :string
      add :alert_metric_path, :string
      add :alert_timeframe, :string
      add :alert_granularity, :string
      remove :alert_settings
    end

    create table(:monitor_alerts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :analysis_strategy, :string, null: false, default: "threshold"

      add :monitor_id, references(:monitors, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create index(:monitor_alerts, [:monitor_id])
  end
end
