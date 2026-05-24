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

    create constraint(:databases, :chk_databases_connection_method_allowed,
             check: "connection_method IN ('direct', 'ssh_tunnel', 'agent')"
           )

    create constraint(:databases, :chk_databases_ssh_port_valid,
             check:
               "(connection_method != 'ssh_tunnel' AND ssh_port IS NULL) OR (connection_method = 'ssh_tunnel' AND ssh_port BETWEEN 1 AND 65535)"
           )

    create constraint(:databases, :chk_databases_ssh_host_required,
             check: "connection_method != 'ssh_tunnel' OR ssh_host IS NOT NULL"
           )
  end
end
