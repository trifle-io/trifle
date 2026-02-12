defmodule Trifle.Billing.Entitlement do
  use Ecto.Schema
  import Ecto.Changeset

  alias Trifle.Organizations.Organization

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "billing_entitlements" do
    field :app_tier, :string
    field :seat_limit, :integer
    field :projects_enabled, :boolean, default: false
    field :billing_locked, :boolean, default: false
    field :lock_reason, :string
    field :founder_offer_locked, :boolean, default: false
    field :effective_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :organization, Organization

    timestamps()
  end

  def changeset(entitlement, attrs) do
    entitlement
    |> cast(attrs, [
      :organization_id,
      :app_tier,
      :seat_limit,
      :projects_enabled,
      :billing_locked,
      :lock_reason,
      :founder_offer_locked,
      :effective_at,
      :metadata
    ])
    |> validate_required([:organization_id])
    |> unique_constraint(:organization_id, name: :billing_entitlements_organization_id_index)
  end
end
