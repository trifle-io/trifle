defmodule TrifleApp.ProjectBillingLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  setup do
    on_exit(Trifle.ConfigFixtures.enable_saas_with_projects())
  end

  test "canceled project subscription can be resubscribed from the current tier card", %{
    conn: conn
  } do
    user = Trifle.AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})
    app_entitlement_fixture(organization)
    project = project_fixture(%{user: user, organization: organization})

    plan =
      project_plan_fixture(%{
        name: "100K",
        tier_key: "100k",
        hard_limit: 100_000,
        amount_cents: 1900
      })

    project_subscription_fixture(project, %{
      status: "canceled",
      stripe_price_id: plan.stripe_price_id
    })

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/projects/#{project.id}/billing")

    html =
      view
      |> render_click("show_plans")

    assert html =~ "Resubscribe"
    assert html =~ ~s(action="/organization/billing/checkout/project/#{project.id}")
    assert html =~ ~s(name="tier" value="100k")
  end
end
