defmodule TrifleWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Content-Security-Policy for browser pages.

  The mode comes from `config :trifle, :csp_mode` (`CSP_MODE`):

    * `:report_only` (default) - the full policy is sent as
      `content-security-policy-report-only`: nothing is blocked, and browsers
      post what *would* be blocked to `/csp-report`, where it is logged. A small
      baseline that the app is known to satisfy is enforced alongside it.
    * `:enforce` - the full policy is enforced.
    * `:off` - this plug adds nothing; Phoenix's own minimal policy (`base-uri`,
      `frame-ancestors`) from `put_secure_browser_headers` remains.

  ## Why report-only is the default

  The full policy allows scripts only from the app itself, two CDNs, and inline
  `<script>` tags carrying this request's nonce (`@csp_nonce` in the root
  layouts). The app does not meet it yet. Known violations, all of which would
  break under `:enforce`:

    * Alpine.js evaluates attribute expressions with `new Function` (needs
      `'unsafe-eval'`, or Alpine's CSP build).
    * Inline event handlers (`onclick=`, `onmousedown=`, `onload=`) in the filter
      bar, widget download menus, the projects/databases lists and the download
      iframes.
    * Inline `<script>` blocks rendered inside LiveViews (download menu reset in
      the dashboard, monitor and explore pages; theme switch in the export
      layout).

  Move those into `assets/js`, watch the reports go quiet, then switch to
  `:enforce`.
  """

  @behaviour Plug

  import Plug.Conn

  @baseline "object-src 'none'; base-uri 'self'; frame-ancestors 'self'"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case mode() do
      :off ->
        conn

      mode ->
        nonce = 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
        policy = policy(conn, nonce)

        conn
        |> assign(:csp_nonce, nonce)
        |> put_headers(mode, policy)
    end
  end

  defp put_headers(conn, :enforce, policy) do
    put_resp_header(conn, "content-security-policy", policy)
  end

  defp put_headers(conn, _report_only, policy) do
    conn
    |> put_resp_header("content-security-policy", @baseline)
    |> put_resp_header("content-security-policy-report-only", policy)
  end

  @doc "The configured mode: `:report_only`, `:enforce` or `:off`."
  def mode do
    case Application.get_env(:trifle, :csp_mode, :report_only) do
      mode when mode in [:enforce, :off] -> mode
      _ -> :report_only
    end
  end

  @doc false
  def policy(conn, nonce) do
    # 'self' covers same-origin websockets in current browsers; older Safari
    # needs the explicit origin.
    socket = "wss://#{conn.host} ws://#{conn.host}"

    [
      "default-src 'self'",
      # unpkg: Alpine.js. jsdelivr: AG Grid, loaded on demand.
      "script-src 'self' 'nonce-#{nonce}' https://unpkg.com https://cdn.jsdelivr.net",
      # Charts, the grid and many templates set inline styles.
      "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdn.jsdelivr.net",
      "font-src 'self' data: https://fonts.gstatic.com https://cdn.jsdelivr.net",
      # Gravatar, chart snapshots, trace media served from object storage.
      "img-src 'self' data: blob: https:",
      "media-src 'self' blob: https:",
      "connect-src 'self' #{socket}",
      "frame-src 'self'",
      "worker-src 'self' blob:",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'",
      "frame-ancestors 'self'",
      "report-uri /csp-report"
    ]
    |> Enum.join("; ")
  end
end
