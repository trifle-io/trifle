defmodule Trifle.Billing.PlanTest do
  use ExUnit.Case, async: true

  alias Trifle.Billing.Plan

  test "changeset handles nil strings without crashing" do
    attrs = %{
      organization_id: Ecto.UUID.generate(),
      name: nil,
      scope_type: "app",
      tier_key: "pro",
      interval: "month",
      stripe_price_id: nil
    }

    changeset = Plan.changeset(%Plan{}, attrs)

    refute changeset.valid?
    assert {"can't be blank", _opts} = changeset.errors[:name]
    assert {"can't be blank", _opts} = changeset.errors[:stripe_price_id]
  end
end
