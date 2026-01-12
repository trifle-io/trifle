defmodule Trifle.Organizations.DatabaseToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "database_tokens" do
    field :name, :string
    field :read, :boolean, default: true
    field :token, :string
    belongs_to :database, Trifle.Organizations.Database

    timestamps()
  end

  @doc false
  def changeset(database_token, attrs) do
    database = Map.get(attrs, "database") || Map.get(attrs, :database)

    attrs =
      attrs
      |> Map.delete("database")
      |> Map.delete(:database)

    database_token
    |> cast(attrs, [:name])
    |> maybe_put_database(database)
    |> put_change(:read, true)
    |> put_change(:token, database_token.token || build_token(database))
    |> validate_required([:database, :name, :token, :read])
    |> unique_constraint(:token)
  end

  defp build_token(nil), do: nil

  defp build_token(database) do
    payload = %{database_id: database.id, nonce: nonce()}

    Phoenix.Token.sign(TrifleWeb.Endpoint, "database auth", payload, max_age: 86400 * 365)
  end

  defp nonce do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  defp maybe_put_database(changeset, nil), do: changeset
  defp maybe_put_database(changeset, database), do: put_assoc(changeset, :database, database)
end
