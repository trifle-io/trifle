defmodule Trifle.Repo.Migrations.AddAuthDatabaseToDatabases do
  use Ecto.Migration

  def change do
    alter table(:databases) do
      add :auth_database, :string
    end
  end
end
