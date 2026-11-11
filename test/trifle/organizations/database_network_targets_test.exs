defmodule Trifle.Organizations.DatabaseNetworkTargetsTest do
  # Flips the global SSRF-guard setting.
  use Trifle.DataCase, async: false

  import Trifle.OrganizationsFixtures

  alias Trifle.Networking.DatabaseEndpoint
  alias Trifle.Organizations
  alias Trifle.Organizations.Database

  setup do
    previous = Application.get_env(:trifle, :allow_private_network_targets)
    Application.put_env(:trifle, :allow_private_network_targets, false)
    on_exit(fn -> Application.put_env(:trifle, :allow_private_network_targets, previous) end)

    %{organization: organization_fixture()}
  end

  defp postgres_attrs(host) do
    %{
      display_name: "Tenant DB",
      driver: "postgres",
      host: host,
      port: 5432,
      database_name: "app",
      username: "u",
      password: "p"
    }
  end

  test "tenant databases cannot target internal hosts", %{organization: organization} do
    for host <- ["127.0.0.1", "localhost", "169.254.169.254", "10.0.0.8", "postgres"] do
      assert {:error, changeset} =
               Organizations.create_database_for_org(organization, postgres_attrs(host))

      assert {message, _} = changeset.errors[:host]
      assert message =~ "public host"
    end
  end

  test "public hosts are accepted", %{organization: organization} do
    assert {:ok, %Database{host: "db.example.com"}} =
             Organizations.create_database_for_org(organization, postgres_attrs("db.example.com"))
  end

  test "an internal host is refused again at connection time", %{organization: organization} do
    # A row saved before the guard existed (or while it was off).
    database = %Database{
      organization_id: organization.id,
      driver: "postgres",
      connection_method: "direct",
      host: "127.0.0.1",
      port: 5432
    }

    assert DatabaseEndpoint.resolve(database) == {:error, :forbidden_host}
  end

  test "platform-managed databases may use internal hosts", %{organization: organization} do
    database = %Database{
      organization_id: organization.id,
      driver: "postgres",
      connection_method: "direct",
      host: "127.0.0.1",
      port: 5432,
      managed_key: "internal_observability"
    }

    assert {:ok, %{host: "127.0.0.1", via: :direct}} = DatabaseEndpoint.resolve(database)
  end

  test "tenant trace storage cannot use local files or internal S3 endpoints", %{
    organization: organization
  } do
    base = postgres_attrs("db.example.com")

    assert {:error, file_changeset} =
             Organizations.create_database_for_org(
               organization,
               Map.put(base, :trace_config, %{"data_driver" => "file", "data_path" => "/proc"})
             )

    assert {message, _} = file_changeset.errors[:trace_config]
    assert message =~ "not available"

    s3 = %{
      "data_driver" => "s3",
      "data_buckets" => ["traces"],
      "data_region" => "us-east-1",
      "data_prefix" => "t",
      "data_endpoint" => "http://169.254.169.254"
    }

    assert {:error, s3_changeset} =
             Organizations.create_database_for_org(organization, Map.put(base, :trace_config, s3))

    assert Enum.any?(Keyword.get_values(s3_changeset.errors, :trace_config), fn {message, _} ->
             message =~ "public host"
           end)
  end
end
