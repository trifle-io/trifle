defmodule Trifle.Repo.Migrations.AddStatusToMonitorAlerts do
  use Ecto.Migration

  def change do
    alter table(:monitor_alerts) do
      add :status, :string, null: false, default: "passed"
    end
  end
end
