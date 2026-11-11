defmodule Trifle.Repo.Migrations.HashOrganizationInvitationTokens do
  use Ecto.Migration

  # Invitation tokens are bearer credentials, so only their SHA-256 hash is kept.
  # Existing tokens are hashed in place: links that were already emailed keep
  # working. The plaintext column is emptied and left nullable.
  def up do
    alter table(:organization_invitations) do
      add :token_hash, :binary
    end

    execute("""
    UPDATE organization_invitations
    SET token_hash = sha256(convert_to(token, 'UTF8'))
    WHERE token IS NOT NULL
    """)

    execute("ALTER TABLE organization_invitations ALTER COLUMN token DROP NOT NULL")
    execute("UPDATE organization_invitations SET token = NULL")

    create unique_index(:organization_invitations, [:token_hash])
  end

  def down do
    raise Ecto.MigrationError,
      message:
        "irreversible: invitation tokens are stored hashed and cannot be recovered. " <>
          "Pending invitations would have to be re-sent."
  end
end
