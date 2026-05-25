defmodule Trifle.Organizations.OrganizationConnector do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @hash_algorithm :sha256
  @token_size 32
  @token_prefix "trf_connector_"
  @statuses ["pending", "online", "offline", "error"]

  schema "organization_connectors" do
    field :name, :string
    field :token_hash, :binary
    field :token_last5, :string
    field :status, :string, default: "pending"
    field :last_heartbeat_at, :utc_datetime
    field :last_poll_at, :utc_datetime
    field :last_seen_at, :utc_datetime
    field :version, :string
    field :commit, :string
    field :build_date, :string
    field :hostname, :string
    field :capabilities, {:array, :string}, default: []
    field :metadata, :map, default: %{}
    field :last_error, :string

    belongs_to :organization, Trifle.Organizations.Organization
    has_many :databases, Trifle.Organizations.Database
    has_many :connector_jobs, Trifle.Organizations.ConnectorJob

    timestamps()
  end

  def statuses, do: @statuses

  def changeset(connector, attrs) do
    connector
    |> cast(attrs, [
      :name,
      :token_hash,
      :token_last5,
      :status,
      :last_heartbeat_at,
      :last_poll_at,
      :last_seen_at,
      :version,
      :commit,
      :build_date,
      :hostname,
      :capabilities,
      :metadata,
      :last_error,
      :organization_id
    ])
    |> validate_required([:name, :token_hash, :organization_id])
    |> validate_length(:name, min: 1, max: 160)
    |> validate_length(:token_last5, is: 5)
    |> validate_inclusion(:status, @statuses)
    |> normalize_capabilities()
    |> normalize_metadata()
    |> assoc_constraint(:organization)
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

    from a in __MODULE__,
      where: a.token_hash == ^token_hash
  end

  defp normalize_capabilities(changeset) do
    case get_field(changeset, :capabilities) do
      nil ->
        put_change(changeset, :capabilities, [])

      values when is_list(values) ->
        values =
          values
          |> Enum.map(&to_string/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.uniq()

        put_change(changeset, :capabilities, values)

      _ ->
        add_error(changeset, :capabilities, "must be a list")
    end
  end

  defp normalize_metadata(changeset) do
    case get_field(changeset, :metadata) do
      nil -> put_change(changeset, :metadata, %{})
      value when is_map(value) -> changeset
      _ -> add_error(changeset, :metadata, "must be an object")
    end
  end
end
