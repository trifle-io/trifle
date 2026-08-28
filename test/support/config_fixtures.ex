defmodule Trifle.ConfigFixtures do
  @moduledoc false

  def override_application_env(overrides) when is_list(overrides) do
    previous =
      Map.new(overrides, fn {key, _value} ->
        {key, Application.get_env(:trifle, key, :__missing__)}
      end)

    Enum.each(overrides, fn {key, value} ->
      Application.put_env(:trifle, key, value)
    end)

    fn ->
      Enum.each(previous, fn
        {key, :__missing__} -> Application.delete_env(:trifle, key)
        {key, value} -> Application.put_env(:trifle, key, value)
      end)
    end
  end

  def enable_saas_with_projects(overrides \\ []) do
    [deployment_mode: :saas, projects_enabled: true]
    |> Keyword.merge(overrides)
    |> override_application_env()
  end
end
