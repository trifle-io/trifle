defmodule Trifle.SqliteUploadsTest do
  use ExUnit.Case, async: false

  alias Trifle.SqliteUploads

  setup do
    previous_root = Application.get_env(:trifle, :sqlite_upload_root)
    previous_max = Application.get_env(:trifle, :sqlite_upload_max_bytes)

    root = Path.join(System.tmp_dir!(), "trifle-sqlite-upload-test-#{Ecto.UUID.generate()}")
    Application.put_env(:trifle, :sqlite_upload_root, root)
    Application.put_env(:trifle, :sqlite_upload_max_bytes, 100 * 1024 * 1024)

    on_exit(fn ->
      _ = File.rm_rf(root)
      Application.put_env(:trifle, :sqlite_upload_root, previous_root)
      Application.put_env(:trifle, :sqlite_upload_max_bytes, previous_max)
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
