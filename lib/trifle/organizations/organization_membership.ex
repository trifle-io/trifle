defmodule Trifle.Organizations.OrganizationMembership do
  use Ecto.Schema
  import Ecto.Changeset

  alias Trifle.Organizations.Organization
  alias Trifle.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(owner admin member)

  schema "organization_memberships" do
    belongs_to :organization, Organization
    belongs_to :user, User
    field :role, :string, default: "member"
    belongs_to :invited_by, User, foreign_key: :invited_by_user_id
    field :last_active_at, :utc_datetime

    timestamps()
  end

  def roles, do: @roles

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:organization_id, :user_id, :role, :invited_by_user_id, :last_active_at])
    |> validate_required([:organization_id, :user_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:organization_user, name: :organization_memberships_org_user_index)
    |> unique_constraint(:user_id, name: :organization_memberships_user_unique)
  end
end
