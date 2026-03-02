defmodule Trifle.Accounts.UserApiToken do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @hash_algorithm :sha256
  @token_size 32
  @token_prefix "trf_uat_"

  schema "user_api_tokens" do
    field :name, :string
    field :token_hash, :binary
    field :created_by, :string
    field :created_from, :string
    field :last_used_at, :utc_datetime
    field :last_used_from, :string
    field :expires_at, :utc_datetime

    belongs_to :user, Trifle.Accounts.User

    timestamps()
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [
      :name,
      :token_hash,
      :created_by,
      :created_from,
      :last_used_at,
      :last_used_from,
      :expires_at,
      :user_id
    ])
    |> validate_required([:name, :token_hash, :user_id])
    |> validate_length(:name, min: 1, max: 160)
    |> validate_length(:created_by, min: 1, max: 160)
    |> validate_length(:created_from, min: 1, max: 255)
    |> validate_length(:last_used_from, min: 1, max: 255)
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

  def valid_query(token) when is_binary(token) do
    token_hash = hash_token(token)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from t in __MODULE__,
      where: t.token_hash == ^token_hash and (is_nil(t.expires_at) or t.expires_at > ^now)
  end
end
