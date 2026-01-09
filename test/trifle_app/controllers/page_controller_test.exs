defmodule TrifleApp.PageControllerTest do
  use TrifleApp.ConnCase

  test "GET /home renders marketing page", %{conn: conn} do
    conn = get(conn, ~p"/home")
    assert html_response(conn, 200) =~ "Analytics tracking"
  end
end
