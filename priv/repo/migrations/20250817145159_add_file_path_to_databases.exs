defmodule Trifle.Repo.Migrations.AddFilePathToDatabases do
  use Ecto.Migration

  def change do
    alter table(:databases) do
      add :file_path, :string
    end
  end
end
