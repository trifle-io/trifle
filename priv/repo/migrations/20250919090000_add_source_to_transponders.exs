defmodule Trifle.Repo.Migrations.AddSourceToTransponders do
  use Ecto.Migration

  def change do
    alter table(:transponders) do
      add :source_type, :string
      add :source_id, :binary_id
    end

    execute("UPDATE transponders SET source_type = 'database', source_id = database_id")

    alter table(:transponders) do
      modify :source_type, :string, null: false
      modify :source_id, :binary_id, null: false
    end

    execute("ALTER TABLE transponders ALTER COLUMN database_id DROP NOT NULL")

    drop_if_exists index(:transponders, [:database_id, :key])
    create index(:transponders, [:source_type, :source_id])
  end
end
