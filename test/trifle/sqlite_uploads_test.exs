defmodule Trifle.SqliteUploadsTest do
  use ExUnit.Case, async: false

  alias Trifle.SqliteUploads

  defmodule MockObjectStoreClient do
    def put_object(object_key, source_path, _config) do
      destination = object_path(object_key)

      with :ok <- File.mkdir_p(Path.dirname(destination)),
           :ok <- File.cp(source_path, destination) do
        :ok
      end
    end

    def get_object(object_key, destination_path, _config) do
      source = object_path(object_key)

      with :ok <- File.mkdir_p(Path.dirname(destination_path)),
           :ok <- File.cp(source, destination_path) do
        :ok
      else
        {:error, :enoent} -> {:error, {:http_error, 404, "Not Found"}}
        {:error, reason} -> {:error, reason}
      end
    end

    def delete_object(object_key, _config) do
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
  end

  setup do
    previous_root = Application.get_env(:trifle, :sqlite_upload_root)
    previous_max = Application.get_env(:trifle, :sqlite_upload_max_bytes)
    previous_storage_backend = Application.get_env(:trifle, :sqlite_storage_backend)
    previous_cache_root = Application.get_env(:trifle, :sqlite_cache_root)
    previous_object_store = Application.get_env(:trifle, :sqlite_object_store)
    previous_object_store_client = Application.get_env(:trifle, :sqlite_object_store_client)
    previous_mock_root = Application.get_env(:trifle, :sqlite_object_store_mock_root)

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
end
