defmodule Trifle.Networking.SSHKeyTest do
  use ExUnit.Case, async: true

  alias Trifle.Networking.SSHKey

  test "generates OpenSSH-compatible key material" do
    key = SSHKey.generate_key_pair("trifle-test")

    [private_entry] = :public_key.pem_decode(key.private_key)

    assert {:RSAPrivateKey, _, _, _, _, _, _, _, _, _, _} =
             :public_key.pem_entry_decode(private_entry)

    public_entries = :ssh_file.decode(key.public_key, :public_key)
    assert [{{:RSAPublicKey, _, _}, _attributes} | _] = public_entries
  end
end
