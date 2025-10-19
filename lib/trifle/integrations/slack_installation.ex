defmodule Trifle.Integrations.SlackInstallation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Trifle.Accounts.User
  alias Trifle.Integrations.SlackChannel
  alias Trifle.Organizations.Organization

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @required_fields ~w(organization_id team_id team_name reference bot_access_token)a
  @optional_fields ~w(team_domain bot_user_id scope settings installed_by_user_id last_channel_sync_at)a

  schema "slack_installations" do
    field :team_id, :string
    field :team_name, :string
    field :team_domain, :string
    field :reference, :string
    field :bot_user_id, :string
    field :bot_access_token, :string
    field :scope, :string
    field :settings, :map, default: %{}
    field :last_channel_sync_at, :utc_datetime_usec

    belongs_to :organization, Organization
    belongs_to :installed_by, User, foreign_key: :installed_by_user_id

    has_many :channels, SlackChannel

    timestamps()
  end

  def changeset(%__MODULE__{} = installation, attrs) do
    installation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:team_id, max: 255)
    |> validate_length(:team_name, max: 255)
    |> validate_length(:reference, max: 64)
    |> validate_format(:reference, ~r/^[a-z0-9][a-z0-9_\-]*$/,
      message: "must use lowercase letters, digits, underscores, or hyphens"
    )
    |> ensure_settings_map()
    |> unique_constraint(:team_id,
      name: :slack_installations_organization_id_team_id_index,
      message: "workspace already connected"
    )
    |> unique_constraint(:reference,
      name: :slack_installations_organization_id_reference_index,
      message: "reference prefix already in use"
    )
  end

  defp ensure_settings_map(changeset) do
    case get_change(changeset, :settings) do
      nil ->
        changeset

      value when is_map(value) ->
        changeset

      value when is_list(value) ->
        put_change(changeset, :settings, Map.new(value))

      _ ->
        add_error(changeset, :settings, "must be a map")
    end
  end
end
