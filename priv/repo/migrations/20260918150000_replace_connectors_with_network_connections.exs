defmodule Trifle.Repo.Migrations.ReplaceConnectorsWithNetworkConnections do
  use Ecto.Migration

  def up do
    create table(:organization_network_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :provider, :string, null: false, default: "tailscale"
      add :auth_key, :binary
      add :enabled, :boolean, null: false, default: true
      add :generation, :bigint, null: false, default: 1
      add :status, :string, null: false, default: "pending"
      add :hostname, :string
      add :addresses, {:array, :string}, null: false, default: []
      add :last_error, :string
      add :checked_at, :utc_datetime
      timestamps()
    end

    create index(:organization_network_connections, [:organization_id])
    create unique_index(:organization_network_connections, [:organization_id, :name])

    drop_if_exists constraint(:databases, :chk_databases_connector_required)
    drop_if_exists constraint(:databases, :chk_databases_connection_method_allowed)

    execute """
    UPDATE databases SET connection_method = 'unconfigured',
      organization_connector_id = NULL, pool_version = pool_version + 1,
      last_check_status = 'error',
      last_error = 'Private Connector was retired. Configure a Tailscale connection.'
    WHERE connection_method NOT IN ('direct', 'ssh_tunnel', 'tailscale', 'unconfigured')
    """

    create constraint(:databases, :chk_databases_connection_method_allowed,
             check: "connection_method IN ('direct', 'ssh_tunnel', 'tailscale', 'unconfigured')"
           )

    alter table(:databases) do
      remove :organization_connector_id

      add :network_connection_id,
          references(:organization_network_connections, type: :binary_id, on_delete: :restrict)

      add :trace_network_connection_id,
          references(:organization_network_connections, type: :binary_id, on_delete: :restrict)
    end

    create index(:databases, [:network_connection_id])
    create index(:databases, [:trace_network_connection_id])

    create constraint(:databases, :databases_tailscale_connection_required,
             check:
               "(connection_method = 'tailscale' AND network_connection_id IS NOT NULL) OR (connection_method != 'tailscale' AND network_connection_id IS NULL)"
           )

    drop table(:connector_jobs)
    drop table(:organization_connectors)
  end

  def down do
    raise "Connector retirement cannot be rolled back: restore the pre-upgrade database backup."
  end
end
