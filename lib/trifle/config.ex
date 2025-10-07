defmodule Trifle.Config do
  @moduledoc false

  @spec projects_enabled?() :: boolean()
  def projects_enabled? do
    Application.get_env(:trifle, :projects_enabled, true)
  end
end
