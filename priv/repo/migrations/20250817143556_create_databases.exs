defmodule Trifle.Repo.Migrations.CreateDatabases do
  use Ecto.Migration

  def change do
    create table(:databases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :display_name, :string
      add :driver, :string
      add :host, :string
      add :port, :integer
      add :database_name, :string
      add :username, :string
      add :password, :string
      add :config, :map

      timestamps()
    end
  end
end
