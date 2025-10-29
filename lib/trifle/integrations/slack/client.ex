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

  def chat_post_message(token, channel, text, _opts \\ []) do
    body =
      %{
        "channel" => channel,
        "text" => text,
        "mrkdwn" => true
      }
      |> Jason.encode!()

    headers = [
      {"content-type", "application/json; charset=utf-8"},
      {"authorization", "Bearer #{token}"}
    ]

    with {:ok, %Finch.Response{status: 200, body: resp_body}} <-
           request(:post, "/chat.postMessage", headers, body),
         {:ok, payload} <- Jason.decode(resp_body),
         {:ok, payload} <- normalize_slack_response(payload) do
      {:ok, payload}
    else
      {:error, %Finch.Response{status: status, body: resp_body}} ->
        {:error, :http_error, %{status: status, body: resp_body}}

      {:error, {:slack_error, _error, _payload} = slack_error} ->
        {:error, slack_error}

      {:error, reason} ->
        {:error, reason}

      other ->
        other
    end
  end

  def upload_file(token, channel, binary, metadata \\ %{}, _opts \\ []) do
    filename = metadata_value(metadata, :filename) || "preview.bin"
    content_type = metadata_value(metadata, :content_type) || "application/octet-stream"
    title = metadata_value(metadata, :title) || filename
    initial_comment = metadata_value(metadata, :initial_comment)
    boundary = "---------------------------trifle#{System.unique_integer([:positive])}"

    parts =
      [
        multipart_field("channels", channel),
        multipart_field("filename", filename),
        multipart_field("title", title)
      ]
      |> maybe_add_comment(initial_comment)
      |> Kernel.++([multipart_file("file", filename, content_type, binary)])

    body = build_multipart(boundary, parts)

    headers = [
      {"authorization", "Bearer #{token}"},
      {"content-type", "multipart/form-data; boundary=#{boundary}"}
    ]

    with {:ok, %Finch.Response{status: 200, body: resp_body}} <-
           request(:post, "/files.upload", headers, body),
         {:ok, payload} <- Jason.decode(resp_body),
         {:ok, payload} <- normalize_slack_response(payload) do
      {:ok, payload}
    else
      {:error, %Finch.Response{status: status, body: resp_body}} ->
        {:error, :http_error, %{status: status, body: resp_body}}

      {:error, {:slack_error, _error, _payload} = slack_error} ->
        {:error, slack_error}

      {:error, reason} ->
        {:error, reason}

      other ->
        other
    end
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

  defp metadata_value(metadata, key) when is_atom(key) do
    value = Map.get(metadata, key) || Map.get(metadata, Atom.to_string(key))

    cond do
      is_nil(value) -> nil
      is_binary(value) -> value
      true -> to_string(value)
    end
  end

  defp maybe_add_comment(parts, comment) when comment in [nil, ""] do
    parts
  end

  defp maybe_add_comment(parts, comment) do
    parts ++ [multipart_field("initial_comment", comment)]
  end

  defp multipart_field(name, value), do: {:field, name, value}

  defp multipart_file(name, filename, content_type, data) do
    {:file, name, filename, content_type, data}
  end

  defp build_multipart(boundary, parts) do
    body =
      parts
      |> Enum.map(fn
        {:file, name, filename, content_type, data} ->
          [
            "--",
            boundary,
            "\r\n",
            "Content-Disposition: form-data; name=\"",
            name,
            "\"; filename=\"",
            filename,
            "\"\r\n",
            "Content-Type: ",
            content_type,
            "\r\n\r\n",
            data,
            "\r\n"
          ]

        {:field, field_name, value} ->
          [
            "--",
            boundary,
            "\r\n",
            "Content-Disposition: form-data; name=\"",
            field_name,
            "\"\r\n\r\n",
            value,
            "\r\n"
          ]
      end)

    [body, "--", boundary, "--\r\n"]
  end
end
