defmodule Trifle.Organizations.SourceAnnotation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Trifle.Accounts.User
  alias Trifle.Organizations.Organization

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "source_annotations" do
    field :source_type, :string
    field :source_id, Ecto.UUID
    field :at, :utc_datetime_usec
    field :source_granularity, :string
    field :body, :string

    belongs_to :organization, Organization
    belongs_to :created_by_user, User
    belongs_to :updated_by_user, User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(annotation, attrs) do
    annotation
    |> cast(attrs, [
      :organization_id,
      :source_type,
      :source_id,
      :at,
      :source_granularity,
      :body,
      :created_by_user_id,
      :updated_by_user_id
    ])
    |> update_change(:body, &trim_body/1)
    |> validate_required([
      :organization_id,
      :source_type,
      :source_id,
      :at,
      :source_granularity,
      :body,
      :created_by_user_id,
      :updated_by_user_id
    ])
    |> validate_inclusion(:source_type, ["database", "project"])
    |> validate_length(:body, min: 1, max: 2000)
  end

  def update_changeset(annotation, attrs) do
    annotation
    |> cast(attrs, [:body, :updated_by_user_id])
    |> update_change(:body, &trim_body/1)
    |> validate_required([:body, :updated_by_user_id])
    |> validate_length(:body, min: 1, max: 2000)
  end

  defp trim_body(value) when is_binary(value), do: String.trim(value)
  defp trim_body(value), do: value
end
