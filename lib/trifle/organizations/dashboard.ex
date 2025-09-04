defmodule Trifle.Organizations.Dashboard do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dashboards" do
    field :name, :string
    field :visibility, :boolean, default: false  # Now means Personal (false) / Everyone (true)
    field :access_token, :string  # For public URL access, nullable
    field :payload, :map, default: %{}
    field :key, :string

    belongs_to :database, Trifle.Organizations.Database
    belongs_to :user, Trifle.Accounts.User

    timestamps()
  end

  def changeset(dashboard, attrs) do
    dashboard
    |> cast(attrs, [:database_id, :user_id, :name, :visibility, :access_token, :payload, :key])
    |> validate_required([:database_id, :user_id, :name, :key])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:key, min: 1)
    |> unique_constraint(:access_token)
  end

  @doc """
  Generates a new public access token for the dashboard
  """
  def generate_public_token(dashboard) do
    token = :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
    changeset(dashboard, %{access_token: token})
  end

  @doc """
  Removes the public access token from the dashboard
  """
  def remove_public_token(dashboard) do
    changeset(dashboard, %{access_token: nil})
  end

  def visibility_display(true), do: "Everyone"
  def visibility_display(false), do: "Personal"
end