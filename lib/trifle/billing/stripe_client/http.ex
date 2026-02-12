defmodule Trifle.Billing.StripeClient.HTTP do
  def update_subscription(subscription_id, params),
    do: update_subscription(subscription_id, params, [])

  def update_subscription(subscription_id, params, opts)
      when is_binary(subscription_id) and is_map(params) and is_list(opts) do
    request(:post, <<"/v1/subscriptions/", subscription_id::binary>>, params, opts)
  end

  defp stripe_error(%{"error" => %{"message" => message, "type" => type}} = body, status)
       when :erlang.is_binary(message) do
    {:stripe_error, status, type, message, body}
  end

  defp stripe_error(body, status) do
    {:stripe_error, status, body}
  end

  defp request(method, path, params, opts \\ []) do
    idempotency_key = Keyword.get(opts, :idempotency_key)

    with {:ok, secret_key} <- fetch_secret_key(),
         {:ok, body} <- encode_form(params),
         {:ok, response} <- do_request(method, path, body, secret_key, idempotency_key),
         {:ok, decoded} <- decode_body(response.body) do
      case response.status do
        code
        when :erlang.andalso(
               :erlang.is_integer(code),
               :erlang.andalso(:erlang.>=(code, 200), :erlang."=<"(code, 299))
             ) ->
          {:ok, decoded}

        _ ->
          {:error, stripe_error(decoded, response.status)}
      end
    end
  end

  def get_subscription(subscription_id) when :erlang.is_binary(subscription_id) do
    request(:get, <<"/v1/subscriptions/", subscription_id::binary>>, %{})
  end

  defp flatten_params(params) when :erlang.is_map(params) do
    Enum.flat_map(
      params,
      fn {key, value} -> flatten_pair([String.Chars.to_string(key)], value) end
    )
  end

  defp flatten_pair(_path, nil) do
    []
  end

  defp flatten_pair(path, value) when :erlang.is_map(value) do
    Enum.flat_map(value, fn {k, v} ->
      flatten_pair(:erlang.++(path, [String.Chars.to_string(k)]), v)
    end)
  end

  defp flatten_pair(path, list) when :erlang.is_list(list) do
    Enum.flat_map(
      Enum.with_index(list),
      fn {value, idx} -> flatten_pair(:erlang.++(path, [String.Chars.to_string(idx)]), value) end
    )
  end

  defp flatten_pair(path, value) when :erlang.is_boolean(value) do
    [
      {encode_path(path),
       case value do
         x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> "false"
         _ -> "true"
       end}
    ]
  end

  defp flatten_pair(path, value) do
    [{encode_path(path), String.Chars.to_string(value)}]
  end

  defp fetch_secret_key() do
    case System.get_env("STRIPE_SECRET_KEY") do
      value when :erlang.andalso(:erlang.is_binary(value), :erlang."/="(value, "")) ->
        {:ok, value}

      _ ->
        {:error, :missing_stripe_secret_key}
    end
  end

  defp encode_path([head | tail]) do
    Enum.reduce(tail, head, fn part, acc -> <<acc::binary, "[", part::binary, "]">> end)
  end

  defp encode_form(params) do
    try do
      (fn capture -> {:ok, capture} end).(URI.encode_query(flatten_params(params)))
    rescue
      error -> {:error, error}
    end
  end

  defp do_request(method, path, body, secret_key, idempotency_key) do
    url = <<"https://api.stripe.com"::binary, path::binary>>

    headers = [
      {"authorization", <<"Bearer ", secret_key::binary>>},
      {"content-type", "application/x-www-form-urlencoded"}
    ]

    headers =
      case {method, idempotency_key} do
        {m, key} when m in [:post, "POST", "post"] and is_binary(key) and key != "" ->
          [{"idempotency-key", key} | headers]

        _ ->
          headers
      end

    request = Finch.build(method, url, headers, body)

    case Finch.request(request, Trifle.Finch, receive_timeout: 15000) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_body(body) when :erlang.orelse(:erlang."=:="(body, nil), :erlang."=:="(body, "")) do
    {:ok, %{}}
  end

  defp decode_body(body) when :erlang.is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} -> {:ok, map}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  def create_portal_session(params), do: create_portal_session(params, [])

  def create_portal_session(params, opts) when is_map(params) and is_list(opts) do
    request(:post, "/v1/billing_portal/sessions", params, opts)
  end

  def create_customer(params), do: create_customer(params, [])

  def create_customer(params, opts) when is_map(params) and is_list(opts) do
    request(:post, "/v1/customers", params, opts)
  end

  def create_checkout_session(params), do: create_checkout_session(params, [])

  def create_checkout_session(params, opts) when is_map(params) and is_list(opts) do
    request(:post, "/v1/checkout/sessions", params, opts)
  end
end
