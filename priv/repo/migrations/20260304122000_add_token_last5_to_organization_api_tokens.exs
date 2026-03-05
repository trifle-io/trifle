defmodule Trifle.Repo.Migrations.AddTokenLast5ToOrganizationApiTokens do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pgcrypto", "")

    execute("""
    ALTER TABLE organization_api_tokens
    ADD COLUMN IF NOT EXISTS token_last5 VARCHAR(5)
    """)

    execute("""
    UPDATE organization_api_tokens AS organization_api_token
    SET token_last5 = RIGHT(project_token.token, 5)
    FROM project_tokens AS project_token
    WHERE organization_api_token.token_last5 IS NULL
      AND project_token.token IS NOT NULL
      AND project_token.token <> ''
      AND organization_api_token.token_hash = digest(project_token.token, 'sha256')
    """)

    execute("""
    UPDATE organization_api_tokens AS organization_api_token
    SET token_last5 = RIGHT(database_token.token, 5)
    FROM database_tokens AS database_token
    WHERE organization_api_token.token_last5 IS NULL
      AND database_token.token IS NOT NULL
      AND database_token.token <> ''
      AND organization_api_token.token_hash = digest(database_token.token, 'sha256')
    """)
  end

  def down do
    alter table(:organization_api_tokens) do
      remove :token_last5
    end
  end
end
