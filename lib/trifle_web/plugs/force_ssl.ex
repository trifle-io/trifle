defmodule TrifleWeb.Plugs.ForceSSL do
  @moduledoc """
  HTTPS enforcement that can be switched on at runtime.

  Phoenix's built-in `force_ssl` endpoint option is fixed at compile time, which
  does not suit one release image deployed both behind TLS (hosted) and on plain
  HTTP (some self-hosted setups). This plug applies `Plug.SSL` when

      config :trifle, :force_ssl, true        # FORCE_SSL=true

  When enabled it:

    * trusts `x-forwarded-proto` from the proxy, so `conn.scheme` becomes
      `:https` and Plug marks the session and remember-me cookies `Secure`
    * redirects plain HTTP requests to HTTPS
    * sends HSTS so browsers stop trying HTTP

  Health checks (`/api/v1/health`) are exempt so a load balancer probing over
  HTTP keeps working. Only enable this when every client reaches the app through
  a TLS-terminating proxy you control.
  """

  @behaviour Plug

  @impl true
  def init(_opts) do
    Plug.SSL.init(
      rewrite_on: [:x_forwarded_proto],
      hsts: true,
      expires: 31_536_000,
      exclude: [hosts: ["localhost", "127.0.0.1"]]
    )
  end

  @impl true
  def call(%Plug.Conn{path_info: ["api", "v1", "health"]} = conn, _ssl_opts), do: conn

  def call(conn, ssl_opts) do
    if Application.get_env(:trifle, :force_ssl, false) do
      Plug.SSL.call(conn, ssl_opts)
    else
      conn
    end
  end
end
