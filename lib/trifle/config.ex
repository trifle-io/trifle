defmodule Trifle.Config do
  @moduledoc false

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
end
