defmodule Trifle.Repo.Migrations.CleanupLegacyTransponders do
  use Ecto.Migration

  def up do
    execute("""
    DELETE FROM transponders
    WHERE type IS NOT NULL
      AND type <> 'Trifle.Stats.Transponder.Expression'
    """)

    execute("""
    UPDATE transponders
    SET config = jsonb_set(config - 'response_path', '{response}', config->'response_path', true)
    WHERE config IS NOT NULL
      AND config ? 'response_path'
    """)

    alter table(:transponders) do
      remove :type
    end
  end

  def down do
    alter table(:transponders) do
      add :type, :string
    end

    execute("""
    UPDATE transponders
    SET config = jsonb_set(config - 'response', '{response_path}', config->'response', true)
    WHERE config IS NOT NULL
      AND config ? 'response'
    """)

    execute("""
    UPDATE transponders
    SET type = 'Trifle.Stats.Transponder.Expression'
    WHERE type IS NULL
    """)
  end
end
