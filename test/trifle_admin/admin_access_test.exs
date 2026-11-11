defmodule TrifleAdmin.AdminAccessTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest

  alias Trifle.Accounts
  alias Trifle.AccountsFixtures

  @admin_paths [
    "/admin",
    "/admin/organizations",
    "/admin/users",
    "/admin/projects",
    "/admin/project-clusters",
    "/admin/databases",
    "/admin/dashboards",
    "/admin/monitors",
    "/admin/billing",
    "/admin/billing/plans",
    "/admin/dashboard-templates"
  ]

  describe "regular (non-admin) user" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {:ok, conn: log_in_user(conn, user), user: user}
    end

    test "is redirected away from every admin page", %{conn: conn} do
      for path <- @admin_paths do
        conn = get(conn, path)
        assert redirected_to(conn) == "/", "expected #{path} to redirect non-admins"
      end
    end

    test "cannot mount an admin LiveView over the socket", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/users")
    end

    test "stays a standard user", %{conn: conn, user: user} do
      _ = get(conn, "/admin/users")
      refute Accounts.get_user!(user.id).is_admin
    end
  end

  test "anonymous visitors are sent to the login page", %{conn: conn} do
    conn = get(conn, "/admin/users")
    assert redirected_to(conn) == "/users/log_in"
  end

  test "administrators can open the console", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {:ok, user} = Accounts.update_user_admin_status(user.id, true)

    assert {:ok, _lv, _html} = conn |> log_in_user(user) |> live("/admin/users")
  end
end
