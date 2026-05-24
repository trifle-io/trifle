defmodule Trifle.Repo.Migrations.AddSecureConnectionFieldsToDatabases do
  use Ecto.Migration

  def change do
    alter table(:databases) do
      add :connection_method, :string, null: false, default: "direct"
      add :ssh_host, :binary
      add :ssh_port, :integer
      add :ssh_username, :binary
      add :ssh_private_key, :binary
      add :ssh_public_key, :text
      add :ssh_passphrase, :binary
      add :ssh_host_key_fingerprint, :binary
    end
  end
end
