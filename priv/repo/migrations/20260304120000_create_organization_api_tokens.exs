defmodule Trifle.Repo.Migrations.CreateOrganizationApiTokens do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS pgcrypto", "")

    create table(:organization_api_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :token_hash, :binary, null: false
      add :permissions, :map, null: false, default: %{}
      add :created_by, :string
      add :created_from, :string
      add :last_used_at, :utc_datetime
      add :last_used_from, :string
      add :expires_at, :utc_datetime

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all)

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:organization_api_tokens, [:organization_id])
    create index(:organization_api_tokens, [:user_id])
    create unique_index(:organization_api_tokens, [:token_hash])
  end
end
