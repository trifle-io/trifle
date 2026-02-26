defmodule Trifle.Repo.Migrations.AddPoolVersionToDatabases do
  use Ecto.Migration

  def change do
    alter table(:databases) do
      add :pool_version, :integer, null: false, default: 1
    end
  end
end
