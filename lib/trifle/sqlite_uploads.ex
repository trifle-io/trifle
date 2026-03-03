defmodule Trifle.SqliteUploads do
  @moduledoc false

  @allowed_extensions [".sqlite", ".sqlite3", ".db"]

  def allowed_extensions, do: @allowed_extensions

  def store_upload(%Plug.Upload{path: path, filename: filename}, organization_id) do
    store_upload(%{path: path, filename: filename}, organization_id)
  end

  def store_upload(%{path: path, filename: filename}, organization_id)
      when is_binary(path) and is_binary(filename) do
    with :ok <- validate_organization_id(organization_id),
         :ok <- validate_extension(filename),
         {:ok, stat} <- File.stat(path),
         :ok <- validate_size(stat.size),
         {:ok, destination} <- destination_path(organization_id, filename),
         :ok <- File.cp(path, destination) do
      {:ok, destination}
    else
      {:error, :enoent} -> {:error, "Uploaded file could not be read"}
      {:error, reason} -> {:error, format_reason(reason)}
    end
  end

  def store_upload(_upload, _organization_id), do: {:error, "Invalid sqlite upload payload"}

  def managed_path?(path) when is_binary(path) and path != "" do
    expanded_root = Trifle.Config.sqlite_upload_root() |> Path.expand()
    expanded_path = Path.expand(path)

    expanded_path == expanded_root || String.starts_with?(expanded_path, expanded_root <> "/")
  end

  def managed_path?(_), do: false

  def delete_managed_file(path) when is_binary(path) and path != "" do
    if managed_path?(path) do
      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  def delete_managed_file(_), do: :ok

  defp validate_organization_id(organization_id)
       when is_binary(organization_id) and organization_id != "",
       do: :ok

  defp validate_organization_id(_), do: {:error, "Unable to resolve organization for upload"}

  defp validate_extension(filename) when is_binary(filename) do
    extension =
      filename
      |> Path.basename()
      |> Path.extname()
      |> String.downcase()

    if extension in @allowed_extensions do
      :ok
    else
      {:error,
       "Unsupported SQLite file type. Use one of: #{Enum.join(@allowed_extensions, ", ")}"}
    end
  end

  defp validate_size(size) when is_integer(size) and size >= 0 do
    max_size = Trifle.Config.sqlite_upload_max_bytes()

    if size <= max_size do
      :ok
    else
      {:error, "SQLite upload exceeds size limit of #{max_size} bytes"}
    end
  end

  defp validate_size(_), do: {:error, "Uploaded file size is invalid"}

  defp destination_path(organization_id, filename) do
    extension =
      filename
      |> Path.basename()
      |> Path.extname()
      |> String.downcase()

    base_dir =
      Trifle.Config.sqlite_upload_root()
      |> Path.expand()
      |> Path.join("organization_#{organization_id}")
      |> Path.join("sqlite")

    with :ok <- File.mkdir_p(base_dir) do
      generated_filename =
        "#{System.system_time(:millisecond)}_#{Ecto.UUID.generate()}#{extension}"

      {:ok, Path.join(base_dir, generated_filename)}
    end
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: "SQLite upload failed: #{inspect(reason)}"
end
