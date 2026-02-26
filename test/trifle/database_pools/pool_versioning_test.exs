defmodule Trifle.DatabasePools.PoolVersioningTest do
  use Trifle.DataCase, async: false

  import Trifle.OrganizationsFixtures

  alias Trifle.DatabasePools.SqlitePoolSupervisor
  alias Trifle.DatabasePools.VersionRegistry
  alias Trifle.Organizations

  describe "sqlite pool versioning" do
    test "restarts pool when database pool_version increases" do
      database = database_fixture()

      on_exit(fn ->
        _ = SqlitePoolSupervisor.stop_sqlite_pool(database.id)
        _ = File.rm(database.file_path)
      end)

      assert {:ok, connection_name} = SqlitePoolSupervisor.start_sqlite_pool(database)

      pid_before = Process.whereis(connection_name)
      assert is_pid(pid_before)
      assert {:ok, 1} = VersionRegistry.get(:sqlite, database.id)

      assert {:ok, ^connection_name} = SqlitePoolSupervisor.start_sqlite_pool(database)
      assert Process.whereis(connection_name) == pid_before

      new_file_path = Path.join(System.tmp_dir!(), "trifle-db-#{Ecto.UUID.generate()}.sqlite")
      on_exit(fn -> _ = File.rm(new_file_path) end)

      assert {:ok, updated_database} =
               Organizations.update_database(database, %{file_path: new_file_path})

      assert updated_database.pool_version == database.pool_version + 1
      assert {:ok, ^connection_name} = SqlitePoolSupervisor.start_sqlite_pool(updated_database)

      pid_after = Process.whereis(connection_name)
      assert is_pid(pid_after)
      refute pid_after == pid_before

      expected_version = updated_database.pool_version
      assert {:ok, ^expected_version} = VersionRegistry.get(:sqlite, database.id)
    end

    test "delete_database stops active pool" do
      database = database_fixture()
      on_exit(fn -> _ = File.rm(database.file_path) end)

      assert {:ok, connection_name} = SqlitePoolSupervisor.start_sqlite_pool(database)
      assert is_pid(Process.whereis(connection_name))

      assert {:ok, _deleted_database} = Organizations.delete_database(database)

      assert Process.whereis(connection_name) == nil
      assert :error = VersionRegistry.get(:sqlite, database.id)
    end
  end
end
