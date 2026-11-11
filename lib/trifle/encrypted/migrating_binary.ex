defmodule Trifle.Encrypted.MigratingBinary do
  @moduledoc """
  Encrypted string field (same vault as `Trifle.Encrypted.Binary`) that can still
  read values stored before the column was encrypted.

  Writes are always encrypted. On read, a value the vault cannot decrypt is taken
  to be a legacy plaintext value and returned as is; it becomes encrypted the next
  time the row is written. Use this for a column that was plaintext in production,
  so the change does not need a coordinated data migration.
  """

  use Ecto.Type

  @impl true
  def type, do: :binary

  @impl true
  def cast(nil), do: {:ok, nil}
  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_), do: :error

  @impl true
  def dump(nil), do: {:ok, nil}

  def dump(value) when is_binary(value) do
    case Trifle.Vault.encrypt(value) do
      {:ok, ciphertext} -> {:ok, ciphertext}
      _ -> :error
    end
  end

  def dump(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}

  def load(value) when is_binary(value) do
    {:ok, decrypt_or_legacy(value)}
  end

  @doc "True when the stored bytes are vault ciphertext (not legacy plaintext)."
  def encrypted?(value) when is_binary(value) do
    match?({:ok, plaintext} when is_binary(plaintext), safe_decrypt(value))
  end

  def encrypted?(_), do: false

  defp decrypt_or_legacy(value) do
    case safe_decrypt(value) do
      {:ok, plaintext} when is_binary(plaintext) -> plaintext
      _ -> value
    end
  end

  defp safe_decrypt(value) do
    Trifle.Vault.decrypt(value)
  rescue
    _ -> :error
  end
end
