defmodule TrifleApp.Plugs.RequireProjectsEnabledTest do
  use ExUnit.Case, async: true

  import Plug.Conn, only: [get_resp_header: 2]
  import Plug.Test

  alias TrifleApp.Plugs.RequireProjectsEnabled

  setup do
    original = Application.get_env(:trifle, :projects_enabled, true)

    on_exit(fn -> Application.put_env(:trifle, :projects_enabled, original) end)

    :ok
  end

  test "allows request when projects feature enabled" do
    Application.put_env(:trifle, :projects_enabled, true)

    conn =
      :get
      |> conn("/projects")
      |> RequireProjectsEnabled.call(RequireProjectsEnabled.init([]))

    refute conn.halted
  end

  test "halts with not found html response when feature disabled" do
    Application.put_env(:trifle, :projects_enabled, false)

    conn =
      :get
      |> conn("/projects")
      |> RequireProjectsEnabled.call(RequireProjectsEnabled.init([]))

    assert conn.halted
    assert conn.status == 404
    assert conn.resp_body == "Not found"
    assert content_type(conn) |> String.starts_with?("text/html")
  end

  test "halts with json response when feature disabled for api" do
    Application.put_env(:trifle, :projects_enabled, false)

    conn =
      :post
      |> conn("/api/metrics")
      |> RequireProjectsEnabled.call(RequireProjectsEnabled.init(format: :json))

    assert conn.halted
    assert conn.status == 404
    assert content_type(conn) |> String.starts_with?("application/json")
    assert %{"error" => "projects feature disabled"} = Jason.decode!(conn.resp_body)
  end

  defp content_type(conn) do
    conn
    |> get_resp_header("content-type")
    |> List.first()
    |> Kernel.||("")
  end
end
