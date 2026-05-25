defmodule Trifle.Repo.Migrations.CreateOrganizationConnectors do
  use Ecto.Migration

  def change do
    create table(:organization_connectors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :token_hash, :binary, null: false
      add :token_last5, :string
      add :status, :string, null: false, default: "pending"
      add :last_heartbeat_at, :utc_datetime
      add :last_poll_at, :utc_datetime
      add :last_seen_at, :utc_datetime
      add :version, :string
      add :commit, :string
      add :build_date, :string
      add :hostname, :string
      add :capabilities, {:array, :string}, null: false, default: []
      add :metadata, :map, null: false, default: %{}
      add :last_error, :text

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:organization_connectors, [:organization_id])
    create unique_index(:organization_connectors, [:token_hash])

    create constraint(:organization_connectors, :chk_organization_connectors_status_allowed,
             check: "status IN ('pending', 'online', 'offline', 'error')"
           )

    create table(:connector_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :payload, :map, null: false, default: %{}
      add :result, :map
      add :error, :text
      add :logs, {:array, :string}, null: false, default: []
      add :completed_at, :utc_datetime

      add :organization_connector_id,
          references(:organization_connectors, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:connector_jobs, [:organization_connector_id, :status, :inserted_at])

    create constraint(:connector_jobs, :chk_connector_jobs_status_allowed,
             check: "status IN ('pending', 'running', 'ok', 'error')"
           )

    alter table(:databases) do
      add :organization_connector_id,
          references(:organization_connectors, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:databases, [:organization_connector_id])

    create constraint(:databases, :chk_databases_connector_required,
             check:
               "(connection_method = 'connector' AND organization_connector_id IS NOT NULL) OR (connection_method != 'connector' AND organization_connector_id IS NULL)"
           )
  end
end
