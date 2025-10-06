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
    |> validate_required([:name, :key, :type, :source_type, :source_id])
    |> validate_source_type()
    |> validate_transponder_type()
    |> validate_transponder_config()
    |> ensure_database_source_consistency()
    |> maybe_validate_organization_present()
  end

  def available_types do
    [
      "Trifle.Stats.Transponder.Add",
      "Trifle.Stats.Transponder.Subtract",
      "Trifle.Stats.Transponder.Multiply",
      "Trifle.Stats.Transponder.Divide",
      "Trifle.Stats.Transponder.Sum",
      "Trifle.Stats.Transponder.Mean",
      "Trifle.Stats.Transponder.StandardDeviation",
      "Trifle.Stats.Transponder.Min",
      "Trifle.Stats.Transponder.Max",
      "Trifle.Stats.Transponder.Ratio"
    ]
  end

  def get_transponder_fields(type) do
    case type do
      "Trifle.Stats.Transponder.Add" ->
        [
          %{name: "path1", type: "string", label: "First Path", required: true},
          %{name: "path2", type: "string", label: "Second Path", required: true},
          %{name: "response_path", type: "string", label: "Response Path", required: false}
        ]

      "Trifle.Stats.Transponder.Subtract" ->
        [
          %{name: "path1", type: "string", label: "Minuend Path", required: true},
          %{name: "path2", type: "string", label: "Subtrahend Path", required: true},
          %{name: "response_path", type: "string", label: "Response Path", required: false}
        ]

      "Trifle.Stats.Transponder.Multiply" ->
        [
          %{name: "path1", type: "string", label: "First Path", required: true},
          %{name: "path2", type: "string", label: "Second Path", required: true},
          %{name: "response_path", type: "string", label: "Response Path", required: false}
        ]

      "Trifle.Stats.Transponder.Divide" ->
        [
          %{name: "path1", type: "string", label: "Dividend Path", required: true},
          %{name: "path2", type: "string", label: "Divisor Path", required: true},
          %{name: "response_path", type: "string", label: "Response Path", required: false}
        ]

      "Trifle.Stats.Transponder.Sum" ->
        [
          %{name: "path", type: "string", label: "Array Path", required: true},
          %{name: "response_path", type: "string", label: "Response Path", required: false}
        ]

      "Trifle.Stats.Transponder.Mean" ->
        [
          %{name: "path", type: "string", label: "Array Path", required: true},
          %{name: "response_path", type: "string", label: "Response Path", required: false}
        ]

      "Trifle.Stats.Transponder.StandardDeviation" ->
        [
          %{
            name: "left",
            type: "string",
            label: "Sum Path",
            required: true,
            help: "Path to the sum of values"
          },
          %{
            name: "right",
            type: "string",
            label: "Count Path",
            required: true,
            help: "Path to the count of values"
          },
          %{
            name: "square",
            type: "string",
            label: "Sum of Squares Path",
            required: true,
            help: "Path to the sum of squares"
          },
          %{
            name: "response_path",
            type: "string",
            label: "Response Path",
            required: true,
            help: "Path where standard deviation will be stored"
          }
        ]

      "Trifle.Stats.Transponder.Min" ->
        [
          %{name: "path", type: "string", label: "Array Path", required: true},
          %{name: "response_path", type: "string", label: "Response Path", required: false}
        ]

      "Trifle.Stats.Transponder.Max" ->
        [
          %{name: "path", type: "string", label: "Array Path", required: true},
          %{name: "response_path", type: "string", label: "Response Path", required: false}
        ]

      "Trifle.Stats.Transponder.Ratio" ->
        [
          %{name: "path1", type: "string", label: "Numerator Path", required: true},
          %{name: "path2", type: "string", label: "Denominator Path", required: true},
          %{name: "response_path", type: "string", label: "Response Path", required: false}
        ]

      _ ->
        []
    end
  end

  def get_type_display_name(type) do
    type
    |> String.replace("Trifle.Stats.Transponder.", "")
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

    if type do
      required_fields = get_transponder_fields(type)

      Enum.reduce(required_fields, changeset, fn field, acc ->
        if field.required and is_nil(config[field.name]) do
          add_error(acc, :config, "#{field.label} is required")
        else
          acc
        end
      end)
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
