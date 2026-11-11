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
    # The link token is a bearer credential: only its hash is stored. `token`
    # is present on the struct right after it is generated (create or refresh),
    # which is when the email is sent, and is never read back from the database.
    field :token, :string, virtual: true, redact: true
    field :token_hash, :binary, redact: true
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
    |> unique_constraint(:token_hash)
  end

  @doc """
  Issues a fresh link: new token, new expiry, back to pending. The previous
  link stops working.
  """
  def refresh_changeset(invitation) do
    invitation
    |> change(status: "pending", expires_at: default_expiration())
    |> put_new_token()
    |> unique_constraint(:token_hash)
  end

  def hash_token(token) when is_binary(token), do: :crypto.hash(:sha256, token)

  defp ensure_token(changeset) do
    if get_field(changeset, :token_hash), do: changeset, else: put_new_token(changeset)
  end

  defp put_new_token(changeset) do
    token = generate_token()

    changeset
    |> put_change(:token, token)
    |> put_change(:token_hash, hash_token(token))
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
