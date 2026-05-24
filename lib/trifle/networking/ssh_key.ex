defmodule Trifle.Networking.SSHKey do
  @moduledoc """
  Helpers for generating SSH key material used by Trifle-managed database tunnels.
  """

  import Bitwise

  @rsa_bits 3072
  @rsa_public_exponent 65_537

  def generate_key_pair(comment \\ "trifle-db-tunnel") do
    private_key = :public_key.generate_key({:rsa, @rsa_bits, @rsa_public_exponent})
    public_key = rsa_public_key(private_key)

    %{
      private_key: private_key_pem(private_key),
      public_key: public_key_line(public_key, comment)
    }
  end

  def private_key_pem(private_key) do
    private_key
    |> then(&:public_key.pem_entry_encode(:RSAPrivateKey, &1))
    |> List.wrap()
    |> :public_key.pem_encode()
  end

  def public_key_line(
        {:RSAPublicKey, _modulus, _exponent} = public_key,
        comment \\ "trifle-db-tunnel"
      ) do
    "ssh-rsa #{Base.encode64(public_key_blob(public_key))} #{comment}"
  end

  defp rsa_public_key(
         {:RSAPrivateKey, _version, modulus, public_exponent, _private_exponent, _prime1, _prime2,
          _exponent1, _exponent2, _coefficient, _other}
       ) do
    {:RSAPublicKey, modulus, public_exponent}
  end

  defp public_key_blob({:RSAPublicKey, modulus, public_exponent}) do
    ssh_string("ssh-rsa") <> ssh_mpint(public_exponent) <> ssh_mpint(modulus)
  end

  defp ssh_string(value) when is_binary(value) do
    <<byte_size(value)::32, value::binary>>
  end

  defp ssh_mpint(integer) when is_integer(integer) and integer >= 0 do
    bytes = :binary.encode_unsigned(integer)

    bytes =
      case bytes do
        <<first, _rest::binary>> when (first &&& 0x80) == 0x80 -> <<0, bytes::binary>>
        _ -> bytes
      end

    ssh_string(bytes)
  end
end
