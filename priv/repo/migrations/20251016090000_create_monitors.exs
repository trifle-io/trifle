defmodule Trifle.Repo.Migrations.CreateMonitors do
  use Ecto.Migration

  def change do
    create table(:monitors, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :description, :text
      add :type, :string, null: false
      add :status, :string, null: false, default: "active"
      add :target, :map, null: false, default: %{}
      add :report_settings, :map, null: false, default: %{}
      add :alert_settings, :map, null: false, default: %{}
      add :delivery_channels, {:array, :map}, null: false, default: []
      add :dashboard_id, references(:dashboards, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create index(:monitors, [:organization_id])
    create index(:monitors, [:dashboard_id])
    create index(:monitors, [:status])
    create index(:monitors, [:type])

    create table(:monitor_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :monitor_id, references(:monitors, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :string, null: false
      add :triggered_at, :utc_datetime_usec, null: false
      add :summary, :string
      add :details, :map, null: false, default: %{}

      timestamps(updated_at: false)
    end

    create index(:monitor_executions, [:monitor_id])
    create index(:monitor_executions, [:status])
    create index(:monitor_executions, [:triggered_at])
  end
end
