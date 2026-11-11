defmodule Trifle.Repo.Migrations.BackfillManagePermissionOnCliTokens do
  use Ecto.Migration

  # Organization API tokens gained a "manage" capability that the bootstrap
  # (organization-management) endpoints now require. Tokens issued by CLI
  # login/signup carry a client-supplied `created_by`; tokens created in the web
  # UI are tagged "web-ui" and tokens minted through the tokens API have no
  # `created_by`. Only the first group keeps management access, so existing CLI
  # sessions continue to work while ingest/read tokens stop being able to mint
  # or widen other tokens.
  def up do
    execute("""
    UPDATE organization_api_tokens
    SET permissions = jsonb_set(COALESCE(permissions, '{}'::jsonb), '{manage}', 'true'::jsonb)
    WHERE created_by IS NOT NULL AND created_by <> 'web-ui'
    """)
  end

  def down do
    execute("""
    UPDATE organization_api_tokens
    SET permissions = permissions - 'manage'
    WHERE permissions ? 'manage'
    """)
  end
end
