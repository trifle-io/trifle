defmodule Trifle.Repo.Migrations.AddGranularitiesToDatabases do
  use Ecto.Migration

  def change do
    alter table(:databases) do
      add :granularities, {:array, :string}, default: []
    end
  end
end
