defmodule Trifle.Networking.MongoConnectionTest do
  # Flips the global host-guard setting.
  use ExUnit.Case, async: false

  alias Trifle.Networking.MongoConnection
  alias Trifle.Organizations.Database

  setup do
    previous = Application.get_env(:trifle, :allow_private_network_targets)
    on_exit(fn -> Application.put_env(:trifle, :allow_private_network_targets, previous) end)
    :ok
  end

  defp database(attrs \\ %{}) do
    struct(
      %Database{
        driver: "mongo",
        connection_method: "direct",
        host: "db.example.com",
        port: 27017,
        database_name: "analytics",
        username: "app",
        password: "secret",
        config: %{}
      },
      attrs
    )
  end

  @endpoint %{host: "db.example.com", port: 27017, via: :direct}

  # The options after the driver has processed them, as it does in start_link.
  defp driver_view(options), do: Mongo.UrlParser.parse_url(options)

  describe "connection target and credentials" do
    test "no URL is built; the host and port are passed as given" do
      assert {:ok, options} = MongoConnection.options(database(), @endpoint)

      refute Keyword.has_key?(options, :url)
      refute Keyword.has_key?(options, :seeds)
      assert options[:hostname] == "db.example.com"
      assert options[:port] == 27017
    end

    test "hostile values in any field cannot change where the driver connects" do
      hostile = [
        "pw@127.0.0.1:27017/db#",
        "pw@169.254.169.254:27017/",
        "x,127.0.0.1:27017",
        "a/b?authSource=admin&x=@10.0.0.1",
        "p@ss:w/or#d?"
      ]

      for value <- hostile, field <- [:password, :username, :database_name, :auth_database] do
        assert {:ok, options} = MongoConnection.options(database(%{field => value}), @endpoint)
        seen = driver_view(options)

        assert seen[:hostname] == "db.example.com", "#{field}=#{inspect(value)} moved the host"
        assert seen[:port] == 27017
        refute Keyword.has_key?(seen, :seeds)
      end
    end

    test "names and credentials reach the driver exactly as entered" do
      for name <- ["analytics", "analytics+events", "my-db_2", "per%cent", "with space"] do
        assert {:ok, options} =
                 MongoConnection.options(
                   database(%{database_name: name, auth_database: name}),
                   @endpoint
                 )

        seen = driver_view(options)
        assert seen[:database] == name
        assert seen[:auth_source] == name
      end

      password = "pw@127.0.0.1:27017/db#+%20"
      username = "app+user@corp"

      assert {:ok, options} =
               MongoConnection.options(
                 database(%{username: username, password: password}),
                 @endpoint
               )

      seen = driver_view(options)
      assert seen[:username] == username
      # The driver moves the password into its password safe and masks the option.
      assert seen[:password] == "*****"
      assert Mongo.PasswordSafe.get_password(seen[:pw_safe]) == password
    end

    test "defaults: admin database, no credentials unless both are present" do
      assert {:ok, options} =
               MongoConnection.options(
                 database(%{database_name: nil, password: nil, auth_database: ""}),
                 @endpoint
               )

      assert options[:database] == "admin"
      refute Keyword.has_key?(options, :username)
      refute Keyword.has_key?(options, :password)
      refute Keyword.has_key?(options, :auth_source)
    end

    test "caller-supplied url or seeds are discarded" do
      assert {:ok, options} =
               MongoConnection.options(database(), @endpoint,
                 url: "mongodb://127.0.0.1/x",
                 seeds: ["127.0.0.1:27017"],
                 pool_size: 2
               )

      refute Keyword.has_key?(options, :url)
      refute Keyword.has_key?(options, :seeds)
      assert options[:pool_size] == 2
    end

    test "a host that is not a single plain host is rejected" do
      for host <- [
            "db.example.com,127.0.0.1",
            "db.example.com/x",
            "user@127.0.0.1",
            "db.example.com?x",
            "db example.com",
            ""
          ] do
        assert MongoConnection.options(database(), %{host: host, port: 27017}) ==
                 {:error, :invalid_host},
               "accepted host #{inspect(host)}"
      end
    end
  end

  describe "options/3" do
    test "tenant connections do not discover other servers when hosts are restricted" do
      Application.put_env(:trifle, :allow_private_network_targets, false)

      for {method, endpoint} <- [
            {"direct", @endpoint},
            {"ssh_tunnel", %{host: "127.0.0.1", port: 40_123, via: :ssh_tunnel}}
          ] do
        assert {:ok, options} =
                 MongoConnection.options(database(%{connection_method: method}), endpoint,
                   pool_size: 1
                 )

        assert options[:type] == :single, "#{method} still discovers"
        assert options[:pool_size] == 1
      end
    end

    test "platform-managed databases keep discovery" do
      Application.put_env(:trifle, :allow_private_network_targets, false)

      assert {:ok, options} =
               MongoConnection.options(database(%{managed_key: "internal"}), @endpoint)

      refute options[:type] == :single
    end

    test "discovery is untouched where private targets are allowed" do
      Application.put_env(:trifle, :allow_private_network_targets, true)

      assert {:ok, options} = MongoConnection.options(database(), @endpoint)
      refute options[:type] == :single
    end
  end
end
