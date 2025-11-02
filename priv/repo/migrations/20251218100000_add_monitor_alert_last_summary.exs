defmodule Trifle.Repo.Migrations.AddMonitorAlertLastSummary do
  use Ecto.Migration

  def change do
    alter table(:monitor_alerts) do
      add :last_summary, :text
      add :last_evaluated_at, :utc_datetime_usec
    end
  end
end

