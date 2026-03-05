defmodule Trifle.Repo.Migrations.MigrateLegacyTokensToOrganizationApiTokens do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pgcrypto", "")

    execute("""
    INSERT INTO organization_api_tokens (
      id,
      organization_id,
      user_id,
      name,
      token_hash,
      permissions,
      created_by,
      created_from,
      inserted_at,
      updated_at
    )
    SELECT
      gen_random_uuid(),
      project.organization_id,
      project.user_id,
      COALESCE(project_token.name, 'Migrated project token'),
      digest(project_token.token, 'sha256'),
      jsonb_build_object(
        'wildcard', jsonb_build_object('read', false, 'write', false),
        'sources', jsonb_build_object(
          CONCAT('project:', project.id::text),
          jsonb_build_object('read', project_token.read, 'write', project_token.write)
        )
      ),
      'legacy-migration',
      'legacy-migration',
      project_token.inserted_at,
      project_token.updated_at
    FROM project_tokens AS project_token
    JOIN projects AS project ON project.id = project_token.project_id
    WHERE project_token.token IS NOT NULL
      AND project_token.token <> ''
    ON CONFLICT (token_hash) DO NOTHING
    """)

    execute("""
    INSERT INTO organization_api_tokens (
      id,
      organization_id,
      user_id,
      name,
      token_hash,
      permissions,
      created_by,
      created_from,
      inserted_at,
      updated_at
    )
    SELECT
      gen_random_uuid(),
      database.organization_id,
      membership.user_id,
      COALESCE(database_token.name, 'Migrated database token'),
      digest(database_token.token, 'sha256'),
      jsonb_build_object(
        'wildcard', jsonb_build_object('read', false, 'write', false),
        'sources', jsonb_build_object(
          CONCAT('database:', database.id::text),
          jsonb_build_object('read', true, 'write', false)
        )
      ),
      'legacy-migration',
      'legacy-migration',
      database_token.inserted_at,
      database_token.updated_at
    FROM database_tokens AS database_token
    JOIN databases AS database ON database.id = database_token.database_id
    JOIN LATERAL (
      SELECT organization_membership.user_id
      FROM organization_memberships AS organization_membership
      WHERE organization_membership.organization_id = database.organization_id
      ORDER BY
        CASE organization_membership.role
          WHEN 'owner' THEN 0
          WHEN 'admin' THEN 1
          ELSE 2
        END,
        organization_membership.inserted_at
      LIMIT 1
    ) AS membership ON TRUE
    WHERE database_token.token IS NOT NULL
      AND database_token.token <> ''
    ON CONFLICT (token_hash) DO NOTHING
    """)

    execute("""
    INSERT INTO organization_api_tokens (
      id,
      organization_id,
      user_id,
      name,
      token_hash,
      permissions,
      created_by,
      created_from,
      last_used_at,
      last_used_from,
      expires_at,
      inserted_at,
      updated_at
    )
    SELECT
      gen_random_uuid(),
      membership.organization_id,
      user_api_token.user_id,
      COALESCE(user_api_token.name, 'Migrated user token'),
      user_api_token.token_hash,
      jsonb_build_object(
        'wildcard', jsonb_build_object('read', true, 'write', true),
        'sources', jsonb_build_object()
      ),
      'legacy-migration',
      'legacy-migration',
      user_api_token.last_used_at,
      user_api_token.last_used_from,
      user_api_token.expires_at,
      user_api_token.inserted_at,
      user_api_token.updated_at
    FROM user_api_tokens AS user_api_token
    JOIN LATERAL (
      SELECT organization_membership.organization_id
      FROM organization_memberships AS organization_membership
      WHERE organization_membership.user_id = user_api_token.user_id
      ORDER BY organization_membership.inserted_at
      LIMIT 1
    ) AS membership ON TRUE
    WHERE user_api_token.token_hash IS NOT NULL
      AND octet_length(user_api_token.token_hash) > 0
    ON CONFLICT (token_hash) DO NOTHING
    """)
  end

  def down do
    execute("""
    DELETE FROM organization_api_tokens
    WHERE created_from = 'legacy-migration'
       OR created_by = 'legacy-migration'
    """)
  end
end
