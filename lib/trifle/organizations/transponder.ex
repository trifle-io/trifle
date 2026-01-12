defmodule Trifle.Organizations.Transponder do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "transponders" do
    field :name, :string
    field :key, :string
    field :type, :string
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
      :type,
      :config,
      :enabled,
      :order,
      :organization_id,
      :source_type,
      :source_id
    ])
    |> maybe_put_expression_type()
    |> validate_required([:name, :key, :type, :source_type, :source_id])
    |> validate_source_type()
    |> validate_transponder_type()
    |> validate_transponder_config()
    |> ensure_database_source_consistency()
    |> maybe_validate_organization_present()
  end

  @expression_type "Trifle.Stats.Transponder.Expression"

  def expression_type, do: @expression_type

  def available_types do
    [@expression_type]
  end

  defp maybe_put_expression_type(changeset) do
    case get_field(changeset, :type) do
      nil -> put_change(changeset, :type, @expression_type)
      "" -> put_change(changeset, :type, @expression_type)
      _ -> changeset
    end
  end

  defp validate_transponder_type(changeset) do
    validate_inclusion(changeset, :type, available_types())
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
    type = get_field(changeset, :type)
    config = get_field(changeset, :config) || %{}

    if type == @expression_type do
      paths = Map.get(config, "paths") || Map.get(config, :paths)
      expression = Map.get(config, "expression") || Map.get(config, :expression)
      response_path = Map.get(config, "response_path") || Map.get(config, :response_path)

      case Trifle.Stats.Transponder.Expression.validate(paths, expression, response_path) do
        :ok -> changeset
        {:error, %{message: message}} -> add_error(changeset, :config, message)
        {:error, other} -> add_error(changeset, :config, inspect(other))
      end
    else
      changeset
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
