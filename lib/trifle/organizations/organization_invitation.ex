defmodule Trifle.Organizations.OrganizationInvitation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Trifle.Organizations.Organization
  alias Trifle.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(owner admin member)
  @statuses ~w(pending accepted cancelled expired)

  schema "organization_invitations" do
    belongs_to :organization, Organization
    field :email, :string
    field :role, :string, default: "member"
    field :token, :string
    field :status, :string, default: "pending"
    field :expires_at, :utc_datetime
    belongs_to :invited_by, User, foreign_key: :invited_by_user_id
    belongs_to :accepted_user, User, foreign_key: :accepted_user_id

    timestamps()
  end

  def roles, do: @roles
  def statuses, do: @statuses

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [
      :organization_id,
      :email,
      :role,
      :token,
      :status,
      :expires_at,
      :invited_by_user_id,
      :accepted_user_id
    ])
    |> validate_required([:organization_id, :email, :role])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:status, @statuses)
    |> ensure_token()
    |> ensure_expiration()
    |> unique_constraint(:token)
  end

  defp ensure_token(changeset) do
    case get_field(changeset, :token) do
      nil -> put_change(changeset, :token, generate_token())
      "" -> put_change(changeset, :token, generate_token())
      _ -> changeset
    end
  end

  defp ensure_expiration(changeset) do
    case get_field(changeset, :expires_at) do
      nil -> put_change(changeset, :expires_at, default_expiration())
      _ -> changeset
    end
  end

  def default_expiration do
    DateTime.utc_now()
    |> DateTime.add(3 * 24 * 60 * 60, :second)
    |> DateTime.truncate(:second)
  end

  def generate_token do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
