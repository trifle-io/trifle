defmodule Trifle.Organizations.OrganizationApiToken do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @hash_algorithm :sha256
  @token_size 32
  @token_prefix "trf_oat_"

  schema "organization_api_tokens" do
    field :name, :string
    field :token_hash, :binary
    field :token_last5, :string
    field :permissions, :map, default: %{}
    field :created_by, :string
    field :created_from, :string
    field :last_used_at, :utc_datetime
    field :last_used_from, :string
    field :expires_at, :utc_datetime

    belongs_to :organization, Trifle.Organizations.Organization
    belongs_to :user, Trifle.Accounts.User

    timestamps()
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [
      :name,
      :token_hash,
      :token_last5,
      :permissions,
      :created_by,
      :created_from,
      :last_used_at,
      :last_used_from,
      :expires_at,
      :organization_id,
      :user_id
    ])
    |> validate_required([:name, :token_hash, :organization_id, :user_id])
    |> validate_length(:name, min: 1, max: 160)
    |> validate_length(:token_last5, is: 5)
    |> validate_length(:created_by, min: 1, max: 160)
    |> validate_length(:created_from, min: 1, max: 255)
    |> validate_length(:last_used_from, min: 1, max: 255)
    |> validate_permissions()
    |> assoc_constraint(:organization)
    |> assoc_constraint(:user)
    |> unique_constraint(:token_hash)
  end

  def build_token do
    random =
      @token_size
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    @token_prefix <> random
  end

  def hash_token(token) when is_binary(token) do
    :crypto.hash(@hash_algorithm, token)
  end

  def token_last5(token) when is_binary(token) do
    token
    |> String.trim()
    |> String.slice(-5, 5)
  end

  def token_last5(_), do: nil

  def valid_query(token) when is_binary(token) do
    token_hash = hash_token(token)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from t in __MODULE__,
      where: t.token_hash == ^token_hash and (is_nil(t.expires_at) or t.expires_at > ^now)
  end

  defp validate_permissions(changeset) do
    case get_field(changeset, :permissions) do
      nil -> put_change(changeset, :permissions, %{})
      value when is_map(value) -> changeset
      _ -> add_error(changeset, :permissions, "must be an object")
    end
  end
end
