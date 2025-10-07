defmodule TrifleApp.Plugs.RequireProjectsEnabled do
  import Plug.Conn

  @spec init(Keyword.t()) :: :html | :json
  def init(opts) do
    Keyword.get(opts, :format, :html)
  end

  @spec call(Plug.Conn.t(), :html | :json) :: Plug.Conn.t()
  def call(conn, format) do
    if Trifle.Config.projects_enabled?() do
      conn
    else
      respond(conn, format)
    end
  end

  defp respond(conn, :json) do
    body = Jason.encode!(%{error: "projects feature disabled"})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:not_found, body)
    |> halt()
  end

  defp respond(conn, _format) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(:not_found, "Not found")
    |> halt()
  end
end
