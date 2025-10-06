defmodule Trifle.Repo.Migrations.AddSourceToDashboards do
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      add :source_type, :string
      add :source_id, :binary_id
    end

    execute("UPDATE dashboards SET source_type = 'database', source_id = database_id")

    alter table(:dashboards) do
      modify :source_type, :string, null: false
      modify :source_id, :binary_id, null: false
    end

    execute("ALTER TABLE dashboards ALTER COLUMN database_id DROP NOT NULL")

    create index(:dashboards, [:source_type, :source_id])
  end
end
