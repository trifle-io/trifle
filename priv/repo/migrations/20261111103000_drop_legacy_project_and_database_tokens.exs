defmodule Trifle.Repo.Migrations.DropLegacyProjectAndDatabaseTokens do
  use Ecto.Migration

  # Per-project and per-database tokens were replaced by organization API tokens
  # (migrated in 20260304121000) and nothing reads these tables any more. They
  # still held the old tokens in plaintext, so they are dropped rather than kept.
  #
  # `down` recreates the empty tables so the migration can be rolled back; the
  # tokens themselves are gone.
  def up do
    drop_if_exists table(:project_tokens)
    drop_if_exists table(:database_tokens)
  end

  def down do
    create_if_not_exists table(:project_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :token, :string
      add :read, :boolean, default: false, null: false
      add :write, :boolean, default: false, null: false
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all)

      timestamps()
    end

    create_if_not_exists index(:project_tokens, [:project_id])

    create_if_not_exists table(:database_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :token, :string, null: false
      add :read, :boolean, default: true, null: false

      add :database_id,
          references(:databases, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create_if_not_exists index(:database_tokens, [:database_id])
  end
end
