defmodule TrifleWeb.Plugs.RateLimitTest do
  # Toggles global rate-limit config.
  use TrifleApp.ConnCase, async: false

  import Trifle.AccountsFixtures

  alias Trifle.RateLimit

  setup do
    previous = Application.get_env(:trifle, RateLimit, [])

    Application.put_env(:trifle, RateLimit,
      enabled: true,
      policies: %{login: {3, 60_000}, login_account: {2, 60_000}, api_auth: {2, 60_000}}
    )

    on_exit(fn -> Application.put_env(:trifle, RateLimit, previous) end)

    # Each test gets its own client address so counters do not leak between tests.
    ip = {10, :rand.uniform(250), :rand.uniform(250), :rand.uniform(250)}
    {:ok, ip: ip}
  end

  defp from(conn, ip), do: %{conn | remote_ip: ip}

  defp login(conn, ip, email, password \\ "wrong password") do
    conn
    |> from(ip)
    |> post(~p"/users/log_in", %{"user" => %{"email" => email, "password" => password}})
  end

  test "browser login is limited per client and redirects back with a message", %{
    conn: conn,
    ip: ip
  } do
    for n <- 1..3 do
      conn = login(conn, ip, "nobody-#{n}-#{System.unique_integer([:positive])}@example.com")
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
    end

    conn = login(conn, ip, "nobody-4@example.com")

    assert redirected_to(conn) == ~p"/users/log_in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many requests"
    assert [retry_after] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry_after) > 0
  end

  test "guesses against one account are limited across clients, even with the right password",
       %{conn: conn} do
    user = user_fixture()

    for last <- 1..2 do
      conn = login(conn, {10, 99, 99, last}, user.email)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
    end

    conn = login(conn, {10, 99, 99, 3}, user.email, valid_user_password())

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many requests"
    refute get_session(conn, :user_token)
  end

  test "API credential endpoints answer 429 with JSON", %{conn: conn, ip: ip} do
    request = fn ->
      conn
      |> from(ip)
      |> put_req_header("accept", "application/json")
      |> post(~p"/api/v1/bootstrap/login", %{
        "email" => "nobody-#{System.unique_integer([:positive])}@example.com",
        "password" => "wrong password"
      })
    end

    for _ <- 1..2, do: assert(request.().status == 401)

    conn = request.()

    assert %{"errors" => %{"detail" => detail}} = json_response(conn, 429)
    assert detail =~ "Too many requests"
    assert [_] = get_resp_header(conn, "retry-after")
  end

  test "other clients are unaffected", %{conn: conn, ip: ip} do
    for _ <- 1..4, do: login(conn, ip, "nobody@example.com")

    conn = login(conn, {10, 250, 250, 250}, "someone-else@example.com")
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
  end
end
