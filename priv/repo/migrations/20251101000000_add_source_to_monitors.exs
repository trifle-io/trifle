defmodule Trifle.Repo.Migrations.AddSourceToMonitors do
  use Ecto.Migration

  def up do
    alter table(:monitors) do
      add :source_type, :string
      add :source_id, :binary_id
    end

    execute("""
    UPDATE monitors AS m
    SET source_type = d.source_type,
        source_id = d.source_id
    FROM dashboards AS d
    WHERE m.dashboard_id = d.id
    """)

    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM monitors
        WHERE source_type IS NULL OR source_id IS NULL
      ) THEN
        RAISE EXCEPTION 'Monitors without a source were found. Populate source_type/source_id before proceeding.';
      END IF;
    END
    $$;
    """)

    alter table(:monitors) do
      modify :source_type, :string, null: false
      modify :source_id, :binary_id, null: false
    end

    create index(:monitors, [:source_type, :source_id])
  end

  def down do
    drop index(:monitors, [:source_type, :source_id])

    alter table(:monitors) do
      remove :source_type
      remove :source_id
    end
  end
end
