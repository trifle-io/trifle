defmodule TrifleApp.CommandPaletteLayoutTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures

  test "renders the command palette trigger above workspace navigation", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    _organization = organization_fixture(%{user: user})

    {:ok, _view, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings")

    assert html =~ ~s(id="command-palette-trigger")
    assert html =~ "Search"
    assert html =~ "Mr. Baker"

    assert {trigger_position, _} = :binary.match(html, "command-palette-trigger")
    assert {workspace_position, _} = :binary.match(html, "Workspace")
    assert trigger_position < workspace_position
  end
end
