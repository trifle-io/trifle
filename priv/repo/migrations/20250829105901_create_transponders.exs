defmodule Trifle.Repo.Migrations.CreateTransponders do
  use Ecto.Migration

  def change do
    create table(:transponders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :database_id, references(:databases, on_delete: :delete_all, type: :binary_id), null: false
      add :key, :string, null: false
      add :type, :string, null: false
      add :config, :map, default: %{}
      add :enabled, :boolean, default: true

      timestamps()
    end

    create index(:transponders, [:database_id])
    create unique_index(:transponders, [:database_id, :key])
  end
end
