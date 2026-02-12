defmodule Trifle.Config do
  @moduledoc false

  @spec deployment_mode() :: :saas | :self_hosted
  def deployment_mode do
    Application.get_env(:trifle, :deployment_mode, :saas)
  end

  @spec saas_mode?() :: boolean()
  def saas_mode?, do: deployment_mode() == :saas

  @spec self_hosted_mode?() :: boolean()
  def self_hosted_mode?, do: deployment_mode() == :self_hosted

  @spec projects_enabled?() :: boolean()
  def projects_enabled? do
    Application.get_env(:trifle, :projects_enabled, true)
  end
end
