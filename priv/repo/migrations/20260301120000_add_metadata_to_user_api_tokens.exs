defmodule Trifle.Repo.Migrations.AddMetadataToUserApiTokens do
  use Ecto.Migration

  def change do
    alter table(:user_api_tokens) do
      add :created_by, :string
      add :created_from, :string
      add :last_used_from, :string
    end
  end
end
