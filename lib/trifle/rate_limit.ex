defmodule Trifle.RateLimit do
  @moduledoc """
  Application-wide rate limiting, built on Hammer.

  One place defines named **policies** (how many hits per window); callers say
  which policy applies and what the limit is counted against (the *subject*: a
  client IP, an email address, a user id, or a combination).

  ## Using it

  On routes or controller actions, with the plug:

      plug TrifleWeb.Plugs.RateLimit, policy: :login
      plug TrifleWeb.Plugs.RateLimit, policy: :login_account, by: {:param, ["user", "email"]}
      plug TrifleWeb.Plugs.RateLimit, policy: :api_auth when action in [:login, :signup]

  Anywhere else (LiveView events, context functions):

      case Trifle.RateLimit.check(:email_send, email) do
        :ok -> ...
        {:error, {:rate_limited, retry_after_ms}} -> ...
      end

  ## Policies

  Defaults live in `@default_policies`. Override or add in config:

      config :trifle, Trifle.RateLimit,
        enabled: true,
        policies: %{login: {20, :timer.minutes(1)}}

  A policy is `{limit, window_ms}`: at most `limit` hits per `window_ms` for each
  subject.

  ## Scope

  Counters are kept in ETS, so limits are **per node**. With N nodes behind a load
  balancer a client can do up to N times the configured rate. That is fine for
  blunting brute force and abuse; for exact cross-node limits switch the backend to
  Redis (`hammer_backend_redis`) — only the `use Hammer` line below changes.

  ## Client IP behind a proxy

  `conn.remote_ip` is the load balancer when the app sits behind one. Set

      config :trifle, Trifle.RateLimit,
        client_ip_header: "x-forwarded-for",
        trusted_proxies: 1

  (`RATE_LIMIT_CLIENT_IP_HEADER`, `RATE_LIMIT_TRUSTED_PROXIES`) to read the address
  from that header instead: the entry `trusted_proxies` from the right is used,
  i.e. the address seen by the outermost proxy you control. Never enable this
  when clients can reach the app directly, or they could spoof the header.
  """

  use Hammer, backend: :ets

  @default_policies %{
    # Interactive credential endpoints, per client IP.
    login: {10, :timer.minutes(1)},
    # Guesses against one account, from any number of IPs.
    login_account: {10, :timer.minutes(10)},
    # Unauthenticated API credential endpoints (CLI login / signup), per client IP.
    api_auth: {10, :timer.minutes(1)},
    # Account creation, per client IP.
    signup: {10, :timer.hours(1)},
    # Transactional emails triggered by a visitor (reset, confirmation), per
    # recipient and per client IP.
    email_send: {5, :timer.hours(1)},
    # Invitation link attempts, per client IP.
    invitation: {30, :timer.minutes(10)},
    # Organization management API calls, per token.
    api_manage: {120, :timer.minutes(1)},
    # LLM chat messages, per user.
    chat_message: {30, :timer.minutes(5)},
    # Headless-browser exports, per user.
    export: {20, :timer.minutes(1)},
    # Outbound connection tests against customer databases, per user.
    connection_test: {30, :timer.minutes(1)}
  }

  @type policy :: atom()
  @type result :: :ok | {:error, {:rate_limited, retry_after_ms :: non_neg_integer()}}

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [Keyword.put_new(opts, :clean_period, :timer.minutes(1))]},
      type: :worker
    }
  end

  @doc """
  Counts one hit for `subject` under `policy` and says whether it is allowed.

  `subject` may be any term; `nil`, `""` and `{tag, nil}` subjects are not limited
  (there is nothing to count against). Unknown policies raise, so a typo cannot silently
  disable a limit.
  """
  @spec check(policy(), term()) :: result()
  def check(policy, subject) when is_atom(policy) do
    {limit, window_ms} = policy!(policy)

    cond do
      not enabled?() ->
        :ok

      subject in [nil, ""] or match?({_tag, nil}, subject) ->
        :ok

      true ->
        count_hit({policy, normalize_subject(subject)}, window_ms, limit)
    end
  end

  defp count_hit(key, window_ms, limit) do
    case hit(key, window_ms, limit) do
      {:allow, _count} -> :ok
      {:deny, retry_after_ms} -> {:error, {:rate_limited, retry_after_ms}}
    end
  rescue
    # The limiter must never take the application down with it: if its table is
    # missing (not started), let the request through.
    ArgumentError -> :ok
  end

  @doc "Checks several `{policy, subject}` pairs; stops at the first denial."
  @spec check_all([{policy(), term()}]) :: result()
  def check_all(checks) when is_list(checks) do
    Enum.reduce_while(checks, :ok, fn {policy, subject}, :ok ->
      case check(policy, subject) do
        :ok -> {:cont, :ok}
        denied -> {:halt, denied}
      end
    end)
  end

  @doc "The configured `{limit, window_ms}` for a policy."
  def policy!(policy) do
    case Map.fetch(policies(), policy) do
      {:ok, {limit, window_ms}} when is_integer(limit) and is_integer(window_ms) ->
        {limit, window_ms}

      _ ->
        raise ArgumentError, "unknown rate limit policy #{inspect(policy)}"
    end
  end

  def policies do
    Map.merge(@default_policies, Map.new(config(:policies, %{})))
  end

  def enabled?, do: config(:enabled, true) == true

  @doc "Human-readable wait, for messages: \"45 seconds\", \"3 minutes\"."
  def retry_after_text(retry_after_ms) when is_integer(retry_after_ms) do
    seconds = max(div(retry_after_ms + 999, 1000), 1)

    cond do
      seconds < 90 -> "#{seconds} second#{if seconds == 1, do: "", else: "s"}"
      true -> "#{div(seconds + 59, 60)} minutes"
    end
  end

  @doc """
  Client IP as a string, from a `Plug.Conn` or a connected LiveView socket.

  See the moduledoc for the proxy header settings. Returns `nil` when it cannot
  be determined (e.g. a LiveView's static render).
  """
  def client_ip(%Plug.Conn{} = conn) do
    forwarded_ip(Plug.Conn.get_req_header(conn, header_name() || "")) ||
      format_ip(conn.remote_ip)
  end

  def client_ip(%Phoenix.LiveView.Socket{} = socket) do
    if Phoenix.LiveView.connected?(socket) do
      headers =
        case Phoenix.LiveView.get_connect_info(socket, :x_headers) do
          list when is_list(list) -> for {name, value} <- list, name == header_name(), do: value
          _ -> []
        end

      forwarded_ip(headers) ||
        case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
          %{address: address} -> format_ip(address)
          _ -> nil
        end
    end
  end

  defp forwarded_ip(values) do
    with name when is_binary(name) <- header_name(),
         [_ | _] = values <- values do
      hops = max(config(:trusted_proxies, 1), 1)

      values
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.at(-hops)
      |> case do
        nil -> nil
        candidate -> if valid_ip?(candidate), do: candidate
      end
    else
      _ -> nil
    end
  end

  defp valid_ip?(value) do
    match?({:ok, _}, :inet.parse_address(String.to_charlist(value)))
  end

  defp header_name do
    case config(:client_ip_header, nil) do
      name when is_binary(name) and name != "" -> String.downcase(name)
      _ -> nil
    end
  end

  defp format_ip(nil), do: nil

  defp format_ip(address) when is_tuple(address) do
    address |> :inet.ntoa() |> to_string()
  rescue
    _ -> nil
  end

  defp format_ip(_), do: nil

  defp normalize_subject(subject) when is_binary(subject),
    do: subject |> String.trim() |> String.downcase() |> String.slice(0, 200)

  defp normalize_subject(subject), do: subject

  defp config(key, default) do
    :trifle
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end
end
