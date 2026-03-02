defmodule Trifle.Repo.Migrations.CreateUserApiTokens do
  use Ecto.Migration

  def change do
    create table(:user_api_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :token_hash, :binary, null: false
      add :last_used_at, :utc_datetime
      add :expires_at, :utc_datetime

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create index(:user_api_tokens, [:user_id])
    create unique_index(:user_api_tokens, [:token_hash])
  end
end
