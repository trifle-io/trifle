defmodule Trifle.Billing.Customer do
  use Ecto.Schema
  import Ecto.Changeset

  alias Trifle.Organizations.Organization

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "billing_customers" do
    field :stripe_customer_id, :string
    field :email, :string
    field :name, :string
    field :default_payment_method_last4, :string
    field :default_payment_method_brand, :string
    field :metadata, :map, default: %{}

    belongs_to :organization, Organization

    timestamps()
  end

  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [
      :organization_id,
      :stripe_customer_id,
      :email,
      :name,
      :default_payment_method_last4,
      :default_payment_method_brand,
      :metadata
    ])
    |> validate_required([:organization_id, :stripe_customer_id])
    |> unique_constraint(:organization_id, name: :billing_customers_organization_id_index)
    |> unique_constraint(:stripe_customer_id, name: :billing_customers_stripe_customer_id_index)
  end
end
