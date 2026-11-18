defmodule TrifleWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :trifle

  # The session is stored in the cookie, encrypted and signed with keys derived
  # from SECRET_KEY_BASE, so its contents can be neither read nor changed by the
  # browser.
  #
  # There is deliberately no :max_age: without it this is a browser-session
  # cookie, which is what makes "Keep me logged in" meaningful (that uses its own
  # 60-day cookie, see TrifleApp.UserAuth). The session token inside is also
  # checked against the database and expires there after 60 days.
  @session_options [
    store: :cookie,
    key: "_trifle_key",
    signing_salt: "VtYmEb7T",
    encryption_salt: "pZ4wQe1N",
    same_site: "Lax"
  ]

  # :peer_data and :x_headers let LiveViews resolve the client IP for rate limiting.
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:peer_data, :x_headers, session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # `mix phx.digest` (part of assets.deploy) writes a .gz next to every static
  # file, and Plug.Static serves it to clients that accept gzip. That is only
  # safe where the .gz files are produced by the same build as the plain files,
  # i.e. in releases. With code reloading (dev) the watchers rewrite app.js but
  # not app.js.gz, so a leftover .gz from an old `phx.digest` run would be served
  # instead of the current file.
  plug Plug.Static,
    at: "/",
    from: :trifle,
    gzip: not code_reloading?,
    only: TrifleApp.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :trifle
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug TrifleWeb.Plugs.ForceSSL
  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug TrifleWeb.DynamicParsers

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug TrifleWeb.Router
end
