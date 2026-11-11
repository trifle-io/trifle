defmodule Trifle.Repo.Migrations.EncryptSlackBotAccessToken do
  use Ecto.Migration

  # The Slack bot token is now stored encrypted (Trifle.Encrypted.MigratingBinary).
  # The column becomes bytea; existing plaintext values are kept byte-for-byte and
  # are still readable, and get encrypted the next time the installation is saved
  # or when Trifle.Integrations.encrypt_legacy_slack_tokens/0 is run.
  def up do
    execute("""
    ALTER TABLE slack_installations
    ALTER COLUMN bot_access_token TYPE bytea
    USING convert_to(bot_access_token, 'UTF8')
    """)
  end

  def down do
    raise Ecto.MigrationError,
      message:
        "irreversible: encrypted Slack tokens cannot be turned back into a text column. " <>
          "Restore from backup or re-install the Slack integration."
  end
end
