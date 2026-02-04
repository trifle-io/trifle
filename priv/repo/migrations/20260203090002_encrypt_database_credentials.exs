defmodule Trifle.Repo.Migrations.EncryptDatabaseCredentials do
  use Ecto.Migration
  import Ecto.Query

  def up do
    alter table(:databases) do
      add :database_name_encrypted, :binary
      add :username_encrypted, :binary
      add :password_encrypted, :binary
      add :auth_database_encrypted, :binary
    end

    flush()
    # NOTE: We intentionally skip migrating existing credentials.
    # Existing values will be dropped and must be re-entered manually.

    alter table(:databases) do
      remove :database_name
      remove :username
      remove :password
      remove :auth_database
    end

    rename table(:databases), :database_name_encrypted, to: :database_name
    rename table(:databases), :username_encrypted, to: :username
    rename table(:databases), :password_encrypted, to: :password
    rename table(:databases), :auth_database_encrypted, to: :auth_database
  end

  def down do
    raise "irreversible migration"
  end

  defp encrypt_databases do
    repo().all(
      from(d in "databases",
        select: %{
          id: d.id,
          database_name: d.database_name,
          username: d.username,
          password: d.password,
          auth_database: d.auth_database
        }
      )
    )
    |> Enum.each(fn row ->
      updates = [
        database_name_encrypted: encrypt_value(row.database_name),
        username_encrypted: encrypt_value(row.username),
        password_encrypted: encrypt_value(row.password),
        auth_database_encrypted: encrypt_value(row.auth_database)
      ]

      from(d in "databases", where: d.id == ^row.id)
      |> repo().update_all(set: updates)
    end)
  end

  defp encrypt_value(nil), do: nil

  defp encrypt_value(value) when is_binary(value) do
    do_encrypt(value)
  end

  defp encrypt_value(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> do_encrypt()
  end

  defp encrypt_value(value) when is_list(value) do
    value
    |> to_string()
    |> do_encrypt()
  end

  defp encrypt_value(value) when is_integer(value) or is_float(value) do
    value
    |> to_string()
    |> do_encrypt()
  end

  defp encrypt_value(value) do
    value
    |> inspect()
    |> do_encrypt()
  end

  defp do_encrypt(value) do
    case Trifle.Encrypted.Binary.dump(value) do
      {:ok, encrypted} -> encrypted
      :error -> raise "failed to encrypt database credentials"
    end
  end
end
