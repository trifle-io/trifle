defmodule TrifleApi.ConnectorsControllerTest do
  use TrifleApp.ConnCase, async: true

  test "retired connector endpoints return an actionable 410 without authentication", %{
    conn: conn
  } do
    for {method, path} <- [
          {:post, "/api/v1/connectors/heartbeat"},
          {:get, "/api/v1/connectors/jobs"},
          {:post, "/api/v1/connectors/jobs/retired-job/complete"}
        ] do
      response = Phoenix.ConnTest.dispatch(conn, @endpoint, method, path, %{})
      assert %{"errors" => %{"detail" => message}} = json_response(response, 410)
      assert message =~ "Tailscale"
    end
  end
end
