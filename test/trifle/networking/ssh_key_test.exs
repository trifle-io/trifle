defmodule Trifle.Networking.SSHKeyTest do
  use ExUnit.Case, async: true

  alias Trifle.Networking.SSHKey

  test "generates OpenSSH-compatible key material" do
    key = SSHKey.generate_key_pair("trifle-test")

    assert key.private_key =~ "BEGIN RSA PRIVATE KEY"
    assert key.public_key =~ "ssh-rsa "
    assert key.public_key =~ " trifle-test"
  end
end
