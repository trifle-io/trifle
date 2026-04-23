defmodule TrifleApp.OrganizationBillingLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations

  test "canceled app subscription can be resubscribed from the current plan card", %{conn: conn} do
    user = Trifle.AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})
    membership = Organizations.get_membership_for_user(user)

    plan =
      app_plan_fixture(%{
        name: "Pro",
        tier_key: "pro",
        interval: "month",
        amount_cents: 1900,
        seat_limit: 1
      })

    app_subscription_fixture(organization, %{
      status: "canceled",
      interval: "month",
      stripe_price_id: plan.stripe_price_id
    })

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/organization/billing")

    html =
      view
      |> render_click("show_plans")

    assert html =~ "Resubscribe"
    assert html =~ ~s(action="/organization/billing/checkout/app")
    assert html =~ ~s(name="tier" value="pro")
    assert html =~ ~s(name="interval" value="month")
    refute html =~ "Current Plan"
    assert membership.organization_id == organization.id
  end

  test "active app subscription keeps the current plan disabled in the modal", %{conn: conn} do
    user = Trifle.AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})

    plan =
      app_plan_fixture(%{
        name: "Starter",
        tier_key: "starter",
        interval: "month",
        amount_cents: 3900,
        seat_limit: 3
      })

    app_subscription_fixture(organization, %{
      status: "active",
      interval: "month",
      stripe_price_id: plan.stripe_price_id
    })

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/organization/billing")

    html =
      view
      |> render_click("show_plans")

    assert html =~ "Current Plan"
    refute html =~ "Resubscribe"
  end
end
