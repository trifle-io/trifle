defmodule Trifle.Config do
  @moduledoc false

  @default_sqlite_upload_max_bytes 100 * 1024 * 1024
  @default_request_body_max_bytes 8_000_000
  @default_sqlite_storage_backend :local

  @spec deployment_mode() :: :saas | :self_hosted
  def deployment_mode do
    :trifle
    |> Application.get_env(:deployment_mode, :saas)
    |> normalize_deployment_mode()
  end

  @spec saas_mode?() :: boolean()
  def saas_mode?, do: deployment_mode() == :saas

  @spec self_hosted_mode?() :: boolean()
  def self_hosted_mode?, do: deployment_mode() == :self_hosted

  @spec projects_enabled?() :: boolean()
  def projects_enabled? do
    Application.get_env(:trifle, :projects_enabled, true)
  end

  @spec sqlite_upload_max_bytes() :: pos_integer()
  def sqlite_upload_max_bytes do
    case Application.get_env(:trifle, :sqlite_upload_max_bytes, @default_sqlite_upload_max_bytes) do
      value when is_integer(value) and value > 0 -> value
      _ -> @default_sqlite_upload_max_bytes
    end
  end

  @spec sqlite_upload_root() :: String.t()
  def sqlite_upload_root do
    case Application.get_env(:trifle, :sqlite_upload_root, default_sqlite_upload_root()) do
      value when is_binary(value) and value != "" -> value
      _ -> default_sqlite_upload_root()
    end
  end

  @spec sqlite_storage_backend() :: :local | :s3
  def sqlite_storage_backend do
    case Application.get_env(:trifle, :sqlite_storage_backend, @default_sqlite_storage_backend) do
      :s3 -> :s3
      "s3" -> :s3
      _ -> :local
    end
  end

  @spec sqlite_cache_root() :: String.t()
  def sqlite_cache_root do
    case Application.get_env(:trifle, :sqlite_cache_root, default_sqlite_cache_root()) do
      value when is_binary(value) and value != "" -> value
      _ -> default_sqlite_cache_root()
    end
  end

  @spec sqlite_object_store_config() :: map()
  def sqlite_object_store_config do
    configured =
      case Application.get_env(:trifle, :sqlite_object_store, %{}) do
        value when is_list(value) -> Enum.into(value, %{})
        value when is_map(value) -> value
        _ -> %{}
      end

    %{
      endpoint: normalize_string(fetch_config_value(configured, :endpoint, "endpoint")),
      bucket: normalize_string(fetch_config_value(configured, :bucket, "bucket")),
      region:
        normalize_string(fetch_config_value(configured, :region, "region")) ||
          "us-east-1",
      access_key_id:
        normalize_string(fetch_config_value(configured, :access_key_id, "access_key_id")),
      secret_access_key:
        normalize_string(fetch_config_value(configured, :secret_access_key, "secret_access_key")),
      force_path_style:
        normalize_bool(
          fetch_config_value(configured, :force_path_style, "force_path_style"),
          true
        ),
      prefix:
        normalize_prefix(
          normalize_string(fetch_config_value(configured, :prefix, "prefix")) || "sqlite-files"
        )
    }
  end

  @spec request_body_max_bytes() :: pos_integer()
  def request_body_max_bytes do
    configured =
      case Application.get_env(
             :trifle,
             :request_body_max_bytes,
             @default_request_body_max_bytes
           ) do
        value when is_integer(value) and value > 0 -> value
        _ -> @default_request_body_max_bytes
      end

    max(configured, sqlite_upload_max_bytes())
  end

  defp normalize_deployment_mode(:saas), do: :saas
  defp normalize_deployment_mode(:self_hosted), do: :self_hosted

  defp normalize_deployment_mode(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "saas" -> :saas
      "self_hosted" -> :self_hosted
      "self-hosted" -> :self_hosted
      "selfhosted" -> :self_hosted
      _ -> :saas
    end
  end

  defp normalize_deployment_mode(_), do: :saas

  defp fetch_config_value(map, atom_key, string_key) do
    Map.get(map, atom_key) || Map.get(map, string_key)
  end

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(_), do: nil

  defp normalize_bool(value, default)

  defp normalize_bool(value, _default) when value in [true, 1], do: true
  defp normalize_bool(value, _default) when value in [false, 0], do: false

  defp normalize_bool(value, default) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      v when v in ["1", "true", "yes", "on", "enabled"] -> true
      v when v in ["0", "false", "no", "off", "disabled"] -> false
      _ -> default
    end
  end

  defp normalize_bool(nil, default), do: default
  defp normalize_bool(_, default), do: default

  defp normalize_prefix(prefix) when is_binary(prefix) do
    prefix
    |> String.trim()
    |> String.trim("/")
  end

  defp normalize_prefix(_), do: ""

  defp default_sqlite_upload_root do
    Path.join(System.tmp_dir!(), "trifle_sqlite_uploads")
  end

  defp default_sqlite_cache_root do
    Path.join(System.tmp_dir!(), "trifle_sqlite_cache")
  end
end
