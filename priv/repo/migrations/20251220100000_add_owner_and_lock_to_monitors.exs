defmodule Trifle.Repo.Migrations.AddOwnerAndLockToMonitors do
  use Ecto.Migration

  def up do
    alter table(:monitors) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :locked, :boolean, default: false, null: false
    end

    execute("""
    UPDATE monitors
    SET user_id = created_by_id
    WHERE user_id IS NULL
      AND created_by_id IS NOT NULL
    """)

    execute("""
    UPDATE monitors AS m
    SET user_id = (
      SELECT om.user_id
      FROM organization_memberships AS om
      WHERE om.organization_id = m.organization_id
      ORDER BY
        CASE om.role
          WHEN 'owner' THEN 0
          WHEN 'admin' THEN 1
          ELSE 2
        END,
        om.inserted_at
      LIMIT 1
    )
    WHERE m.user_id IS NULL
    """)

    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM monitors WHERE user_id IS NULL) THEN
        RAISE EXCEPTION 'Unable to assign owners to all monitors. Please ensure every monitor has an owner before rerunning.';
      END IF;
    END
    $$;
    """)

    execute("ALTER TABLE monitors ALTER COLUMN user_id SET NOT NULL")

    create index(:monitors, [:user_id])
    create index(:monitors, [:locked])
  end

  def down do
    drop index(:monitors, [:locked])
    drop index(:monitors, [:user_id])

    alter table(:monitors) do
      remove :locked
      remove :user_id
    end
  end
end
