defmodule Trifle.Billing.SubscriptionTest do
  use ExUnit.Case, async: true

  alias Trifle.Billing.Subscription

  test "requires scope_id for project subscriptions" do
    attrs = %{
      organization_id: Ecto.UUID.generate(),
      scope_type: "project",
      stripe_subscription_id: "sub_project_123"
    }

    changeset = Subscription.changeset(%Subscription{}, attrs)

    refute changeset.valid?
    assert {"can't be blank", _opts} = changeset.errors[:scope_id]
  end

  test "does not require scope_id for app subscriptions" do
    attrs = %{
      organization_id: Ecto.UUID.generate(),
      scope_type: "app",
      stripe_subscription_id: "sub_app_123"
    }

    changeset = Subscription.changeset(%Subscription{}, attrs)

    assert changeset.valid?
  end
end
