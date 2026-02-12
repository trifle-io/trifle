defmodule Trifle.Billing.Plan do
  use Ecto.Schema
  import Ecto.Changeset

  alias Trifle.Organizations.Organization

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @scope_types ["app", "project"]
  @intervals ["day", "week", "month", "year"]
  @currencies ["usd", "eur", "gbp"]

  schema "billing_plans" do
    field :name, :string
    field :scope_type, :string
    field :tier_key, :string
    field :interval, :string
    field :stripe_price_id, :string
    field :currency, :string, default: "usd"
    field :amount_cents, :integer
    field :seat_limit, :integer
    field :hard_limit, :integer
    field :retention_add_on, :boolean, default: false
    field :founder_offer, :boolean, default: false
    field :active, :boolean, default: true
    field :metadata, :map, default: %{}

    belongs_to :organization, Organization

    timestamps()
  end

  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :organization_id,
      :name,
      :scope_type,
      :tier_key,
      :interval,
      :stripe_price_id,
      :currency,
      :amount_cents,
      :seat_limit,
      :hard_limit,
      :retention_add_on,
      :founder_offer,
      :active,
      :metadata
    ])
    |> validate_required([:name, :scope_type, :tier_key, :interval, :stripe_price_id])
    |> update_change(:name, &String.trim/1)
    |> update_change(:scope_type, &normalize_string/1)
    |> update_change(:tier_key, &normalize_string/1)
    |> update_change(:interval, &normalize_string/1)
    |> update_change(:stripe_price_id, &String.trim/1)
    |> update_change(:currency, &normalize_string/1)
    |> validate_inclusion(:scope_type, @scope_types)
    |> validate_inclusion(:interval, @intervals)
    |> validate_inclusion(:currency, @currencies)
    |> validate_number(:amount_cents, greater_than_or_equal_to: 0)
    |> validate_number(:seat_limit, greater_than: 0)
    |> validate_number(:hard_limit, greater_than: 0)
    |> validate_founder_offer()
    |> validate_retention_add_on()
    |> unique_constraint(:stripe_price_id, name: :billing_plans_stripe_price_id_unique)
    |> unique_constraint(:active, name: :billing_plans_active_global_unique)
    |> unique_constraint(:active, name: :billing_plans_active_org_unique)
  end

  defp validate_retention_add_on(changeset) do
    retention_add_on? = get_field(changeset, :retention_add_on)
    scope_type = get_field(changeset, :scope_type)

    if retention_add_on? && scope_type != "project" do
      add_error(changeset, :retention_add_on, "is allowed only for project plans")
    else
      changeset
    end
  end

  defp validate_founder_offer(changeset) do
    founder_offer? = get_field(changeset, :founder_offer)
    scope_type = get_field(changeset, :scope_type)
    tier_key = get_field(changeset, :tier_key)
    interval = get_field(changeset, :interval)

    if founder_offer? && !(scope_type == "app" && tier_key == "pro" && interval == "month") do
      add_error(changeset, :founder_offer, "is allowed only for app pro monthly plans")
    else
      changeset
    end
  end

  defp normalize_string(value) when is_binary(value),
    do: value |> String.trim() |> String.downcase()

  defp normalize_string(value), do: value
end
