defmodule TrifleApp.OrganizationTokensLiveTest do
  use TrifleApp.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Trifle.AccountsFixtures
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations

  setup %{conn: conn} do
    owner = user_fixture()
    organization = organization_fixture(%{user: owner})
    app_entitlement_fixture(organization)

    %{conn: log_in_user(conn, owner), owner: owner, organization: organization}
  end

  defp create_token(owner, organization, manage) do
    {:ok, record, _value} =
      Organizations.create_organization_api_token(owner, %{
        organization_id: organization.id,
        name: "token-#{System.unique_integer([:positive])}",
        created_by: "web-ui",
        permissions: %{
          "wildcard" => %{"read" => true, "write" => false},
          "sources" => %{},
          "manage" => manage
        }
      })

    record
  end

  defp reload(token), do: Trifle.Repo.reload!(token)

  test "marks tokens that can manage the organization", %{
    conn: conn,
    owner: owner,
    organization: organization
  } do
    managing = create_token(owner, organization, true)
    _plain = create_token(owner, organization, false)
    assert Organizations.token_can_manage?(managing)

    {:ok, view, _html} = live(conn, ~p"/organization/tokens")

    assert view |> element("[data-role=token-manage-badge]") |> render() =~ "Manages organization"
    assert view |> render() |> String.split("Manages organization") |> length() == 2
  end

  test "editing a token can grant and remove the capability", %{
    conn: conn,
    owner: owner,
    organization: organization
  } do
    token = create_token(owner, organization, false)
    {:ok, view, _html} = live(conn, ~p"/organization/tokens")

    view
    |> element("button[phx-click=open_edit_modal][phx-value-id='#{token.id}']")
    |> render_click()

    view
    |> form("form[phx-submit=update_token_grants]", %{
      "token" => %{"wildcard_read" => "true", "manage" => "true"}
    })
    |> render_submit()

    assert Organizations.token_can_manage?(reload(token))
    assert has_element?(view, "[data-role=token-manage-badge]")

    view
    |> element("button[phx-click=open_edit_modal][phx-value-id='#{token.id}']")
    |> render_click()

    # The edit form opens with the box ticked for a managing token.
    assert has_element?(
             view,
             "form[phx-submit=update_token_grants] input[type=checkbox][name='token[manage]'][checked]"
           )

    view
    |> form("form[phx-submit=update_token_grants]", %{
      "token" => %{"wildcard_read" => "true", "manage" => "false"}
    })
    |> render_submit()

    refute Organizations.token_can_manage?(reload(token))
    # Data access is untouched.
    assert %{"wildcard" => %{"read" => true}} =
             Organizations.normalize_token_permissions(reload(token).permissions)
  end

  test "a new token has the capability only when asked for", %{
    conn: conn,
    organization: organization
  } do
    {:ok, view, _html} = live(conn, ~p"/organization/tokens")

    for {name, extra} <- [{"plain", %{}}, {"managing", %{"manage" => "true"}}] do
      view |> element("button[phx-click=open_create_modal]") |> render_click()

      view
      |> form("form[phx-submit=create_token]", %{
        "token" => Map.merge(%{"name" => name, "wildcard_read" => "true"}, extra)
      })
      |> render_submit()

      render_click(view, "close_create_modal")
    end

    tokens = Organizations.list_organization_api_tokens_for_org(organization.id)
    by_name = Map.new(tokens, &{&1.name, Organizations.token_can_manage?(&1)})

    assert by_name["plain"] == false
    assert by_name["managing"] == true
  end
end
