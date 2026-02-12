defmodule Trifle.Billing.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  alias Trifle.Organizations.Organization

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @scope_types ["app", "project"]
  @intervals ["day", "week", "month", "year"]

  schema "billing_subscriptions" do
    field :scope_type, :string
    field :scope_id, :binary_id
    field :stripe_subscription_id, :string
    field :stripe_customer_id, :string
    field :stripe_price_id, :string
    field :status, :string
    field :interval, :string
    field :current_period_start, :utc_datetime
    field :current_period_end, :utc_datetime
    field :cancel_at_period_end, :boolean, default: false
    field :grace_until, :utc_datetime
    field :founder_price, :boolean, default: false
    field :metadata, :map, default: %{}

    belongs_to :organization, Organization

    timestamps()
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :organization_id,
      :scope_type,
      :scope_id,
      :stripe_subscription_id,
      :stripe_customer_id,
      :stripe_price_id,
      :status,
      :interval,
      :current_period_start,
      :current_period_end,
      :cancel_at_period_end,
      :grace_until,
      :founder_price,
      :metadata
    ])
    |> validate_required([:organization_id, :scope_type, :stripe_subscription_id])
    |> validate_inclusion(:scope_type, @scope_types)
    |> validate_scope_id_for_project()
    |> validate_interval()
    |> unique_constraint(:stripe_subscription_id,
      name: :billing_subscriptions_stripe_subscription_id_index
    )
    |> unique_constraint(:organization_id, name: :billing_subscriptions_org_app_unique)
    |> unique_constraint(:scope_id, name: :billing_subscriptions_org_project_unique)
  end

  def active?(%__MODULE__{status: status}) when status in ["active", "trialing"], do: true
  def active?(_), do: false

  def in_grace?(%__MODULE__{grace_until: %DateTime{} = grace_until}) do
    DateTime.compare(grace_until, DateTime.utc_now()) in [:gt, :eq]
  end

  def in_grace?(_), do: false

  def locked_for_delinquency?(%__MODULE__{} = subscription) do
    subscription.status in ["past_due", "unpaid"] and not in_grace?(subscription)
  end

  defp validate_interval(changeset) do
    interval = get_change(changeset, :interval) || get_field(changeset, :interval)

    cond do
      is_nil(interval) ->
        changeset

      interval == "" ->
        changeset

      interval in @intervals ->
        changeset

      true ->
        add_error(changeset, :interval, "is invalid")
    end
  end

  defp validate_scope_id_for_project(changeset) do
    case get_field(changeset, :scope_type) do
      "project" -> validate_required(changeset, [:scope_id])
      _ -> changeset
    end
  end
end
