defmodule Trifle.SqliteUploads do
  @moduledoc false

  require Logger

  @allowed_extensions [".sqlite", ".sqlite3", ".db"]
  @sqlite_storage_key "sqlite_storage"
  @download_lock_timeout_ms 60_000

  def allowed_extensions, do: @allowed_extensions

  def store_upload(%Plug.Upload{path: path, filename: filename}, organization_id) do
    store_upload(%{path: path, filename: filename}, organization_id)
  end

  def store_upload(upload, organization_id) do
    with {:ok, %{file_path: file_path}} <- store_upload_for_database(upload, organization_id) do
      {:ok, file_path}
    end
  end

  def store_upload_for_database(%Plug.Upload{path: path, filename: filename}, organization_id) do
    store_upload_for_database(%{path: path, filename: filename}, organization_id)
  end

  def store_upload_for_database(%{path: path, filename: filename}, organization_id)
      when is_binary(path) and is_binary(filename) do
    with {:ok, normalized_org_id} <- validate_organization_id(organization_id),
         {:ok, extension} <- validate_extension(filename),
         {:ok, stat} <- File.stat(path),
         :ok <- validate_size(stat.size) do
      case Trifle.Config.sqlite_storage_backend() do
        :s3 ->
          store_to_object_storage(path, normalized_org_id, extension, stat.size)

        _ ->
          store_to_local_path(path, normalized_org_id, extension)
      end
    else
      {:error, :enoent} -> {:error, "Uploaded file could not be read"}
      {:error, reason} -> {:error, format_reason(reason)}
    end
  end

  def store_upload_for_database(_upload, _organization_id),
    do: {:error, "Invalid sqlite upload payload"}

  def apply_config_patch(attrs, config_patch) when is_map(attrs) and is_map(config_patch) do
    if map_size(config_patch) == 0 do
      attrs
    else
      existing_config =
        attrs
        |> fetch_key("config")
        |> normalize_map()

      merged_config = deep_merge(existing_config, normalize_map(config_patch))
      Map.put(attrs, "config", merged_config)
    end
  end

  def apply_config_patch(attrs, _config_patch), do: attrs

  def extract_storage_metadata(config) when is_map(config) do
    case fetch_key(config, @sqlite_storage_key) do
      value when is_map(value) -> normalize_map(value)
      _ -> %{}
    end
  end

  def extract_storage_metadata(_config), do: %{}

  def managed_path?(path) when is_binary(path) and path != "" do
    expanded_path = Path.expand(path)

    managed_roots()
    |> Enum.any?(fn root -> path_under_root?(expanded_path, root) end)
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

  def delete_managed_upload(path, config \\ %{}) do
    remote_result = maybe_delete_remote_object(config)
    local_result = delete_managed_file(path)

    case {remote_result, local_result} do
      {{:error, remote_reason}, _} -> {:error, remote_reason}
      {_, {:error, local_reason}} -> {:error, local_reason}
      _ -> :ok
    end
  end

  def resolve_database_path(database) when is_map(database) do
    case database_file_path(database) do
      ":memory:" ->
        {:ok, ":memory:"}

      path when is_binary(path) and path != "" ->
        storage_metadata = database |> database_config() |> extract_storage_metadata()

        case storage_metadata do
          %{"backend" => "s3", "object_key" => object_key} when is_binary(object_key) ->
            ensure_cached_object(object_key, storage_metadata)

          _ ->
            with :ok <- ensure_parent_directory(path) do
              {:ok, path}
            end
        end

      _ ->
        db_dir = Application.get_env(:trifle, :sqlite_db_dir, "/tmp/trifle_sqlite")

        with :ok <- File.mkdir_p(db_dir) do
          {:ok, Path.join(db_dir, "trifle_db_#{fetch_key(database, :id) || "unknown"}.sqlite")}
        end
    end
  end

  def resolve_database_path(_), do: {:error, "Invalid database configuration"}

  defp store_to_local_path(path, organization_id, extension) do
    with {:ok, destination} <- local_destination_path(organization_id, extension),
         :ok <- File.cp(path, destination) do
      {:ok, %{file_path: destination, config_patch: %{}}}
    end
  end

  defp store_to_object_storage(path, organization_id, extension, byte_size) do
    with {:ok, object_store_config} <- object_store_config(),
         {:ok, checksum} <- sha256_file(path),
         {:ok, generated_filename} <- generated_filename(extension),
         object_key = object_key(object_store_config, organization_id, generated_filename),
         {:ok, cache_path} <- cache_path_for_object_key(object_key) do
      with :ok <- ensure_parent_directory(cache_path),
           :ok <- object_store_client().put_object(object_key, path, object_store_config) do
        maybe_seed_local_cache(path, cache_path)

        config_patch = %{
          @sqlite_storage_key => %{
            "backend" => "s3",
            "object_key" => object_key,
            "checksum_sha256" => checksum,
            "size_bytes" => byte_size,
            "bucket" => object_store_config[:bucket],
            "region" => object_store_config[:region],
            "endpoint" => object_store_config[:endpoint]
          }
        }

        {:ok, %{file_path: cache_path, config_patch: config_patch}}
      end
    end
  end

  defp ensure_cached_object(object_key, storage_metadata) do
    with {:ok, cache_path} <- cache_path_for_object_key(object_key),
         {:ok, object_store_config} <- object_store_config(storage_metadata),
         :ok <- ensure_parent_directory(cache_path),
         :ok <-
           with_download_lock(cache_path, fn ->
             ensure_cached_object_locked(cache_path, storage_metadata, object_store_config)
           end) do
      {:ok, cache_path}
    end
  end

  defp ensure_cached_object_locked(cache_path, storage_metadata, object_store_config) do
    if cached_file_valid?(cache_path, storage_metadata) do
      :ok
    else
      object_key = storage_metadata["object_key"]
      temp_path = cache_path <> ".tmp-#{System.unique_integer([:positive])}"

      result =
        with :ok <- object_store_client().get_object(object_key, temp_path, object_store_config),
             :ok <- validate_downloaded_file(temp_path, storage_metadata),
             :ok <- replace_file(temp_path, cache_path) do
          :ok
        end

      case result do
        :ok ->
          :ok

        {:error, reason} ->
          _ = File.rm(temp_path)
          {:error, format_reason(reason)}
      end
    end
  end

  defp with_download_lock(cache_path, fun) when is_function(fun, 0) do
    case :global.trans(
           {:sqlite_cache_download, cache_path},
           fun,
           [node()],
           @download_lock_timeout_ms
         ) do
      {:aborted, reason} ->
        {:error, "SQLite cache lock acquisition failed: #{inspect(reason)}"}

      result ->
        result
    end
  end

  defp cached_file_valid?(path, storage_metadata) do
    with {:ok, stat} <- File.stat(path),
         :ok <- validate_cached_size(stat.size, storage_metadata),
         :ok <- validate_cached_checksum(path, storage_metadata) do
      true
    else
      _ -> false
    end
  end

  defp validate_cached_size(size, storage_metadata) do
    case expected_size(storage_metadata) do
      nil -> :ok
      expected when is_integer(expected) -> if(size == expected, do: :ok, else: :error)
    end
  end

  defp validate_cached_checksum(path, storage_metadata) do
    case expected_checksum(storage_metadata) do
      nil ->
        :ok

      :unsupported ->
        :error

      {:sha256, expected_checksum} ->
        case sha256_file(path) do
          {:ok, actual_checksum} ->
            if String.downcase(actual_checksum) == expected_checksum do
              :ok
            else
              :error
            end

          {:error, _reason} ->
            :error
        end
    end
  end

  defp validate_downloaded_file(path, storage_metadata) do
    with :ok <- validate_downloaded_size(path, storage_metadata),
         :ok <- validate_downloaded_checksum(path, storage_metadata) do
      :ok
    end
  end

  defp validate_downloaded_size(path, storage_metadata) do
    case expected_size(storage_metadata) do
      nil ->
        :ok

      expected ->
        case File.stat(path) do
          {:ok, %{size: ^expected}} ->
            :ok

          {:ok, %{size: actual}} ->
            {:error, "Downloaded SQLite file size mismatch (expected #{expected}, got #{actual})"}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp validate_downloaded_checksum(path, storage_metadata) do
    case Map.get(storage_metadata, "checksum_sha256") do
      checksum when is_binary(checksum) and checksum != "" ->
        with {:ok, actual_checksum} <- sha256_file(path) do
          if String.downcase(actual_checksum) == String.downcase(checksum) do
            :ok
          else
            {:error, "Downloaded SQLite file checksum mismatch"}
          end
        end

      _ ->
        :ok
    end
  end

  defp replace_file(from_path, to_path) do
    case File.rename(from_path, to_path) do
      :ok ->
        :ok

      {:error, :eexist} ->
        with :ok <- File.rm(to_path),
             :ok <- File.rename(from_path, to_path) do
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_delete_remote_object(config) do
    storage_metadata = extract_storage_metadata(config)

    case storage_metadata do
      %{"backend" => "s3", "object_key" => object_key}
      when is_binary(object_key) and object_key != "" ->
        with {:ok, object_store_config} <- object_store_config(storage_metadata) do
          case object_store_client().delete_object(object_key, object_store_config) do
            :ok ->
              :ok

            {:error, {:http_error, 404, _body_preview}} ->
              :ok

            {:error, reason} ->
              {:error, reason}
          end
        end

      _ ->
        :ok
    end
  end

  defp object_store_config(_storage_metadata \\ %{}) do
    base_config = Trifle.Config.sqlite_object_store_config()

    config = %{
      endpoint: base_config[:endpoint],
      bucket: base_config[:bucket],
      region: base_config[:region],
      access_key_id: base_config[:access_key_id],
      secret_access_key: base_config[:secret_access_key],
      force_path_style: base_config[:force_path_style],
      prefix: base_config[:prefix]
    }

    missing =
      [
        {:endpoint, config[:endpoint]},
        {:bucket, config[:bucket]},
        {:region, config[:region]},
        {:access_key_id, config[:access_key_id]},
        {:secret_access_key, config[:secret_access_key]}
      ]
      |> Enum.filter(fn {_key, value} -> value in [nil, ""] end)
      |> Enum.map(fn {key, _value} -> key end)

    case missing do
      [] -> {:ok, config}
      _ -> {:error, "SQLite object storage missing config: #{Enum.join(missing, ", ")}"}
    end
  end

  defp object_store_client do
    Application.get_env(:trifle, :sqlite_object_store_client, Trifle.SqliteUploads.S3Client)
  end

  defp maybe_seed_local_cache(source_path, destination_path) do
    case File.cp(source_path, destination_path) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Failed to seed SQLite local cache after upload",
          cache_path: destination_path,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp object_key(object_store_config, organization_id, generated_filename) do
    prefix = object_store_config[:prefix]

    [prefix, "organization_#{organization_id}", "sqlite", generated_filename]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("/")
  end

  defp cache_path_for_object_key(object_key) when is_binary(object_key) do
    cache_root = Trifle.Config.sqlite_cache_root()
    expanded_cache_root = Path.expand(cache_root)

    object_segments =
      object_key
      |> then(&Regex.split(~r{[\\/]+}, &1, trim: true))
      |> Enum.reject(&(&1 == ""))

    has_path_traversal? = Enum.any?(object_segments, &(&1 in [".", ".."]))
    absolute_path? = Path.type(object_key) == :absolute

    cond do
      absolute_path? or has_path_traversal? or object_segments == [] ->
        {:error, "Invalid SQLite object storage key"}

      true ->
        cache_path = Path.join([expanded_cache_root | object_segments])
        expanded_cache_path = Path.expand(cache_path)

        if path_under_root?(expanded_cache_path, expanded_cache_root) do
          {:ok, expanded_cache_path}
        else
          {:error, "Invalid SQLite object storage key"}
        end
    end
  end

  defp cache_path_for_object_key(_object_key), do: {:error, "Invalid SQLite object storage key"}

  defp local_destination_path(organization_id, extension) do
    base_dir =
      Trifle.Config.sqlite_upload_root()
      |> Path.expand()
      |> Path.join("organization_#{organization_id}")
      |> Path.join("sqlite")

    with :ok <- File.mkdir_p(base_dir),
         {:ok, generated_filename} <- generated_filename(extension) do
      {:ok, Path.join(base_dir, generated_filename)}
    end
  end

  defp generated_filename(extension) when is_binary(extension) do
    {:ok, "#{System.system_time(:millisecond)}_#{Ecto.UUID.generate()}#{extension}"}
  end

  defp validate_organization_id(organization_id) when is_binary(organization_id) do
    case Ecto.UUID.cast(organization_id) do
      {:ok, normalized_org_id} -> {:ok, normalized_org_id}
      :error -> {:error, "Unable to resolve organization for upload"}
    end
  end

  defp validate_organization_id(_), do: {:error, "Unable to resolve organization for upload"}

  defp validate_extension(filename) when is_binary(filename) do
    extension =
      filename
      |> Path.basename()
      |> Path.extname()
      |> String.downcase()

    if extension in @allowed_extensions do
      {:ok, extension}
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

  defp sha256_file(path) do
    path
    |> File.stream!([], 2048)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
      :crypto.hash_update(acc, chunk)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
    |> then(&{:ok, &1})
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp expected_size(storage_metadata) do
    case Map.get(storage_metadata, "size_bytes") do
      size when is_integer(size) and size >= 0 ->
        size

      size when is_binary(size) ->
        case Integer.parse(size) do
          {parsed, ""} when parsed >= 0 -> parsed
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp expected_checksum(storage_metadata) do
    case Map.fetch(storage_metadata, "checksum_sha256") do
      :error ->
        nil

      {:ok, checksum} when is_binary(checksum) ->
        normalized_checksum =
          checksum
          |> String.trim()
          |> String.downcase()

        if normalized_checksum == "" do
          :unsupported
        else
          {:sha256, normalized_checksum}
        end

      {:ok, _} ->
        :unsupported
    end
  end

  defp database_file_path(database) when is_map(database) do
    fetch_key(database, :file_path) || fetch_key(database, "file_path")
  end

  defp database_config(database) when is_map(database) do
    database
    |> fetch_key(:config)
    |> case do
      nil -> fetch_key(database, "config")
      value -> value
    end
    |> normalize_map()
  end

  defp fetch_key(map, key) when is_map(map), do: Map.get(map, key)
  defp fetch_key(_map, _key), do: nil

  defp normalize_map(nil), do: %{}
  defp normalize_map(value) when is_map(value), do: stringify_keys(value)

  defp normalize_map(value) when is_list(value) do
    value
    |> Enum.into(%{})
    |> stringify_keys()
  rescue
    _ -> %{}
  end

  defp normalize_map(_value), do: %{}

  defp stringify_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      normalized_key =
        case key do
          value when is_atom(value) -> Atom.to_string(value)
          value when is_binary(value) -> value
          value -> to_string(value)
        end

      normalized_value =
        case value do
          nested when is_map(nested) ->
            stringify_keys(nested)

          nested when is_list(nested) ->
            if Keyword.keyword?(nested) do
              stringify_keys(Enum.into(nested, %{}))
            else
              nested
            end

          other ->
            other
        end

      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end

  defp ensure_parent_directory(path) when is_binary(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  defp path_under_root?(expanded_path, root) when is_binary(root) and root != "" do
    expanded_root = Path.expand(root)
    expanded_path == expanded_root || String.starts_with?(expanded_path, expanded_root <> "/")
  end

  defp path_under_root?(_expanded_path, _root), do: false

  defp managed_roots do
    [Trifle.Config.sqlite_upload_root(), Trifle.Config.sqlite_cache_root()]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
  end

  defp format_reason(reason) when is_binary(reason), do: reason

  defp format_reason({:http_error, status, body}),
    do: "Object storage request failed (#{status}): #{body}"

  defp format_reason({:request_failed, reason}),
    do: "Object storage request failed: #{inspect(reason)}"

  defp format_reason(reason), do: "SQLite upload failed: #{inspect(reason)}"
end
