defmodule Trifle.Billing.FounderClaim do
  use Ecto.Schema
  import Ecto.Changeset

  alias Trifle.Organizations.Organization

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "billing_founder_claims" do
    field :slot_number, :integer
    field :claimed_at, :utc_datetime

    belongs_to :organization, Organization

    timestamps()
  end

  def changeset(claim, attrs) do
    claim
    |> cast(attrs, [:organization_id, :slot_number, :claimed_at])
    |> validate_required([:organization_id, :slot_number, :claimed_at])
    |> validate_number(:slot_number, greater_than: 0)
    |> unique_constraint(:organization_id, name: :billing_founder_claims_organization_id_index)
    |> unique_constraint(:slot_number, name: :billing_founder_claims_slot_number_index)
  end
end
