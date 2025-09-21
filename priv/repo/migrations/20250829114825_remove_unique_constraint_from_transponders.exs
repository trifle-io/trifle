defmodule Trifle.Repo.Migrations.RemoveUniqueConstraintFromTransponders do
  use Ecto.Migration

  def change do
    drop_if_exists unique_index(:transponders, [:database_id, :key])
    create index(:transponders, [:database_id, :key])
  end
end
