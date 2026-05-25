defmodule Trifle.Networking.DatabaseEndpointTest do
  use ExUnit.Case, async: true

  alias Trifle.Networking.DatabaseEndpoint
  alias Trifle.Organizations.Database

  test "resolves direct databases explicitly" do
    database = %Database{
      connection_method: "direct",
      driver: "postgres",
      host: "db.internal",
      port: nil
    }

    assert {:ok, %{host: "db.internal", port: 5432, via: :direct}} =
             DatabaseEndpoint.resolve(database)
  end

  test "keeps sqlite direct databases local" do
    database = %Database{connection_method: "direct", driver: "sqlite", host: nil, port: nil}

    assert {:ok, %{host: nil, port: nil, via: :local}} = DatabaseEndpoint.resolve(database)
  end

  test "rejects legacy agent connection method" do
    database = %Database{connection_method: "agent", driver: "postgres"}

    assert {:error, :agent_connection_not_supported} = DatabaseEndpoint.resolve(database)
  end

  test "rejects unsupported connection methods" do
    database = %Database{connection_method: "legacy", driver: "postgres"}

    assert {:error, :unsupported_connection_method} = DatabaseEndpoint.resolve(database)
  end
end
