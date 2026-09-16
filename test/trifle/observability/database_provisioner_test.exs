defmodule Trifle.Observability.DatabaseProvisionerTest do
  use Trifle.DataCase, async: false

  import Trifle.AccountsFixtures

  alias Trifle.Observability.DatabaseProvisioner
  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  alias Trifle.Repo

  setup do
    previous_mode = Application.get_env(:trifle, :deployment_mode)
    previous_observability = Application.get_env(:trifle, Trifle.Observability)

    on_exit(fn ->
      restore_env(:deployment_mode, previous_mode)
      restore_env(Trifle.Observability, previous_observability)
    end)

    Application.put_env(:trifle, :deployment_mode, :self_hosted)
    :ok
  end

  test "provisions one editable internal Stats + Traces database for the first organization" do
    path = Path.join(System.tmp_dir!(), "trifle-provisioner-#{Ecto.UUID.generate()}")
    on_exit(fn -> File.rm_rf!(path) end)

    configure_file_observability(path)
    user = user_fixture()

    assert {:ok, organization, _membership} =
             Organizations.create_organization_with_owner(%{name: "First organization"}, user)

    database = Repo.get_by!(Database, managed_key: DatabaseProvisioner.managed_key())
    on_exit(fn -> Trifle.DatabasePools.PoolManager.stop_all_pools_for_database(database.id) end)

    assert database.organization_id == organization.id
    assert database.driver == "postgres"
    assert database.config["table_name"] == "trifle_internal_stats"
    assert database.trace_config["index_name"] == "trifle_traces"
    assert database.trace_config["data_driver"] == "file"
    assert database.trace_config["data_path"] == path
    assert Database.capabilities(database) == [:stats, :traces]

    assert {:ok, edited} =
             Organizations.update_database(database, %{display_name: "My internal telemetry"})

    assert {:ok, existing} = DatabaseProvisioner.ensure_internal_database()
    assert existing.id == edited.id
    assert existing.display_name == "My internal telemetry"
  end

  test "does not block organization creation or create a partial source without payload storage" do
    Application.put_env(:trifle, Trifle.Observability,
      enabled: true,
      traces_storage_backend: :none,
      traces_storage_path: nil
    )

    user = user_fixture()

    assert {:ok, organization, _membership} =
             Organizations.create_organization_with_owner(%{name: "Still created"}, user)

    assert organization.name == "Still created"
    assert Repo.get_by(Database, managed_key: DatabaseProvisioner.managed_key()) == nil
  end

  test "disabled observability does not provision a source when an organization is created" do
    Application.put_env(:trifle, Trifle.Observability,
      enabled: false,
      traces_storage_backend: :file,
      traces_storage_path: nil
    )

    user = user_fixture()

    assert {:ok, organization, _membership} =
             Organizations.create_organization_with_owner(%{name: "No internal telemetry"}, user)

    assert {:error, :observability_disabled} =
             DatabaseProvisioner.ensure_internal_database(organization)

    assert Repo.get_by(Database, managed_key: DatabaseProvisioner.managed_key()) == nil
    assert Trifle.Observability.setup() == []
  end

  defp configure_file_observability(path) do
    Application.put_env(:trifle, Trifle.Observability,
      enabled: true,
      traces_storage_backend: :file,
      traces_storage_path: path,
      traces_retention_days: 7,
      traces_gzip: true
    )
  end

  defp restore_env(key, nil), do: Application.delete_env(:trifle, key)
  defp restore_env(key, value), do: Application.put_env(:trifle, key, value)
end
