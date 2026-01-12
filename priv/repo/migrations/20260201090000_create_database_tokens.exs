defmodule Trifle.Repo.Migrations.CreateDatabaseTokens do
  use Ecto.Migration

  def change do
    create table(:database_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :token, :string, null: false
      add :read, :boolean, default: true, null: false

      add :database_id,
          references(:databases, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create index(:database_tokens, [:database_id])
  end
end
