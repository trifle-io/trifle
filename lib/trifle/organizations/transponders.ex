defmodule Trifle.Organizations.Transponders do
  @moduledoc """
  Transponders: per-source (database/project) data transformers, including
  CRUD, source binding, and display ordering.
  """

  import Ecto.Query, warn: false

  alias Trifle.Organizations.Attrs
  alias Trifle.Organizations.Database
  alias Trifle.Organizations.Organization
  alias Trifle.Organizations.Project
  alias Trifle.Organizations.Transponder
  alias Trifle.Repo

  @doc """
  Returns the list of transponders for a database.
  """
  def list_transponders_for_database(%Database{} = database) do
    list_transponders_for_source(:database, database.id, database.organization_id)
  end

  @doc """
  Returns the list of transponders for a project.
  """
  def list_transponders_for_project(%Project{} = project) do
    list_transponders_for_source(:project, project.id, nil)
  end

  @doc """
  Gets a single transponder.
  """
  def get_transponder_for_org!(%Organization{} = organization, id) when is_binary(id) do
    Repo.get_by!(Transponder, id: id, organization_id: organization.id)
  end

  def get_transponder_for_org!(organization_id, id)
      when is_binary(organization_id) and is_binary(id) do
    Repo.get_by!(Transponder, id: id, organization_id: organization_id)
  end

  def get_transponder!(id), do: Repo.get!(Transponder, id)

  def get_transponder_for_source!(%Database{} = database, id) when is_binary(id) do
    Repo.get_by!(Transponder,
      id: id,
      source_type: Attrs.source_type_string(:database),
      source_id: database.id,
      organization_id: database.organization_id
    )
  end

  def get_transponder_for_source!(%Project{} = project, id) when is_binary(id) do
    Repo.get_by!(Transponder,
      id: id,
      source_type: Attrs.source_type_string(:project),
      source_id: project.id
    )
  end

  @doc """
  Creates a transponder bound to a database.
  """
  def create_transponder_for_database(%Database{} = database, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put("database_id", database.id)
      |> Map.delete(:database_id)
      |> Attrs.assign_org_id(database.organization_id)
      |> assign_source(:database, database.id)
      |> Attrs.atomize_keys()

    create_transponder(attrs)
  end

  @doc """
  Creates a transponder bound to a project.
  """
  def create_transponder_for_project(%Project{} = project, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.delete(:database_id)
      |> Map.delete("database_id")
      |> assign_source(:project, project.id)
      |> Attrs.atomize_keys()

    create_transponder(attrs)
  end

  @doc """
  Creates a transponder.
  """
  def create_transponder(attrs \\ %{}) do
    attrs =
      attrs
      |> ensure_transponder_org()
      |> ensure_transponder_source()
      |> Attrs.atomize_keys()

    %Transponder{}
    |> Transponder.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a transponder.
  """
  def update_transponder(%Transponder{} = transponder, attrs) do
    attrs = ensure_transponder_source(attrs)

    transponder
    |> Transponder.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a transponder.
  """
  def delete_transponder(%Transponder{} = transponder) do
    Repo.delete(transponder)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking transponder changes.
  """
  def change_transponder(%Transponder{} = transponder, attrs \\ %{}) do
    attrs = ensure_transponder_source(attrs)

    Transponder.changeset(transponder, attrs)
  end

  @doc """
  Updates the order of transponders for a database or project.
  """
  def update_transponder_order(%Database{} = database, transponder_ids) do
    update_transponder_order_for_source(:database, database.id, transponder_ids)
  end

  def update_transponder_order(%Project{} = project, transponder_ids) do
    update_transponder_order_for_source(:project, project.id, transponder_ids)
  end

  @doc """
  Sets the next available order for a new transponder.
  """
  def get_next_transponder_order(%Database{} = database) do
    get_next_transponder_order_for_source(:database, database.id)
  end

  def get_next_transponder_order(%Project{} = project) do
    get_next_transponder_order_for_source(:project, project.id)
  end

  @doc """
  Query for all transponders bound to a source; used by source deletion to
  cascade-delete transponders.
  """
  def for_source_query(type, source_id) do
    type_string = Attrs.source_type_string(type)

    from(t in Transponder,
      where: t.source_type == ^type_string and t.source_id == ^source_id
    )
  end

  defp list_transponders_for_source(type, source_id, organization_id) do
    type_string = Attrs.source_type_string(type)

    base_query =
      from t in Transponder,
        where: t.source_type == ^type_string and t.source_id == ^source_id,
        order_by: [asc: t.order, asc: t.key]

    query =
      case organization_id do
        nil -> base_query
        org_id -> from t in base_query, where: t.organization_id == ^org_id
      end

    Repo.all(query)
  end

  defp update_transponder_order_for_source(type, source_id, transponder_ids) do
    type_string = Attrs.source_type_string(type)

    Repo.transaction(fn ->
      transponder_ids
      |> Enum.with_index()
      |> Enum.each(fn {transponder_id, index} ->
        from(t in Transponder,
          where:
            t.id == ^transponder_id and t.source_type == ^type_string and
              t.source_id == ^source_id
        )
        |> Repo.update_all(set: [order: index])
      end)
    end)
  end

  defp get_next_transponder_order_for_source(type, source_id) do
    type_string = Attrs.source_type_string(type)

    query =
      from(t in Transponder,
        where: t.source_type == ^type_string and t.source_id == ^source_id,
        select: max(t.order)
      )

    case Repo.one(query) do
      nil -> 0
      max_order -> max_order + 1
    end
  end

  defp assign_source(attrs, type, source_id) do
    attrs
    |> Map.put("source_type", Attrs.source_type_string(type))
    |> Map.put("source_id", source_id)
    |> Map.delete(:source_type)
    |> Map.delete(:source_id)
  end

  defp ensure_transponder_org(attrs) do
    case Map.get(attrs, :organization_id) || Map.get(attrs, "organization_id") do
      nil ->
        case Map.get(attrs, :database_id) || Map.get(attrs, "database_id") do
          nil ->
            attrs

          database_id ->
            case Repo.get(Database, database_id) do
              nil -> attrs
              %Database{} = database -> Attrs.assign_org_id(attrs, database.organization_id)
            end
        end

      _ ->
        attrs
    end
  end

  defp ensure_transponder_source(nil), do: %{}

  defp ensure_transponder_source(attrs) when is_map(attrs) do
    source_type = Map.get(attrs, :source_type) || Map.get(attrs, "source_type")
    source_id = Map.get(attrs, :source_id) || Map.get(attrs, "source_id")
    database_id = Map.get(attrs, :database_id) || Map.get(attrs, "database_id")

    cond do
      source_type && source_id ->
        attrs
        |> Map.put("source_type", normalize_source_type(source_type))
        |> Map.delete(:source_type)
        |> Map.put("source_id", source_id)
        |> Map.delete(:source_id)

      database_id ->
        attrs
        |> Map.put("source_type", Attrs.source_type_string(:database))
        |> Map.put("source_id", database_id)

      true ->
        attrs
    end
  end

  defp ensure_transponder_source(attrs), do: attrs

  defp normalize_source_type(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_source_type()
  end

  defp normalize_source_type(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_source_type(_), do: nil
end
