defmodule Trifle.Config do
  @moduledoc false

  @default_sqlite_upload_max_bytes 100 * 1024 * 1024
  @default_request_body_max_bytes 8_000_000

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

  defp default_sqlite_upload_root do
    Path.join(System.tmp_dir!(), "trifle_sqlite_uploads")
  end
end
