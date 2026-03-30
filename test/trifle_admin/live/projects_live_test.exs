defmodule TrifleAdmin.ProjectsLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.OrganizationsFixtures

  alias Trifle.Billing.Subscription
  alias Trifle.Organizations
  alias Trifle.Repo

  setup %{conn: conn} do
    user = Trifle.AccountsFixtures.user_fixture()

    {:ok, conn: log_in_user(conn, user), user: user}
  end

  test "admin project modal disables delete when subscription is active", %{
    conn: conn,
    user: user
  } do
    project = project_fixture(%{user: user})

    Repo.insert!(
      Subscription.changeset(%Subscription{}, %{
        organization_id: project.organization_id,
        scope_type: "project",
        scope_id: project.id,
        stripe_subscription_id: "sub_#{System.unique_integer([:positive])}",
        status: "active"
      })
    )

    {:ok, lv, html} = live(conn, "/admin/projects/#{project.id}/show")

    assert html =~ "Danger zone"
    assert has_element?(lv, "button[phx-click=\"delete_project\"][disabled]")
  end

  test "admin project modal deletes project when subscription is inactive", %{
    conn: conn,
    user: user
  } do
    project = project_fixture(%{user: user})

    {:ok, transponder} =
      Organizations.create_transponder_for_project(project, transponder_attrs("Project Total"))

    subscription =
      Repo.insert!(
        Subscription.changeset(%Subscription{}, %{
          organization_id: project.organization_id,
          scope_type: "project",
          scope_id: project.id,
          stripe_subscription_id: "sub_#{System.unique_integer([:positive])}",
          status: "canceled"
        })
      )

    {:ok, lv, _html} = live(conn, "/admin/projects/#{project.id}/show")

    lv
    |> element("button[phx-click=\"delete_project\"]")
    |> render_click()

    assert_patch(lv, "/admin/projects")
    assert_raise Ecto.NoResultsError, fn -> Organizations.get_project!(project.id) end
    assert_raise Ecto.NoResultsError, fn -> Organizations.get_transponder!(transponder.id) end
    assert Repo.get(Subscription, subscription.id) == nil
  end

  defp transponder_attrs(name) do
    %{
      "name" => name,
      "key" => "metric::#{System.unique_integer([:positive])}",
      "config" => %{
        "paths" => ["foo"],
        "expression" => "a",
        "response" => "total"
      }
    }
  end
end
