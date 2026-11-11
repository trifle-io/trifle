defmodule TrifleWeb.RequestHardeningTest do
  # Changes global request-size and HTTPS settings.
  use TrifleApp.ConnCase, async: false

  describe "request body limits" do
    setup do
      previous = Application.get_env(:trifle, :request_body_max_bytes)
      Application.put_env(:trifle, :request_body_max_bytes, 2_000)
      on_exit(fn -> Application.put_env(:trifle, :request_body_max_bytes, previous) end)
      :ok
    end

    defp json_post(conn, path, bytes) do
      body =
        Jason.encode!(%{"email" => "a@example.com", "padding" => String.duplicate("x", bytes)})

      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> post(path, body)
    end

    test "ordinary routes reject bodies over the configured limit", %{conn: conn} do
      assert_raise Plug.Parsers.RequestTooLargeError, fn ->
        json_post(conn, "/api/v1/bootstrap/login", 5_000)
      end

      assert_raise Plug.Parsers.RequestTooLargeError, fn ->
        json_post(conn, "/webhooks/stripe", 5_000)
      end
    end

    test "small bodies still pass", %{conn: conn} do
      assert json_post(conn, "/api/v1/bootstrap/login", 100).status in [400, 401]
    end

    test "only upload routes accept upload-sized bodies", %{conn: conn} do
      # Unauthenticated, so it is refused, but by auth and not by the size limit.
      assert json_post(conn, "/api/v1/bootstrap/databases", 5_000).status == 401

      assert TrifleWeb.DynamicParsers.upload_route?(%Plug.Conn{
               path_info: ["api", "v1", "bootstrap", "databases", "abc", "setup"]
             })

      refute TrifleWeb.DynamicParsers.upload_route?(%Plug.Conn{path_info: ["users", "log_in"]})

      assert Trifle.Config.upload_request_body_max_bytes() >
               Trifle.Config.sqlite_upload_max_bytes()
    end
  end

  describe "HTTPS enforcement" do
    setup do
      on_exit(fn -> Application.put_env(:trifle, :force_ssl, false) end)
      :ok
    end

    test "is off unless configured", %{conn: conn} do
      conn = get(conn, "/users/log_in")
      assert conn.status == 200
      assert get_resp_header(conn, "strict-transport-security") == []
    end

    test "redirects plain HTTP to HTTPS when enabled", %{conn: conn} do
      Application.put_env(:trifle, :force_ssl, true)

      conn = conn |> Map.put(:host, "app.example.com") |> get("/users/log_in")

      assert conn.status == 301
      assert [location] = get_resp_header(conn, "location")
      assert String.starts_with?(location, "https://app.example.com/")
    end

    test "trusts the proxy's forwarded scheme and sends HSTS", %{conn: conn} do
      Application.put_env(:trifle, :force_ssl, true)

      conn =
        conn
        |> Map.put(:host, "app.example.com")
        |> put_req_header("x-forwarded-proto", "https")
        |> get("/users/log_in")

      assert conn.status == 200
      assert conn.scheme == :https
      assert [hsts] = get_resp_header(conn, "strict-transport-security")
      assert hsts =~ "max-age=31536000"
    end

    test "health checks are exempt", %{conn: conn} do
      Application.put_env(:trifle, :force_ssl, true)

      conn = conn |> Map.put(:host, "app.example.com") |> get("/api/v1/health")
      assert conn.status == 200
    end
  end
end
