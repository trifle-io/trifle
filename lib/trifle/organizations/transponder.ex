defmodule Trifle.Organizations.Transponder do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "transponders" do
    field :name, :string
    field :key, :string
    field :config, :map, default: %{}
    field :enabled, :boolean, default: true
    field :order, :integer, default: 0
    field :source_type, :string
    field :source_id, :binary_id

    belongs_to :organization, Trifle.Organizations.Organization
    belongs_to :database, Trifle.Organizations.Database

    timestamps()
  end

  def changeset(transponder, attrs) do
    attrs = attrs |> ensure_source_fields()

    transponder
    |> cast(attrs, [
      :database_id,
      :name,
      :key,
      :config,
      :enabled,
      :order,
      :organization_id,
      :source_type,
      :source_id
    ])
    |> validate_required([:name, :key, :source_type, :source_id])
    |> validate_source_type()
    |> validate_transponder_config()
    |> ensure_database_source_consistency()
    |> maybe_validate_organization_present()
  end

  defp validate_source_type(changeset) do
    validate_change(changeset, :source_type, fn :source_type, value ->
      case value do
        "database" -> []
        "project" -> []
        _ -> [source_type: "is invalid"]
      end
    end)
  end

  defp validate_transponder_config(changeset) do
    config = get_field(changeset, :config) || %{}
    paths = Map.get(config, "paths") || Map.get(config, :paths)
    expression = Map.get(config, "expression") || Map.get(config, :expression)
    response = Map.get(config, "response") || Map.get(config, :response)

    case Trifle.Stats.Transponder.Expression.validate(paths, expression, response) do
      :ok -> changeset
      {:error, %{message: message}} -> add_error(changeset, :config, message)
      {:error, other} -> add_error(changeset, :config, inspect(other))
    end
  end

  defp ensure_source_fields(attrs) do
    source_type = Map.get(attrs, :source_type) || Map.get(attrs, "source_type")
    source_id = Map.get(attrs, :source_id) || Map.get(attrs, "source_id")
    database_id = Map.get(attrs, :database_id) || Map.get(attrs, "database_id")

    cond do
      source_type && source_id ->
        attrs

      database_id ->
        attrs
        |> Map.put("source_type", "database")
        |> Map.put("source_id", database_id)

      true ->
        attrs
    end
  end

  defp ensure_database_source_consistency(changeset) do
    database_id = get_field(changeset, :database_id)
    source_type = get_field(changeset, :source_type)
    source_id = get_field(changeset, :source_id)

    cond do
      is_nil(database_id) ->
        changeset

      source_type != "database" ->
        add_error(changeset, :source_type, "must be database when database_id is present")

      source_id != database_id ->
        add_error(changeset, :database_id, "must match source reference")

      true ->
        changeset
    end
  end

  defp maybe_validate_organization_present(changeset) do
    case get_field(changeset, :source_type) do
      "database" -> validate_required(changeset, [:organization_id])
      _ -> changeset
    end
  end
end
