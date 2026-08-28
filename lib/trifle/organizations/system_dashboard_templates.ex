defmodule Trifle.Organizations.SystemDashboardTemplate do
  @moduledoc false

  @enforce_keys [:key, :name, :group, :version, :payload]
  defstruct [:key, :name, :group, :version, :payload]
end

defmodule Trifle.Organizations.SystemDashboardTemplates do
  @moduledoc """
  Hardcoded dashboard layouts distributed with the application.

  Keys are persistent identifiers. Once referenced by a dashboard they must not
  be renamed or removed without a migration strategy.
  """

  alias Trifle.Organizations.DashboardTemplateRef
  alias Trifle.Organizations.SystemDashboardTemplate, as: Definition

  @templates [
    %Definition{
      key: "blank",
      name: "Blank dashboard",
      group: "System templates",
      version: 1,
      payload: %{"grid" => []}
    }
  ]

  def list do
    Enum.sort_by(@templates, &String.downcase(&1.name))
  end

  def fetch(key) when is_binary(key) do
    case Enum.find(@templates, &(&1.key == key)) do
      nil -> {:error, :template_not_found}
      template -> {:ok, template}
    end
  end

  def fetch(_key), do: {:error, :template_not_found}

  def reference(%Definition{key: key}), do: DashboardTemplateRef.encode(:system, key)
end
