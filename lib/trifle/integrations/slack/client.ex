defmodule Trifle.Integrations.Slack.Client do
  @moduledoc false

  require Logger

  @base_url "https://slack.com/api"

  def exchange_code(config, code) do
    body =
      %{
        "client_id" => config.client_id,
        "client_secret" => config.client_secret,
        "code" => code,
        "redirect_uri" => config.redirect_uri
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new()
      |> URI.encode_query()

    headers = [
      {"content-type", "application/x-www-form-urlencoded"}
    ]

    with :ok <- ensure_present(config.client_id, :client_id),
         :ok <- ensure_present(config.client_secret, :client_secret),
         :ok <- ensure_present(config.redirect_uri, :redirect_uri),
         {:ok, %Finch.Response{status: 200, body: body}} <-
           request(:post, "/oauth.v2.access", headers, body),
         {:ok, payload} <- Jason.decode(body),
         {:ok, payload} <- normalize_slack_response(payload) do
      {:ok, payload}
    else
      {:error, %Finch.Response{status: status, body: body}} ->
        Logger.warning("Slack OAuth exchange failed with HTTP #{status}: #{inspect(body)}")
        {:error, :http_error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, :decode_error, reason}

      {:error, {:slack_error, error, payload}} ->
        {:error, {:slack_error, error}, payload}

      {:error, :missing, field} ->
        {:error, {:missing_config, field}}
    end
  end

  def list_channels(bot_access_token, opts \\ []) do
    types = Keyword.get(opts, :types, "public_channel,private_channel")
    limit = Keyword.get(opts, :limit, 500)

    do_list_channels(bot_access_token, types, limit, nil, [])
  end

  defp do_list_channels(token, types, limit, cursor, acc) do
    params =
      %{
        "types" => types,
        "limit" => limit
      }
      |> maybe_put_cursor(cursor)
      |> URI.encode_query()

    headers = [{"authorization", "Bearer #{token}"}]

    with {:ok, %Finch.Response{status: 200, body: body}} <-
           request(:get, "/conversations.list?#{params}", headers),
         {:ok, payload} <- Jason.decode(body),
         {:ok, payload} <- normalize_slack_response(payload) do
      channels = Map.get(payload, "channels", [])
      next_cursor = get_in(payload, ["response_metadata", "next_cursor"])

      combined = acc ++ channels

      if present?(next_cursor) do
        do_list_channels(token, types, limit, next_cursor, combined)
      else
        {:ok, combined}
      end
    else
      {:error, %Finch.Response{status: status, body: body}} ->
        {:error, :http_error, %{status: status, body: body}}

      {:error, {:slack_error, error, payload}} ->
        {:error, {:slack_error, error}, payload}

      {:error, reason} ->
        {:error, :decode_error, reason}

      other ->
        other
    end
  end

  defp request(method, path, headers, body \\ nil) do
    Finch.build(method, "#{@base_url}#{path}", headers, body)
    |> Finch.request(Trifle.Finch)
  end

  defp normalize_slack_response(%{"ok" => true} = payload), do: {:ok, payload}
  defp normalize_slack_response(%{"ok" => false, "error" => error} = payload),
    do: {:error, {:slack_error, error, payload}}

  defp normalize_slack_response(payload),
    do: {:error, {:slack_error, "unknown_response", payload}}

  defp ensure_present(nil, field), do: {:error, :missing, field}
  defp ensure_present("", field), do: {:error, :missing, field}
  defp ensure_present(_value, _field), do: :ok

  defp maybe_put_cursor(params, nil), do: params
  defp maybe_put_cursor(params, ""), do: params
  defp maybe_put_cursor(params, cursor), do: Map.put(params, "cursor", cursor)

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
