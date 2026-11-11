defmodule Trifle.SqliteUploadsTest do
  use ExUnit.Case, async: false

  alias Trifle.SqliteUploads

  defmodule MockObjectStoreClient do
    def put_object(object_key, source_path, config) do
      maybe_notify({:put_object_config, object_key, config})
      destination = object_path(object_key)

      with :ok <- File.mkdir_p(Path.dirname(destination)),
           :ok <- File.cp(source_path, destination) do
        :ok
      end
    end

    def get_object(object_key, destination_path, config) do
      maybe_notify({:get_object_config, object_key, config})
      source = object_path(object_key)

      with :ok <- File.mkdir_p(Path.dirname(destination_path)),
           :ok <- File.cp(source, destination_path) do
        :ok
      else
        {:error, :enoent} -> {:error, {:http_error, 404, "Not Found"}}
        {:error, reason} -> {:error, reason}
      end
    end

    def delete_object(object_key, config) do
      maybe_notify({:delete_object_config, object_key, config})

      case File.rm(object_path(object_key)) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end

    def object_exists?(object_key), do: File.exists?(object_path(object_key))

    defp object_path(object_key) do
      Path.join(mock_root(), object_key)
    end

    defp mock_root do
      Application.fetch_env!(:trifle, :sqlite_object_store_mock_root)
    end

    defp maybe_notify(message) do
      case Application.get_env(:trifle, :sqlite_object_store_test_pid) do
        pid when is_pid(pid) -> send(pid, message)
        _ -> :ok
      end
    end
  end

  setup do
    previous_root = Application.get_env(:trifle, :sqlite_upload_root)
    previous_max = Application.get_env(:trifle, :sqlite_upload_max_bytes)
    previous_storage_backend = Application.get_env(:trifle, :sqlite_storage_backend)
    previous_cache_root = Application.get_env(:trifle, :sqlite_cache_root)
    previous_object_store = Application.get_env(:trifle, :sqlite_object_store)
    previous_object_store_client = Application.get_env(:trifle, :sqlite_object_store_client)
    previous_mock_root = Application.get_env(:trifle, :sqlite_object_store_mock_root)
    previous_test_pid = Application.get_env(:trifle, :sqlite_object_store_test_pid)

    root = Path.join(System.tmp_dir!(), "trifle-sqlite-upload-test-#{Ecto.UUID.generate()}")
    cache_root = Path.join(System.tmp_dir!(), "trifle-sqlite-cache-test-#{Ecto.UUID.generate()}")

    mock_root =
      Path.join(System.tmp_dir!(), "trifle-sqlite-object-store-test-#{Ecto.UUID.generate()}")

    Application.put_env(:trifle, :sqlite_upload_root, root)
    Application.put_env(:trifle, :sqlite_upload_max_bytes, 100 * 1024 * 1024)
    Application.put_env(:trifle, :sqlite_storage_backend, :local)
    Application.put_env(:trifle, :sqlite_cache_root, cache_root)

    Application.put_env(:trifle, :sqlite_object_store, %{
      endpoint: "https://objects.example.test",
      bucket: "sqlite-files",
      region: "us-east-1",
      access_key_id: "test-access-key",
      secret_access_key: "test-secret-key",
      force_path_style: true,
      prefix: "sqlite-files"
    })

    Application.put_env(:trifle, :sqlite_object_store_client, MockObjectStoreClient)
    Application.put_env(:trifle, :sqlite_object_store_mock_root, mock_root)
    Application.delete_env(:trifle, :sqlite_object_store_test_pid)

    on_exit(fn ->
      _ = File.rm_rf(root)
      _ = File.rm_rf(cache_root)
      _ = File.rm_rf(mock_root)
      Application.put_env(:trifle, :sqlite_upload_root, previous_root)
      Application.put_env(:trifle, :sqlite_upload_max_bytes, previous_max)
      Application.put_env(:trifle, :sqlite_storage_backend, previous_storage_backend)
      Application.put_env(:trifle, :sqlite_cache_root, previous_cache_root)
      Application.put_env(:trifle, :sqlite_object_store, previous_object_store)
      Application.put_env(:trifle, :sqlite_object_store_client, previous_object_store_client)
      Application.put_env(:trifle, :sqlite_object_store_mock_root, previous_mock_root)
      Application.put_env(:trifle, :sqlite_object_store_test_pid, previous_test_pid)
    end)

    :ok
  end

  test "stores sqlite upload in organization-prefixed directory" do
    org_id = Ecto.UUID.generate()
    input_path = Path.join(System.tmp_dir!(), "sqlite-input-#{Ecto.UUID.generate()}.sqlite")
    File.write!(input_path, "sqlite")

    on_exit(fn -> File.rm(input_path) end)

    assert {:ok, stored_path} =
             SqliteUploads.store_upload(%{path: input_path, filename: "metrics.sqlite"}, org_id)

    assert stored_path =~ "/organization_#{org_id}/sqlite/"
    assert File.exists?(stored_path)
    assert SqliteUploads.managed_path?(stored_path)
  end

  test "stores sqlite upload in object storage and seeds local cache when backend is s3" do
    Application.put_env(:trifle, :sqlite_storage_backend, :s3)

    org_id = Ecto.UUID.generate()
    input_path = Path.join(System.tmp_dir!(), "sqlite-input-#{Ecto.UUID.generate()}.sqlite")
    payload = "sqlite-object-store"
    File.write!(input_path, payload)

    on_exit(fn -> File.rm(input_path) end)

    assert {:ok, %{file_path: cache_path, config_patch: config_patch}} =
             SqliteUploads.store_upload_for_database(
               %{path: input_path, filename: "metrics.sqlite"},
               org_id
             )

    assert cache_path =~ "/sqlite-files/organization_#{org_id}/sqlite/"
    assert File.read!(cache_path) == payload

    assert %{
             "sqlite_storage" => %{
               "backend" => "s3",
               "object_key" => object_key,
               "checksum_sha256" => _checksum,
               "size_bytes" => size_bytes
             }
           } = config_patch

    assert size_bytes == byte_size(payload)
    assert MockObjectStoreClient.object_exists?(object_key)
  end

  test "resolves s3-backed sqlite file by downloading object into cache when missing" do
    Application.put_env(:trifle, :sqlite_storage_backend, :s3)

    org_id = Ecto.UUID.generate()
    input_path = Path.join(System.tmp_dir!(), "sqlite-input-#{Ecto.UUID.generate()}.sqlite")
    payload = "sqlite-download-cache"
    File.write!(input_path, payload)

    on_exit(fn -> File.rm(input_path) end)

    assert {:ok, %{file_path: cache_path, config_patch: config_patch}} =
             SqliteUploads.store_upload_for_database(
               %{path: input_path, filename: "metrics.sqlite"},
               org_id
             )

    :ok = File.rm(cache_path)
    refute File.exists?(cache_path)

    database = %{
      id: Ecto.UUID.generate(),
      file_path: cache_path,
      config: config_patch
    }

    assert {:ok, resolved_path} = SqliteUploads.resolve_database_path(database)
    assert resolved_path == cache_path
    assert File.read!(resolved_path) == payload
  end

  test "deletes s3-backed sqlite upload from object store and local cache" do
    Application.put_env(:trifle, :sqlite_storage_backend, :s3)

    org_id = Ecto.UUID.generate()
    input_path = Path.join(System.tmp_dir!(), "sqlite-input-#{Ecto.UUID.generate()}.sqlite")
    File.write!(input_path, "sqlite-delete")

    on_exit(fn -> File.rm(input_path) end)

    assert {:ok, %{file_path: cache_path, config_patch: config_patch}} =
             SqliteUploads.store_upload_for_database(
               %{path: input_path, filename: "metrics.sqlite"},
               org_id
             )

    object_key = get_in(config_patch, ["sqlite_storage", "object_key"])
    assert File.exists?(cache_path)
    assert MockObjectStoreClient.object_exists?(object_key)

    assert :ok = SqliteUploads.delete_managed_upload(cache_path, config_patch)
    refute File.exists?(cache_path)
    refute MockObjectStoreClient.object_exists?(object_key)
  end

  test "resolves s3-backed sqlite path from object_key instead of persisted file_path" do
    Application.put_env(:trifle, :sqlite_storage_backend, :s3)

    org_id = Ecto.UUID.generate()
    input_path = Path.join(System.tmp_dir!(), "sqlite-input-#{Ecto.UUID.generate()}.sqlite")
    payload = "sqlite-safe-cache-path"
    File.write!(input_path, payload)

    on_exit(fn -> File.rm(input_path) end)

    assert {:ok, %{config_patch: config_patch}} =
             SqliteUploads.store_upload_for_database(
               %{path: input_path, filename: "metrics.sqlite"},
               org_id
             )

    persisted_path =
      Path.join(System.tmp_dir!(), "sqlite-persisted-path-#{Ecto.UUID.generate()}.sqlite")

    database = %{
      id: Ecto.UUID.generate(),
      file_path: persisted_path,
      config: config_patch
    }

    assert {:ok, resolved_path} = SqliteUploads.resolve_database_path(database)
    refute resolved_path == persisted_path
    assert String.starts_with?(resolved_path, Trifle.Config.sqlite_cache_root())
    assert File.read!(resolved_path) == payload
  end

  test "rejects invalid s3 object key when resolving sqlite cache path" do
    Application.put_env(:trifle, :sqlite_storage_backend, :s3)

    database = %{
      id: Ecto.UUID.generate(),
      file_path: "/tmp/ignored.sqlite",
      config: %{
        "sqlite_storage" => %{
          "backend" => "s3",
          "object_key" => "../escape.sqlite",
          "size_bytes" => 10
        }
      }
    }

    assert {:error, reason} = SqliteUploads.resolve_database_path(database)
    assert reason =~ "Invalid SQLite object storage key"
  end

  test "re-downloads cached sqlite file when checksum does not match" do
    Application.put_env(:trifle, :sqlite_storage_backend, :s3)

    org_id = Ecto.UUID.generate()
    input_path = Path.join(System.tmp_dir!(), "sqlite-input-#{Ecto.UUID.generate()}.sqlite")
    payload = "abcdef"
    File.write!(input_path, payload)

    on_exit(fn -> File.rm(input_path) end)

    assert {:ok, %{file_path: cache_path, config_patch: config_patch}} =
             SqliteUploads.store_upload_for_database(
               %{path: input_path, filename: "metrics.sqlite"},
               org_id
             )

    File.write!(cache_path, "ghijkl")

    database = %{
      id: Ecto.UUID.generate(),
      file_path: cache_path,
      config: config_patch
    }

    assert {:ok, resolved_path} = SqliteUploads.resolve_database_path(database)
    assert File.read!(resolved_path) == payload
  end

  test "uses configured object store endpoint bucket and region over metadata overrides" do
    Application.put_env(:trifle, :sqlite_storage_backend, :s3)

    org_id = Ecto.UUID.generate()
    input_path = Path.join(System.tmp_dir!(), "sqlite-input-#{Ecto.UUID.generate()}.sqlite")
    File.write!(input_path, "sqlite-delete")

    on_exit(fn -> File.rm(input_path) end)

    assert {:ok, %{file_path: cache_path, config_patch: config_patch}} =
             SqliteUploads.store_upload_for_database(
               %{path: input_path, filename: "metrics.sqlite"},
               org_id
             )

    object_key = get_in(config_patch, ["sqlite_storage", "object_key"])

    tampered_config =
      config_patch
      |> put_in(["sqlite_storage", "endpoint"], "https://evil.example.test")
      |> put_in(["sqlite_storage", "bucket"], "evil-bucket")
      |> put_in(["sqlite_storage", "region"], "eu-west-1")

    Application.put_env(:trifle, :sqlite_object_store_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:trifle, :sqlite_object_store_test_pid)
    end)

    assert :ok = SqliteUploads.delete_managed_upload(cache_path, tampered_config)

    assert_receive {:delete_object_config, ^object_key, object_store_config}
    assert object_store_config.endpoint == "https://objects.example.test"
    assert object_store_config.bucket == "sqlite-files"
    assert object_store_config.region == "us-east-1"
    refute MockObjectStoreClient.object_exists?(object_key)
  end

  test "skips checksum validation for unsupported checksum metadata" do
    Application.put_env(:trifle, :sqlite_storage_backend, :s3)

    org_id = Ecto.UUID.generate()
    input_path = Path.join(System.tmp_dir!(), "sqlite-input-#{Ecto.UUID.generate()}.sqlite")
    payload = "abcdef"
    File.write!(input_path, payload)

    on_exit(fn -> File.rm(input_path) end)

    assert {:ok, %{file_path: cache_path, config_patch: config_patch}} =
             SqliteUploads.store_upload_for_database(
               %{path: input_path, filename: "metrics.sqlite"},
               org_id
             )

    Application.put_env(:trifle, :sqlite_object_store_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:trifle, :sqlite_object_store_test_pid)
    end)

    File.write!(cache_path, "ghijkl")

    database = %{
      id: Ecto.UUID.generate(),
      file_path: cache_path,
      config: put_in(config_patch, ["sqlite_storage", "checksum_sha256"], 123)
    }

    assert {:ok, resolved_path} = SqliteUploads.resolve_database_path(database)
    refute_receive {:get_object_config, _, _}
    assert File.read!(resolved_path) == "ghijkl"
  end

  test "rejects unsupported sqlite upload extension" do
    org_id = Ecto.UUID.generate()
    input_path = Path.join(System.tmp_dir!(), "sqlite-input-#{Ecto.UUID.generate()}.txt")
    File.write!(input_path, "not sqlite")

    on_exit(fn -> File.rm(input_path) end)

    assert {:error, reason} =
             SqliteUploads.store_upload(%{path: input_path, filename: "metrics.txt"}, org_id)

    assert reason =~ "Unsupported SQLite file type"
  end

  test "enforces configurable sqlite upload max bytes" do
    previous_max = Application.get_env(:trifle, :sqlite_upload_max_bytes)
    Application.put_env(:trifle, :sqlite_upload_max_bytes, 4)

    on_exit(fn ->
      Application.put_env(:trifle, :sqlite_upload_max_bytes, previous_max)
    end)

    org_id = Ecto.UUID.generate()
    input_path = Path.join(System.tmp_dir!(), "sqlite-input-#{Ecto.UUID.generate()}.sqlite")
    File.write!(input_path, "12345")

    on_exit(fn -> File.rm(input_path) end)

    assert {:error, reason} =
             SqliteUploads.store_upload(%{path: input_path, filename: "metrics.sqlite"}, org_id)

    assert reason =~ "size limit"
  end

  test "rejects invalid organization id" do
    input_path = Path.join(System.tmp_dir!(), "sqlite-input-#{Ecto.UUID.generate()}.sqlite")
    File.write!(input_path, "sqlite")

    on_exit(fn -> File.rm(input_path) end)

    assert {:error, reason} =
             SqliteUploads.store_upload(%{path: input_path, filename: "metrics.sqlite"}, "../bad")

    assert reason == "Unable to resolve organization for upload"
  end

  describe "organization scoping" do
    setup do
      previous_mode = Application.get_env(:trifle, :deployment_mode)
      Application.put_env(:trifle, :deployment_mode, :saas)

      on_exit(fn ->
        if is_nil(previous_mode),
          do: Application.delete_env(:trifle, :deployment_mode),
          else: Application.put_env(:trifle, :deployment_mode, previous_mode)
      end)

      {:ok, org_id: Ecto.UUID.generate(), other_org_id: Ecto.UUID.generate()}
    end

    test "re-roots arbitrary server paths under the organization folder", %{org_id: org_id} do
      root = Path.expand(Trifle.Config.sqlite_upload_root())
      org_root = Path.join([root, "organization_#{org_id}", "sqlite", "manual"])

      assert {:ok, scoped} = SqliteUploads.scope_file_path("/etc/secrets/app.sqlite", org_id)
      assert scoped == Path.join(org_root, "etc/secrets/app.sqlite")

      assert {:ok, traversal} = SqliteUploads.scope_file_path("../../../etc/passwd", org_id)
      assert traversal == Path.join(org_root, "etc/passwd")

      assert {:ok, relative} = SqliteUploads.scope_file_path("metrics.sqlite", org_id)
      assert relative == Path.join(org_root, "metrics.sqlite")

      for path <- [scoped, traversal, relative] do
        assert SqliteUploads.organization_path?(path, org_id)
      end
    end

    test "keeps paths already inside the organization and re-roots other tenants' paths", %{
      org_id: org_id,
      other_org_id: other_org_id
    } do
      root = Path.expand(Trifle.Config.sqlite_upload_root())
      own = Path.join([root, "organization_#{org_id}", "sqlite", "a.sqlite"])
      foreign = Path.join([root, "organization_#{other_org_id}", "sqlite", "a.sqlite"])

      assert {:ok, ^own} = SqliteUploads.scope_file_path(own, org_id)

      assert {:ok, rerooted} = SqliteUploads.scope_file_path(foreign, org_id)
      refute rerooted == foreign
      assert SqliteUploads.organization_path?(rerooted, org_id)
      refute SqliteUploads.organization_path?(foreign, org_id)

      # A nested folder named after this organization inside another tenant's folder
      # does not make the path ours.
      sneaky =
        Path.join([root, "organization_#{other_org_id}", "organization_#{org_id}", "a.sqlite"])

      refute SqliteUploads.organization_path?(sneaky, org_id)
    end

    test "object keys must live under the organization prefix", %{
      org_id: org_id,
      other_org_id: other_org_id
    } do
      assert SqliteUploads.organization_object_key?(
               "sqlite-files/organization_#{org_id}/sqlite/a.sqlite",
               org_id
             )

      refute SqliteUploads.organization_object_key?(
               "sqlite-files/organization_#{other_org_id}/sqlite/a.sqlite",
               org_id
             )

      refute SqliteUploads.organization_object_key?(
               "sqlite-files/organization_#{org_id}/../organization_#{other_org_id}/a.sqlite",
               org_id
             )

      refute SqliteUploads.organization_object_key?("sqlite-files/a.sqlite", org_id)
    end

    test "refuses to open another organization's file or object", %{
      org_id: org_id,
      other_org_id: other_org_id
    } do
      root = Path.expand(Trifle.Config.sqlite_upload_root())
      foreign = Path.join([root, "organization_#{other_org_id}", "sqlite", "a.sqlite"])

      assert {:error, message} =
               SqliteUploads.resolve_database_path(%{
                 organization_id: org_id,
                 file_path: foreign,
                 config: %{}
               })

      assert message =~ "outside this organization"

      assert {:error, _} =
               SqliteUploads.resolve_database_path(%{
                 organization_id: org_id,
                 file_path: "/etc/passwd",
                 config: %{}
               })

      assert {:error, _} =
               SqliteUploads.resolve_database_path(%{
                 organization_id: org_id,
                 file_path: foreign,
                 config: %{
                   "sqlite_storage" => %{
                     "backend" => "s3",
                     "object_key" => "sqlite-files/organization_#{other_org_id}/sqlite/a.sqlite"
                   }
                 }
               })
    end

    test "does not delete another organization's file", %{
      org_id: org_id,
      other_org_id: other_org_id
    } do
      root = Path.expand(Trifle.Config.sqlite_upload_root())
      foreign = Path.join([root, "organization_#{other_org_id}", "sqlite", "keep.sqlite"])
      File.mkdir_p!(Path.dirname(foreign))
      File.write!(foreign, "data")
      on_exit(fn -> File.rm_rf(Path.join(root, "organization_#{other_org_id}")) end)

      assert :ok = SqliteUploads.delete_managed_upload(foreign, %{}, org_id)
      assert File.exists?(foreign)

      assert :ok = SqliteUploads.delete_managed_upload(foreign, %{}, other_org_id)
      refute File.exists?(foreign)
    end
  end
end
