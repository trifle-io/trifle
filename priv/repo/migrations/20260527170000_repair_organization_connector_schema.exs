defmodule Trifle.Repo.Migrations.RepairOrganizationConnectorSchema do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS organization_connectors (
      id uuid PRIMARY KEY,
      name varchar(255) NOT NULL,
      token_hash bytea NOT NULL,
      token_last5 varchar(255),
      status varchar(255) NOT NULL DEFAULT 'pending',
      last_heartbeat_at timestamp(0) without time zone,
      last_poll_at timestamp(0) without time zone,
      last_seen_at timestamp(0) without time zone,
      version varchar(255),
      commit varchar(255),
      build_date varchar(255),
      hostname varchar(255),
      capabilities varchar(255)[] NOT NULL DEFAULT ARRAY[]::varchar(255)[],
      metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
      last_error text,
      organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
    )
    """)

    execute(
      "CREATE INDEX IF NOT EXISTS organization_connectors_organization_id_index ON organization_connectors (organization_id)"
    )

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS organization_connectors_token_hash_index ON organization_connectors (token_hash)"
    )

    create_constraint_if_missing(
      :organization_connectors,
      :chk_organization_connectors_status_allowed,
      "status IN ('pending', 'online', 'offline', 'error')"
    )

    execute("""
    CREATE TABLE IF NOT EXISTS connector_jobs (
      id uuid PRIMARY KEY,
      type varchar(255) NOT NULL,
      status varchar(255) NOT NULL DEFAULT 'pending',
      payload jsonb NOT NULL DEFAULT '{}'::jsonb,
      result jsonb,
      error text,
      logs varchar(255)[] NOT NULL DEFAULT ARRAY[]::varchar(255)[],
      completed_at timestamp(0) without time zone,
      organization_connector_id uuid NOT NULL REFERENCES organization_connectors(id) ON DELETE CASCADE,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
    )
    """)

    execute(
      "CREATE INDEX IF NOT EXISTS connector_jobs_organization_connector_id_status_inserted_at_index ON connector_jobs (organization_connector_id, status, inserted_at)"
    )

    create_constraint_if_missing(
      :connector_jobs,
      :chk_connector_jobs_status_allowed,
      "status IN ('pending', 'running', 'ok', 'error')"
    )

    execute("""
    ALTER TABLE databases
    ADD COLUMN IF NOT EXISTS organization_connector_id uuid
    """)

    create_foreign_key_if_missing(
      :databases,
      :databases_organization_connector_id_fkey,
      "FOREIGN KEY (organization_connector_id) REFERENCES organization_connectors(id) ON DELETE SET NULL"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS databases_organization_connector_id_index ON databases (organization_connector_id)"
    )

    create_constraint_if_missing(
      :databases,
      :chk_databases_connector_required,
      "(connection_method = 'connector' AND organization_connector_id IS NOT NULL) OR (connection_method != 'connector' AND organization_connector_id IS NULL)"
    )
  end

  def down do
    :ok
  end

  defp create_constraint_if_missing(table, constraint, check) do
    create_constraint_sql(table, constraint, "CHECK (#{check})")
  end

  defp create_foreign_key_if_missing(table, constraint, definition) do
    create_constraint_sql(table, constraint, definition)
  end

  defp create_constraint_sql(table, constraint, definition) do
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = '#{table}'::regclass
          AND conname = '#{constraint}'
      ) THEN
        ALTER TABLE #{table}
        ADD CONSTRAINT #{constraint} #{definition};
      END IF;
    END
    $$;
    """)
  end
end
