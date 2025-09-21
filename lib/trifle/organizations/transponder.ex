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

    belongs_to :organization, Trifle.Organizations.Organization
    belongs_to :database, Trifle.Organizations.Database

    timestamps()
  end

  def changeset(transponder, attrs) do
    transponder
    |> cast(attrs, [:database_id, :name, :key, :type, :config, :enabled, :order, :organization_id])
    |> validate_required([:database_id, :name, :key, :type, :organization_id])
    |> validate_transponder_type()
    |> validate_transponder_config()
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
end
