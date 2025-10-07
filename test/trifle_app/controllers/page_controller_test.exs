defmodule TrifleApp.PageControllerTest do
  use TrifleApp.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Simple predictive"
  end
end
