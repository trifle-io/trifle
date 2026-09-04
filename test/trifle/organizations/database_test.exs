defmodule Trifle.Organizations.DatabaseTest do
  use Trifle.DataCase, async: true

  import Ecto.Changeset
  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations
  alias Trifle.Organizations.Database

  describe "driver configuration" do
    test "includes mysql in supported drivers" do
      assert "mysql" in Database.drivers()
    end

    test "provides week options" do
      assert Database.week_options() == [
               {"Monday", 1},
               {"Tuesday", 2},
               {"Wednesday", 3},
               {"Thursday", 4},
               {"Friday", 5},
               {"Saturday", 6},
               {"Sunday", 7}
             ]
    end

    test "provides mysql defaults" do
      assert Database.default_port("mysql") == 3306

      assert Database.default_config_options("mysql") == %{
               "pool_size" => 10,
               "pool_timeout" => 15_000,
               "timeout" => 15_000,
               "ssl" => false,
               "table_name" => "trifle_stats",
               "joined_identifiers" => "full"
             }
    end

    test "includes secure connection methods" do
      assert Database.connection_methods() == ["direct", "ssh_tunnel", "connector"]
    end
  end

  describe "optional Trifle Traces configuration" do
    test "keeps an ordinary database Stats-only" do
      changeset = Database.changeset(%Database{}, postgres_attrs())

      assert changeset.valid?
      refute Database.traces_configured?(apply_changes(changeset))
      assert Database.capabilities(apply_changes(changeset)) == [:stats]
    end

    test "accepts and normalizes PostgreSQL with S3 payload storage" do
      changeset =
        Database.changeset(
          %Database{},
          postgres_attrs(%{
            trace_config: %{
              index_name: "custom_traces",
              data_driver: "s3",
              data_endpoint: "http://minio:9000",
              data_buckets: "traces-a, traces-b",
              data_region: "us-east-1",
              data_prefix: "jobs",
              retention_days: "14",
              gzip: "true"
            },
            trace_access_key_id: "minio",
            trace_secret_access_key: "miniosecret"
          })
        )

      assert changeset.valid?
      database = apply_changes(changeset)
      assert Database.traces_configured?(database)
      assert Database.capabilities(database) == [:stats, :traces]
      assert database.trace_config["data_buckets"] == ["traces-a", "traces-b"]
      assert database.trace_config["retention_days"] == 14
      assert database.trace_config["gzip"] == true
    end

    test "accepts MongoDB with File payload storage and clears S3 credentials" do
      changeset =
        Database.changeset(%Database{}, %{
          display_name: "Mongo traces",
          driver: "mongo",
          host: "mongo",
          port: 27017,
          database_name: "trifle_test",
          organization_id: Ecto.UUID.generate(),
          trace_access_key_id: "unused",
          trace_secret_access_key: "unused",
          trace_config: file_trace_config()
        })

      assert changeset.valid?
      database = apply_changes(changeset)
      assert database.trace_access_key_id == nil
      assert database.trace_secret_access_key == nil
      assert database.trace_config["data_driver"] == "file"
    end

    test "rejects partial and unsupported trace configurations" do
      partial =
        Database.changeset(
          %Database{},
          postgres_attrs(%{trace_config: %{"index_name" => "trifle_traces"}})
        )

      refute partial.valid?

      assert Enum.any?(partial.errors, fn
               {:trace_config, {"retention days must be between 1 and 3650", _}} -> true
               _ -> false
             end)

      unsupported =
        Database.changeset(
          %Database{},
          redis_attrs(%{database_name: "0", trace_config: file_trace_config()})
        )

      refute unsupported.valid?

      assert {"is only supported for direct or SSH PostgreSQL and MongoDB databases", _} =
               unsupported.errors[:trace_config]
    end

    test "keeps the private connector Stats-only" do
      changeset =
        Database.changeset(
          %Database{},
          postgres_attrs(%{
            connection_method: "connector",
            organization_connector_id: Ecto.UUID.generate(),
            trace_config: file_trace_config()
          })
        )

      refute changeset.valid?

      assert {"is only supported for direct or SSH PostgreSQL and MongoDB databases", _} =
               changeset.errors[:trace_config]
    end

    test "requires S3 credentials to be provided as a pair" do
      changeset =
        Database.changeset(
          %Database{},
          postgres_attrs(%{
            trace_config: s3_trace_config(),
            trace_access_key_id: "access-only"
          })
        )

      refute changeset.valid?

      assert {"access key ID and secret access key must be provided together", _} =
               changeset.errors[:trace_access_key_id]
    end

    test "requires a safe absolute File path" do
      changeset =
        Database.changeset(
          %Database{},
          postgres_attrs(%{
            trace_config: Map.put(file_trace_config(), "data_path", "relative/traces")
          })
        )

      refute changeset.valid?
      assert {"File path must be an absolute non-root path", _} = changeset.errors[:trace_config]
    end

    test "removes configuration and encrypted credentials without deleting the database" do
      organization = organization_fixture()

      assert {:ok, database} =
               Organizations.create_database_for_org(
                 organization,
                 postgres_attrs(%{
                   trace_config: s3_trace_config(),
                   trace_access_key_id: "access",
                   trace_secret_access_key: "secret"
                 })
                 |> Map.drop([:organization_id])
               )

      assert {:ok, updated} = Organizations.remove_database_traces(database)
      refute Database.traces_configured?(updated)
      assert updated.trace_access_key_id == nil
      assert updated.trace_secret_access_key == nil
      assert Organizations.get_database!(database.id).id == database.id
    end

    test "encrypts S3 credentials at rest and decrypts them on load" do
      organization = organization_fixture()

      assert {:ok, database} =
               Organizations.create_database_for_org(
                 organization,
                 postgres_attrs(%{
                   trace_config: s3_trace_config(),
                   trace_access_key_id: "trace-access",
                   trace_secret_access_key: "trace-secret"
                 })
                 |> Map.drop([:organization_id])
               )

      loaded = Organizations.get_database!(database.id)
      assert loaded.trace_access_key_id == "trace-access"
      assert loaded.trace_secret_access_key == "trace-secret"

      %{rows: [[encrypted_access, encrypted_secret]]} =
        Trifle.Repo.query!(
          "SELECT trace_access_key_id, trace_secret_access_key FROM databases WHERE id = $1",
          [Ecto.UUID.dump!(database.id)]
        )

      refute encrypted_access == "trace-access"
      refute encrypted_secret == "trace-secret"
    end

    test "blank credential fields preserve existing encrypted S3 credentials" do
      organization = organization_fixture()

      assert {:ok, database} =
               Organizations.create_database_for_org(
                 organization,
                 postgres_attrs(%{
                   trace_config: s3_trace_config(),
                   trace_access_key_id: "trace-access",
                   trace_secret_access_key: "trace-secret"
                 })
                 |> Map.drop([:organization_id])
               )

      assert {:ok, updated} =
               Organizations.update_database(database, %{
                 display_name: "Updated",
                 trace_access_key_id: "",
                 trace_secret_access_key: ""
               })

      assert updated.trace_access_key_id == "trace-access"
      assert updated.trace_secret_access_key == "trace-secret"
    end
  end

  describe "changeset/2 for mysql" do
    test "requires host, port, database_name, username, and password" do
      changeset =
        Database.changeset(%Database{}, %{
          display_name: "MySQL",
          driver: "mysql",
          organization_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:host]
      assert {"can't be blank", _} = changeset.errors[:port]
      assert {"can't be blank", _} = changeset.errors[:database_name]
      assert {"can't be blank", _} = changeset.errors[:username]
      assert {"can't be blank", _} = changeset.errors[:password]
    end

    test "merges defaults and normalizes mysql config values" do
      changeset =
        Database.changeset(
          %Database{},
          mysql_attrs(%{
            config: %{
              "table_name" => "custom_stats",
              "joined_identifiers" => "partial",
              "pool_size" => 12,
              "pool_timeout" => 25_000
            },
            granularities: "1m, 1h, 1d"
          })
        )

      assert changeset.valid?
      config = get_change(changeset, :config)

      assert config["table_name"] == "custom_stats"
      assert config["joined_identifiers"] == "partial"
      assert config["pool_size"] == 12
      assert config["pool_timeout"] == 25_000
      assert config["timeout"] == 15_000
      assert get_change(changeset, :granularities) == ["1m", "1h", "1d"]
    end

    test "normalizes joined_identifiers false to nil for mysql" do
      changeset =
        Database.changeset(
          %Database{},
          mysql_attrs(%{config: %{"joined_identifiers" => "false"}})
        )

      assert changeset.valid?
      assert get_change(changeset, :config)["joined_identifiers"] == nil
    end

    test "defaults beginning_of_week to monday" do
      changeset =
        Database.changeset(
          %Database{},
          mysql_attrs()
        )

      assert changeset.valid?
      assert get_field(changeset, :beginning_of_week) == 1
    end

    test "requires ssh tunnel fields when selected" do
      changeset =
        Database.changeset(
          %Database{},
          mysql_attrs(%{connection_method: "ssh_tunnel"})
        )

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:ssh_host]
      assert {"can't be blank", _} = changeset.errors[:ssh_username]
      assert {"can't be blank", _} = changeset.errors[:ssh_private_key]
      assert {"can't be blank", _} = changeset.errors[:ssh_public_key]
      assert {"can't be blank", _} = changeset.errors[:ssh_host_key_fingerprint]
      assert get_field(changeset, :ssh_port) == 22
    end

    test "accepts complete ssh tunnel configuration" do
      changeset =
        Database.changeset(
          %Database{},
          mysql_attrs(ssh_tunnel_attrs())
        )

      assert changeset.valid?
      assert get_field(changeset, :connection_method) == "ssh_tunnel"
      assert get_field(changeset, :ssh_port) == 22
    end

    test "requires an organization connector when connector connection method is selected" do
      changeset =
        Database.changeset(
          %Database{},
          mysql_attrs(%{connection_method: "connector"})
        )

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:organization_connector_id]
    end

    test "clears ssh fields when connection method is not ssh tunnel" do
      database = struct(Database, ssh_tunnel_attrs())

      changeset =
        Database.changeset(
          database,
          mysql_attrs(%{connection_method: "direct"})
        )

      assert get_change(changeset, :ssh_host) == nil
      assert get_change(changeset, :ssh_port) == nil
      assert get_change(changeset, :ssh_private_key) == nil
      assert get_change(changeset, :ssh_passphrase) == nil
    end

    test "requires redis database name to be a non-negative integer" do
      valid_changeset =
        Database.changeset(
          %Database{},
          redis_attrs(%{database_name: "0"})
        )

      assert valid_changeset.valid?

      invalid_changeset =
        Database.changeset(
          %Database{},
          redis_attrs(%{database_name: "-1"})
        )

      refute invalid_changeset.valid?
      assert {"must be a non-negative integer", _} = invalid_changeset.errors[:database_name]
    end

    test "validates existing redis database name when it is not changed" do
      database = struct(Database, redis_attrs(%{database_name: "abc"}))

      changeset = Database.changeset(database, %{display_name: "Renamed Redis"})

      refute changeset.valid?
      assert {"must be a non-negative integer", _} = changeset.errors[:database_name]
    end

    test "requires sqlite databases to use direct connection method" do
      changeset =
        Database.changeset(%Database{}, %{
          display_name: "SQLite",
          driver: "sqlite",
          file_path: "/tmp/trifle.sqlite",
          connection_method: "ssh_tunnel",
          organization_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert {"must be direct for SQLite databases", _} = changeset.errors[:connection_method]
    end
  end

  describe "create_database_for_org/2" do
    test "creates mysql database source" do
      organization = organization_fixture()

      assert {:ok, database} =
               Organizations.create_database_for_org(
                 organization,
                 mysql_attrs() |> Map.delete(:organization_id)
               )

      assert database.driver == "mysql"
      assert database.display_name == "Primary MySQL"
      assert database.host == "127.0.0.1"
      assert database.port == 3306
      assert database.database_name == "trifle_stats"
      assert database.username == "trifle"
      assert database.last_check_status == "pending"
      assert database.pool_version == 1
      assert database.beginning_of_week == 1
      assert database.config["table_name"] == "trifle_stats"
      assert database.config["joined_identifiers"] == "full"
    end

    test "creates connector-connected database with a connector from the same organization" do
      organization = organization_fixture()

      {connector, _token} =
        organization_connector_with_token_fixture(%{organization: organization})

      assert {:ok, database} =
               Organizations.create_database_for_org(
                 organization,
                 mysql_attrs(%{
                   connection_method: "connector",
                   organization_connector_id: connector.id
                 })
                 |> Map.delete(:organization_id)
               )

      assert database.connection_method == "connector"
      assert database.organization_connector_id == connector.id
    end

    test "rejects connector-connected database with a connector from another organization" do
      organization = organization_fixture()
      other_organization = organization_fixture(%{name: "other organization"})

      {connector, _token} =
        organization_connector_with_token_fixture(%{organization: other_organization})

      assert {:error, changeset} =
               Organizations.create_database_for_org(
                 organization,
                 mysql_attrs(%{
                   connection_method: "connector",
                   organization_connector_id: connector.id
                 })
                 |> Map.delete(:organization_id)
               )

      assert {"is not available", _} = changeset.errors[:organization_connector_id]
    end
  end

  describe "beginning_of_week_for/1" do
    test "maps stored integer to expected weekday atom" do
      database = %Database{beginning_of_week: 1}
      assert Database.beginning_of_week_for(database) == :monday
    end
  end

  describe "update_database/2 pool versioning" do
    test "increments pool_version when connection config changes" do
      database = database_fixture()
      assert database.pool_version == 1

      new_file_path = Path.join(System.tmp_dir!(), "trifle-db-#{Ecto.UUID.generate()}.sqlite")

      assert {:ok, updated_database} =
               Organizations.update_database(database, %{file_path: new_file_path})

      assert updated_database.pool_version == 2
      assert updated_database.file_path == new_file_path
    end

    test "does not increment pool_version for non-connection fields" do
      database = database_fixture()

      assert {:ok, updated_database} =
               Organizations.update_database(database, %{display_name: "Renamed database"})

      assert updated_database.pool_version == database.pool_version
      assert updated_database.display_name == "Renamed database"
    end

    test "increments pool_version when ssh tunnel config changes" do
      organization = organization_fixture()

      assert {:ok, database} =
               Organizations.create_database_for_org(
                 organization,
                 mysql_attrs(ssh_tunnel_attrs()) |> Map.delete(:organization_id)
               )

      assert {:ok, updated_database} =
               Organizations.update_database(database, %{ssh_host: "new-bastion.example.com"})

      assert updated_database.pool_version == database.pool_version + 1
      assert updated_database.ssh_host == "new-bastion.example.com"
    end

    test "preserves sqlite storage metadata when updating sqlite config without re-upload" do
      organization = organization_fixture()

      storage_metadata = %{
        "backend" => "s3",
        "object_key" => "sqlite-files/organization_#{organization.id}/sqlite/uploaded.db",
        "checksum_sha256" => String.duplicate("a", 64),
        "size_bytes" => 1_036_288,
        "bucket" => "trifle-sqlite-files",
        "region" => "us-east-1",
        "endpoint" => "http://minio:9000"
      }

      assert {:ok, database} =
               Organizations.create_database_for_org(organization, %{
                 display_name: "SQLite Uploaded",
                 driver: "sqlite",
                 file_path:
                   "/tmp/trifle_sqlite_cache/sqlite-files/organization_#{organization.id}/sqlite/uploaded.db",
                 config: %{
                   "table_name" => "trifle_stats",
                   "joined_identifiers" => "full",
                   "pool_size" => 5,
                   "timeout" => 5000,
                   "sqlite_storage" => storage_metadata
                 }
               })

      assert {:ok, updated_database} =
               Organizations.update_database(database, %{
                 config: %{
                   "table_name" => "updated_table",
                   "joined_identifiers" => "partial",
                   "pool_size" => 10,
                   "timeout" => 15_000
                 }
               })

      assert updated_database.pool_version == database.pool_version + 1
      assert updated_database.config["table_name"] == "updated_table"
      assert updated_database.config["joined_identifiers"] == "partial"
      assert updated_database.config["sqlite_storage"] == storage_metadata
    end

    test "removes previous managed sqlite file when file_path changes" do
      organization = organization_fixture()

      managed_dir =
        Trifle.Config.sqlite_upload_root()
        |> Path.join("organization_#{organization.id}")
        |> Path.join("sqlite")

      :ok = File.mkdir_p(managed_dir)

      old_file_path = Path.join(managed_dir, "#{Ecto.UUID.generate()}.sqlite")
      :ok = File.write(old_file_path, "old")

      assert {:ok, database} =
               Organizations.create_database_for_org(organization, %{
                 display_name: "Managed SQLite",
                 driver: "sqlite",
                 file_path: old_file_path
               })

      new_file_path = Path.join(System.tmp_dir!(), "trifle-db-#{Ecto.UUID.generate()}.sqlite")
      on_exit(fn -> File.rm(new_file_path) end)

      assert {:ok, _updated_database} =
               Organizations.update_database(database, %{file_path: new_file_path})

      refute File.exists?(old_file_path)
    end

    test "keeps external sqlite files when file_path changes" do
      organization = organization_fixture()

      old_file_path = Path.join(System.tmp_dir!(), "external-db-#{Ecto.UUID.generate()}.sqlite")
      :ok = File.write(old_file_path, "old")
      on_exit(fn -> File.rm(old_file_path) end)

      assert {:ok, database} =
               Organizations.create_database_for_org(organization, %{
                 display_name: "External SQLite",
                 driver: "sqlite",
                 file_path: old_file_path
               })

      new_file_path = Path.join(System.tmp_dir!(), "trifle-db-#{Ecto.UUID.generate()}.sqlite")
      on_exit(fn -> File.rm(new_file_path) end)

      assert {:ok, _updated_database} =
               Organizations.update_database(database, %{file_path: new_file_path})

      assert File.exists?(old_file_path)
    end
  end

  defp mysql_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        display_name: "Primary MySQL",
        driver: "mysql",
        host: "127.0.0.1",
        port: 3306,
        database_name: "trifle_stats",
        username: "trifle",
        password: "secret",
        organization_id: Ecto.UUID.generate()
      },
      overrides
    )
  end

  defp postgres_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        display_name: "Primary Postgres",
        driver: "postgres",
        host: "postgres",
        port: 5432,
        database_name: "trifle_test",
        username: "postgres",
        password: "password",
        organization_id: Ecto.UUID.generate()
      },
      overrides
    )
  end

  defp s3_trace_config do
    %{
      "index_name" => "trifle_traces",
      "data_driver" => "s3",
      "data_endpoint" => "http://minio:9000",
      "data_buckets" => ["trifle-traces"],
      "data_region" => "us-east-1",
      "data_prefix" => "traces",
      "retention_days" => 7,
      "gzip" => true
    }
  end

  defp file_trace_config do
    %{
      "index_name" => "trifle_traces",
      "data_driver" => "file",
      "data_path" => Path.join(System.tmp_dir!(), "trifle-traces"),
      "retention_days" => 7,
      "gzip" => true
    }
  end

  defp redis_attrs(overrides) do
    Map.merge(
      %{
        display_name: "Primary Redis",
        driver: "redis",
        host: "127.0.0.1",
        port: 6379,
        database_name: "0",
        organization_id: Ecto.UUID.generate()
      },
      overrides
    )
  end

  defp ssh_tunnel_attrs do
    %{
      connection_method: "ssh_tunnel",
      ssh_host: "bastion.example.com",
      ssh_port: 22,
      ssh_username: "trifle",
      ssh_private_key: "-----BEGIN RSA PRIVATE KEY-----\nkey\n-----END RSA PRIVATE KEY-----\n",
      ssh_public_key: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC",
      ssh_host_key_fingerprint: "SHA256:abc123"
    }
  end
end
