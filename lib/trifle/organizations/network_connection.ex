defmodule Trifle.Organizations.NetworkConnection do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Inspect, except: [:auth_key]}

  schema "organization_network_connections" do
    field :name, :string
    field :provider, :string, default: "tailscale"
    field :auth_key, Trifle.Encrypted.Binary, redact: true
    field :enabled, :boolean, default: true
    field :generation, :integer, default: 1
    field :status, :string, default: "pending"
    field :hostname, :string
    field :addresses, {:array, :string}, default: []
    field :last_error, :string
    field :checked_at, :utc_datetime
    belongs_to :organization, Trifle.Organizations.Organization
    timestamps()
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:name, :auth_key])
    |> update_change(:name, &String.trim/1)
    |> update_change(:auth_key, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 160)
    |> validate_format(:auth_key, ~r/\Atskey-auth-[A-Za-z0-9_-]+\z/,
      message: "must be a Tailscale auth key (tskey-auth-), not an API access token"
    )
    |> unique_constraint([:organization_id, :name])
  end
end
