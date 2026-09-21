defmodule TrifleApi.ConnectorsController do
  use TrifleApi, :controller

  def heartbeat(conn, _params), do: retired(conn)
  def jobs(conn, _params), do: retired(conn)
  def complete_job(conn, _params), do: retired(conn)

  defp retired(conn) do
    conn
    |> put_status(:gone)
    |> json(%{
      errors: %{
        detail:
          "Private Connector was retired. Configure Tailscale in Organization > Connections."
      }
    })
  end
end
