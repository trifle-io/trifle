defmodule Trifle.ConfigTest do
  use ExUnit.Case, async: false

  setup do
    previous =
      if Application.get_env(:trifle, :deployment_mode, :__missing__) == :__missing__ do
        :__missing__
      else
        Application.get_env(:trifle, :deployment_mode)
      end

    on_exit(fn ->
      case previous do
        :__missing__ -> Application.delete_env(:trifle, :deployment_mode)
        value -> Application.put_env(:trifle, :deployment_mode, value)
      end
    end)

    :ok
  end

  test "normalizes string deployment mode values" do
    Application.put_env(:trifle, :deployment_mode, "SELF_HOSTED")

    assert Trifle.Config.deployment_mode() == :self_hosted
    assert Trifle.Config.self_hosted_mode?()
    refute Trifle.Config.saas_mode?()
  end

  test "accepts atom deployment mode values" do
    Application.put_env(:trifle, :deployment_mode, :saas)

    assert Trifle.Config.deployment_mode() == :saas
    assert Trifle.Config.saas_mode?()
    refute Trifle.Config.self_hosted_mode?()
  end

  test "falls back to :saas for invalid values" do
    Application.put_env(:trifle, :deployment_mode, "invalid-mode")

    assert Trifle.Config.deployment_mode() == :saas
    assert Trifle.Config.saas_mode?()
    refute Trifle.Config.self_hosted_mode?()
  end
end
