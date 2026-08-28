defmodule Trifle.Organizations.DashboardTemplate do
  @moduledoc """
  A reusable, organization-scoped dashboard layout.

  Dashboards refer to these records through an encoded `user:<uuid>` reference
  stored in `dashboards.template_id`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Trifle.Accounts.User
  alias Trifle.Organizations.Organization

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dashboard_templates" do
    field :name, :string
    field :payload, :map, default: %{}
    field :lock_version, :integer, default: 1

    belongs_to :organization, Organization
    belongs_to :created_by, User

    timestamps()
  end

  def changeset(template, attrs) do
    template
    |> cast(attrs, [:organization_id, :created_by_id, :name, :payload, :lock_version])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:organization_id, :name, :payload, :lock_version])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_number(:lock_version, greater_than: 0)
  end

  def payload_changeset(template, payload) when is_map(payload) do
    template
    |> change(payload: payload)
    |> optimistic_lock(:lock_version)
  end
end
