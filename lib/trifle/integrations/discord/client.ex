defmodule Trifle.Integrations.Discord.Client do
  @moduledoc false

  require Logger

  @base_url "https://discord.com/api/v10"

  def exchange_code(config, code) do
    body =
      %{
        "client_id" => config.client_id,
        "client_secret" => config.client_secret,
        "code" => code,
        "grant_type" => "authorization_code",
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
           request(:post, "/oauth2/token", headers, body, config),
         {:ok, payload} <- Jason.decode(body),
         {:ok, payload} <- normalize_token_response(payload) do
      {:ok, payload}
    else
      {:error, %Finch.Response{status: status, body: body}} ->
        Logger.warning("Discord OAuth exchange failed with HTTP #{status}: #{inspect(body)}")
        {:error, :http_error, %{status: status, body: body}}

      {:error, {:discord_error, _error, _payload} = discord_error} ->
        {:error, discord_error}

      {:error, reason} ->
        {:error, :decode_error, reason}

      {:error, :missing, field} ->
        {:error, {:missing_config, field}}
    end
  end

  def fetch_guild(bot_token, guild_id, opts \\ []) do
    headers = [{"authorization", "Bot #{bot_token}"}]

    with {:ok, %Finch.Response{status: 200, body: body}} <-
           request(:get, "/guilds/#{guild_id}", headers, nil, opts),
         {:ok, payload} <- Jason.decode(body),
         {:ok, payload} <- normalize_api_response(payload) do
      {:ok, payload}
    else
      {:error, %Finch.Response{status: status, body: body}} ->
        {:error, :http_error, %{status: status, body: body}}

      {:error, {:discord_error, _error, _payload} = discord_error} ->
        {:error, discord_error}

      {:error, reason} ->
        {:error, :decode_error, reason}
    end
  end

  def list_channels(bot_token, guild_id, opts \\ []) do
    headers = [{"authorization", "Bot #{bot_token}"}]

    with {:ok, %Finch.Response{status: 200, body: body}} <-
           request(:get, "/guilds/#{guild_id}/channels", headers, nil, opts),
         {:ok, payload} <- Jason.decode(body),
         {:ok, payload} <- normalize_api_response(payload) do
      {:ok, payload}
    else
      {:error, %Finch.Response{status: status, body: body}} ->
        {:error, :http_error, %{status: status, body: body}}

      {:error, {:discord_error, _error, _payload} = discord_error} ->
        {:error, discord_error}

      {:error, reason} ->
        {:error, :decode_error, reason}
    end
  end

  def create_message(bot_token, channel_id, content, attachments \\ [], opts \\ []) do
    payload = %{
      "content" => content,
      "allowed_mentions" => %{"parse" => []}
    }

    filtered_attachments =
      attachments
      |> List.wrap()
      |> Enum.filter(fn attachment ->
        case Map.get(attachment, :binary) || Map.get(attachment, "binary") do
          binary when is_binary(binary) -> true
          _ -> false
        end
      end)

    cond do
      not present?(content) and filtered_attachments == [] ->
        {:error, {:invalid_request, :empty_message}}

      filtered_attachments == [] ->
        post_json_message(bot_token, channel_id, payload, opts)

      true ->
        post_multipart_message(bot_token, channel_id, payload, filtered_attachments, opts)
    end
  end

  defp post_json_message(bot_token, channel_id, payload, opts) do
    headers = [
      {"content-type", "application/json"},
      {"authorization", "Bot #{bot_token}"}
    ]

    case Jason.encode(payload) do
      {:ok, body} ->
        do_post_message(channel_id, headers, body, opts)

      {:error, reason} ->
        {:error, {:encode_error, reason}}
    end
  end

  defp post_multipart_message(bot_token, channel_id, payload, attachments, opts) do
    payload_json = Jason.encode!(payload)

    payload_part =
      Multipart.Part.binary_body(payload_json, [
        {"content-disposition", "form-data; name=\"payload_json\""},
        {"content-type", "application/json"}
      ])

    parts =
      attachments
      |> Enum.with_index()
      |> Enum.reduce([payload_part], fn {attachment, index}, acc ->
        data = Map.get(attachment, :binary) || Map.get(attachment, "binary")
        filename = Map.get(attachment, :filename) || Map.get(attachment, "filename")
        content_type = Map.get(attachment, :content_type) || Map.get(attachment, "content_type")

        part =
          Multipart.Part.file_content_field(
            filename || default_filename(index),
            data,
            "files[#{index}]",
            [],
            filename: filename || default_filename(index),
            content_type: content_type || MIME.from_path(filename || default_filename(index))
          )

        acc ++ [part]
      end)

    multipart =
      parts
      |> Enum.reduce(Multipart.new(), fn part, mp -> Multipart.add_part(mp, part) end)

    body = Multipart.body_binary(multipart)
    content_length = byte_size(body)
    content_type = Multipart.content_type(multipart, "multipart/form-data")

    headers = [
      {"content-type", content_type},
      {"content-length", Integer.to_string(content_length)},
      {"authorization", "Bot #{bot_token}"}
    ]

    do_post_message(channel_id, headers, body, opts)
  end

  defp do_post_message(channel_id, headers, body, opts) do
    with {:ok, %Finch.Response{status: status, body: resp_body}} <-
           request(:post, "/channels/#{channel_id}/messages", headers, body, opts),
         true <- status in 200..299 || {:error, :http_error, %{status: status, body: resp_body}},
         {:ok, payload} <- Jason.decode(resp_body),
         {:ok, payload} <- normalize_api_response(payload) do
      {:ok, payload}
    else
      {:error, %Finch.Response{status: status, body: resp_body}} ->
        {:error, :http_error, %{status: status, body: resp_body}}

      {:error, {:discord_error, _error, _payload} = discord_error} ->
        {:error, discord_error}

      {:error, reason} ->
        {:error, :decode_error, reason}
    end
  end

  defp request(method, path, headers, body \\ nil, opts \\ []) do
    finch_opts =
      case opts do
        %{} = map -> Map.get(map, :finch_request_opts, [])
        kw when is_list(kw) -> Keyword.get(kw, :finch_request_opts, [])
        _ -> []
      end

    Finch.build(method, "#{@base_url}#{path}", headers, body)
    |> Finch.request(Trifle.Finch, finch_opts)
  end

  defp normalize_token_response(%{"error" => error} = payload),
    do: {:error, {:discord_error, error, payload}}

  defp normalize_token_response(%{"access_token" => _token} = payload), do: {:ok, payload}

  defp normalize_token_response(payload),
    do: {:error, {:discord_error, "unknown_token_response", payload}}

  defp normalize_api_response(%{"message" => message, "code" => code} = payload),
    do: {:error, {:discord_error, message, code, payload}}

  defp normalize_api_response(payload) when is_map(payload) or is_list(payload),
    do: {:ok, payload}

  defp normalize_api_response(payload),
    do: {:error, {:discord_error, "unknown_response", payload}}

  defp ensure_present(nil, field), do: {:error, :missing, field}
  defp ensure_present("", field), do: {:error, :missing, field}
  defp ensure_present(_value, _field), do: :ok

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp default_filename(index), do: "attachment-#{index + 1}"
end
