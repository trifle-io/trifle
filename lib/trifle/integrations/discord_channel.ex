defmodule Trifle.Integrations.DiscordChannel do
  use Ecto.Schema
  import Ecto.Changeset

  alias Trifle.Integrations.DiscordInstallation

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @required_fields ~w(discord_installation_id channel_id name channel_type)a
  @optional_fields ~w(is_thread enabled metadata)a

  schema "discord_channels" do
    field :channel_id, :string
    field :name, :string
    field :channel_type, :string
    field :is_thread, :boolean, default: false
    field :enabled, :boolean, default: false
    field :metadata, :map, default: %{}

    belongs_to :installation, DiscordInstallation, foreign_key: :discord_installation_id

    timestamps()
  end

  def changeset(%__MODULE__{} = channel, attrs) do
    channel
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:channel_id, max: 64)
    |> validate_length(:name, max: 255)
    |> validate_length(:channel_type, max: 64)
    |> ensure_metadata_map()
  end

  def enable_changeset(%__MODULE__{} = channel, attrs) do
    channel
    |> cast(attrs, [:enabled])
    |> validate_inclusion(:enabled, [true, false])
  end

  defp ensure_metadata_map(changeset) do
    case get_change(changeset, :metadata) do
      nil ->
        changeset

      value when is_map(value) ->
        changeset

      value when is_list(value) ->
        put_change(changeset, :metadata, Map.new(value))

      _ ->
        add_error(changeset, :metadata, "must be a map")
    end
  end
end
