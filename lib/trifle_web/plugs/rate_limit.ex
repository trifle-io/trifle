defmodule TrifleWeb.Plugs.RateLimit do
  @moduledoc """
  Rate-limits a route, pipeline or controller action with a named
  `Trifle.RateLimit` policy.

      # per client IP (the default subject)
      plug TrifleWeb.Plugs.RateLimit, policy: :login

      # per submitted value, e.g. the account being logged into
      plug TrifleWeb.Plugs.RateLimit, policy: :login_account, by: {:param, ["user", "email"]}

      # per authenticated identity
      plug TrifleWeb.Plugs.RateLimit, policy: :export, by: :user
      plug TrifleWeb.Plugs.RateLimit, policy: :api_manage, by: {:assign, :current_api_token}

      # anything else
      plug TrifleWeb.Plugs.RateLimit, policy: :x, by: {MyModule, :subject_for}

  Options:

    * `:policy` (required) - a policy name from `Trifle.RateLimit`
    * `:by` - what the limit is counted against: `:ip` (default), `:user`,
      `{:param, path}`, `{:assign, key}` (structs are reduced to their `id`) or
      `{module, function}` receiving the conn. A `nil` subject is not limited.
    * `:methods` - only limit these HTTP methods, e.g. `["POST"]`. Default: all.

  A denied request gets a `retry-after` header and: for API requests a `429` with
  a JSON error; for browser requests a flash message and a redirect back to the
  page it came from.
  """

  @behaviour Plug

  import Plug.Conn

  alias Trifle.RateLimit

  @impl true
  def init(opts) do
    policy = Keyword.fetch!(opts, :policy)
    # Fail at compile/boot time on a mistyped policy name.
    _ = RateLimit.policy!(policy)

    %{
      policy: policy,
      by: Keyword.get(opts, :by, :ip),
      methods: opts |> Keyword.get(:methods) |> normalize_methods()
    }
  end

  @impl true
  def call(conn, %{policy: policy, by: by, methods: methods}) do
    if is_nil(methods) or conn.method in methods do
      case RateLimit.check(policy, subject(conn, by)) do
        :ok -> conn
        {:error, {:rate_limited, retry_after_ms}} -> deny(conn, retry_after_ms)
      end
    else
      conn
    end
  end

  defp normalize_methods(nil), do: nil
  defp normalize_methods(methods), do: Enum.map(methods, &(&1 |> to_string() |> String.upcase()))

  defp subject(conn, :ip), do: RateLimit.client_ip(conn)

  defp subject(conn, :user) do
    case conn.assigns[:current_user] || conn.assigns[:current_api_user] do
      %{id: id} -> {:user, id}
      _ -> nil
    end
  end

  defp subject(conn, {:param, path}) when is_list(path) do
    case get_in(conn.params, path) do
      value when is_binary(value) -> value
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp subject(conn, {:assign, key}) when is_atom(key) do
    case conn.assigns[key] do
      %{id: id} -> {key, id}
      nil -> nil
      other -> {key, other}
    end
  end

  defp subject(conn, {module, function}) when is_atom(module) and is_atom(function),
    do: apply(module, function, [conn])

  defp deny(conn, retry_after_ms) do
    seconds = max(div(retry_after_ms + 999, 1000), 1)
    message = "Too many requests. Try again in #{RateLimit.retry_after_text(retry_after_ms)}."

    conn = put_resp_header(conn, "retry-after", Integer.to_string(seconds))

    if browser_request?(conn) do
      # A redirect (not a bare 429) so the person lands back on the form with the
      # message; browsers do not follow a Location header on a 429.
      conn
      |> Phoenix.Controller.put_flash(:error, message)
      |> Phoenix.Controller.redirect(to: back_path(conn))
      |> halt()
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(:too_many_requests, Jason.encode!(%{errors: %{detail: message}}))
      |> halt()
    end
  end

  # The flash is only available when the browser pipeline ran.
  defp browser_request?(conn) do
    Map.has_key?(conn.private, :phoenix_flash) or Map.has_key?(conn.assigns, :flash)
  end

  # Send people back where they came from, but only to a local path.
  defp back_path(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{host: host, path: path} when is_binary(path) <- URI.parse(referer),
         true <- host == conn.host,
         true <- String.starts_with?(path, "/") and not String.starts_with?(path, "//") do
      path
    else
      _ -> if conn.method == "GET", do: "/", else: conn.request_path
    end
  end
end
