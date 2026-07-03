defmodule Trifle.Organizations.Attrs do
  @moduledoc """
  Shared attrs-normalization helpers used across the Organizations
  sub-contexts (connectors, databases, transponders, dashboards, ...).
  """

  alias Trifle.Organizations.Organization

  def assign_org_id(attrs, %Organization{} = organization) do
    assign_org_id(attrs, organization.id)
  end

  def assign_org_id(attrs, organization_id) when is_binary(organization_id) do
    attrs
    |> Map.put("organization_id", organization_id)
    |> Map.delete(:organization_id)
  end

  @doc """
  Normalizes a source type (:database / :project, atom or string) to its
  canonical lowercase string form.
  """
  def source_type_string(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> String.downcase()
  end

  def source_type_string(type) when is_binary(type) do
    type
    |> String.trim()
    |> String.downcase()
  end

  @doc """
  Converts known string keys to atoms (only existing atoms, never creating
  new ones); unknown string keys pass through unchanged.
  """
  def atomize_keys(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn {key, value}, acc ->
      cond do
        is_atom(key) ->
          Map.put(acc, key, value)

        is_binary(key) ->
          atom_key =
            try do
              String.to_existing_atom(key)
            rescue
              ArgumentError -> nil
            end

          if atom_key do
            Map.put(acc, atom_key, value)
          else
            Map.put(acc, key, value)
          end

        true ->
          Map.put(acc, key, value)
      end
    end)
  end
end
