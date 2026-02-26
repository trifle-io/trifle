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

    test "provides mysql defaults" do
      assert Database.default_port("mysql") == 3306

      assert Database.default_config_options("mysql") == %{
               "pool_size" => 10,
               "pool_timeout" => 15_000,
               "timeout" => 15_000,
               "table_name" => "trifle_stats",
               "joined_identifiers" => "full"
             }
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
      assert database.config["table_name"] == "trifle_stats"
      assert database.config["joined_identifiers"] == "full"
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
end
