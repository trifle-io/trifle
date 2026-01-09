defmodule TrifleWeb.ObanDashboardRouter do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    cond do
      not Code.ensure_loaded?(Oban.Web.Router) ->
        not_found(conn)

      not Application.get_env(:trifle, :oban_web_enabled, false) ->
        not_found(conn)

      true ->
        opts = apply(Oban.Web.Router, :init, [opts])
        apply(Oban.Web.Router, :call, [conn, opts])
    end
  end

  defp not_found(conn) do
    conn
    |> send_resp(:not_found, "Not Found")
    |> halt()
  end
end
