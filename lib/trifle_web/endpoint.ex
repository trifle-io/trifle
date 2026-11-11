defmodule TrifleWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :trifle

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_trifle_key",
    signing_salt: "VtYmEb7T",
    same_site: "Lax"
  ]

  # :peer_data and :x_headers let LiveViews resolve the client IP for rate limiting.
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:peer_data, :x_headers, session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # `mix phx.digest` (part of assets.deploy) writes a .gz next to every static file;
  # with gzip enabled Plug.Static serves it to clients that accept it and falls back
  # to the plain file otherwise (e.g. in dev, where no .gz exists).
  plug Plug.Static,
    at: "/",
    from: :trifle,
    gzip: true,
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
