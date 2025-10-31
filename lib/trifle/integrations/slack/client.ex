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

  defp request(method, path, headers, body \\ nil, opts \\ []) do
    Finch.build(method, "#{@base_url}#{path}", headers, body)
    |> Finch.request(Trifle.Finch, Keyword.get(opts, :finch_request_opts, []))
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

  def upload_file(token, channel, binary, metadata \\ %{}, opts \\ []) do
    filename =
      metadata_value(metadata, :filename)
      |> presence_or("preview.pdf")

    content_type = metadata_value(metadata, :content_type) || "application/pdf"

    title =
      metadata_value(metadata, :title)
      |> presence_or(filename)

    initial_comment = metadata_value(metadata, :initial_comment)

    alt_text =
      metadata_value(metadata, :alt_text)
      |> presence_or(title)
      |> presence_or(filename)

    data = IO.iodata_to_binary(binary)
    length = byte_size(data)

    upload_request =
      %{filename: filename, length: length, alt_text: alt_text}
      |> maybe_put_filetype(content_type)

    file_entry =
      %{id: nil, title: title, filename: filename, alt_text: alt_text, length: length}
      |> maybe_put_filetype(content_type)

    complete_opts = Keyword.put(opts, :initial_comment, initial_comment)

    with {:ok, %{upload_url: upload_url, file_id: file_id, file: file_details}} <-
           get_upload_url_external(token, upload_request, opts),
         :ok <- put_upload_binary(upload_url, data, content_type, opts),
         {:ok, complete_payload} <-
           complete_upload_external(
             token,
             update_file_id([file_entry], file_id),
             [channel],
             complete_opts
           ) do
      {:ok,
       %{
         file_id: file_id,
         file: file_details || extract_completed_file(complete_payload, file_id),
         response: complete_payload
       }}
    else
      {:error, %Finch.Response{status: status, body: resp_body}} ->
        {:error, :http_error, %{status: status, body: resp_body}}

      {:error, {:slack_error, "invalid_arguments", payload} = slack_error} ->
        Logger.warning(
          "Slack completeUploadExternal rejected request for channel #{channel} with invalid arguments: #{inspect(payload)}",
          channel: channel,
          filename: filename,
          title: title,
          content_type: content_type,
          upload_length: length,
          has_initial_comment: not is_nil(initial_comment) and initial_comment != ""
        )

        {:error, slack_error}

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
    value =
      case Map.get(metadata, key) do
        nil -> Map.get(metadata, Atom.to_string(key))
        v -> v
      end

    cond do
      is_nil(value) ->
        nil

      is_binary(value) ->
        value
        |> String.trim()
        |> presence_or(nil)

      true ->
        value
        |> to_string()
        |> String.trim()
        |> presence_or(nil)
    end
  end

  def get_upload_url_external(token, upload_params, opts \\ []) when is_map(upload_params) do
    payload_map =
      upload_params
      |> Map.take([:filename, :length, :alt_text, :title, :mime_type, :filetype])
      |> Enum.reduce(%{}, fn
        {_key, nil}, acc -> acc
        {key, value}, acc -> Map.put(acc, to_string(key), value)
      end)

    payload = URI.encode_query(payload_map)

    headers = [
      {"content-type", "application/x-www-form-urlencoded"},
      {"authorization", "Bearer #{token}"}
    ]

    with {:ok, %Finch.Response{status: 200, body: body}} <-
           request(:post, "/files.getUploadURLExternal", headers, payload, opts),
         {:ok, decoded} <- Jason.decode(body),
         {:ok, decoded} <- normalize_slack_response(decoded),
         {:ok, upload_info} <- extract_upload_data(decoded) do
      {:ok, upload_info}
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

  def complete_upload_external(token, files, channel_ids, opts \\ [])
      when is_list(files) and is_list(channel_ids) do
    initial_comment = Keyword.get(opts, :initial_comment)
    thread_ts = Keyword.get(opts, :thread_ts)

    normalized_channels =
      channel_ids
      |> Enum.map(&normalize_channel_identifier/1)
      |> Enum.reject(&is_nil/1)

    prepared_files = prepare_complete_files(files)

    payload_map =
      %{
        "files" => prepared_files,
        "channel_id" => List.first(normalized_channels)
      }
      |> maybe_put_optional("initial_comment", initial_comment)
      |> maybe_put_optional("thread_ts", thread_ts)

    payload = Jason.encode!(payload_map)

    with {:ok, %Finch.Response{status: 200, body: body}} <-
           request(:post, "/files.completeUploadExternal", json_headers(token), payload, opts),
         {:ok, decoded} <- Jason.decode(body),
         {:ok, decoded} <- normalize_slack_response(decoded) do
      {:ok, decoded}
    else
      {:error, {:slack_error, "invalid_arguments", response_payload} = slack_error} ->
        Logger.warning(
          "Slack completeUploadExternal invalid arguments for channels #{inspect(normalized_channels)}",
          channels: normalized_channels,
          request_payload: payload_map,
          response_payload: response_payload
        )

        {:error, slack_error}

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

  def put_upload_binary(upload_url, binary, _content_type, opts \\ []) do
    data = IO.iodata_to_binary(binary)

    headers =
      [{"content-type", "application/octet-stream"}]
      |> maybe_put_content_length(data)

    request = Finch.build(:post, upload_url, headers, data)

    finch_opts = [redirect: true] ++ Keyword.get(opts, :finch_request_opts, [])

    case Finch.request(request, Trifle.Finch, finch_opts) do
      {:ok, %Finch.Response{status: status}} when status in 200..399 ->
        :ok

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, {:upload_failed, %{status: status, body: body}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp json_headers(token) do
    [
      {"content-type", "application/json; charset=utf-8"},
      {"authorization", "Bearer #{token}"}
    ]
  end

  defp extract_upload_data(%{"upload_url" => upload_url, "file_id" => file_id} = payload)
       when is_binary(upload_url) and is_binary(file_id) do
    {:ok, %{upload_url: upload_url, file_id: file_id, file: Map.get(payload, "file")}}
  end

  defp extract_upload_data(payload),
    do: {:error, {:slack_error, "invalid_upload_payload", payload}}

  defp maybe_put_optional(map, _key, value) when value in [nil, "", []], do: map

  defp maybe_put_optional(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_filetype(file_entry, content_type) do
    case slack_filetype(content_type) do
      nil -> file_entry
      type -> Map.put(file_entry, :filetype, type)
    end
  end

  defp slack_filetype(nil), do: nil

  defp slack_filetype(content_type) when is_binary(content_type) do
    case String.split(content_type, "/") do
      [_type, subtype] ->
        subtype
        |> String.downcase()
        |> normalize_slack_filetype()

      _ ->
        nil
    end
  end

  defp slack_filetype(_), do: nil

  defp normalize_slack_filetype("jpeg"), do: "jpg"
  defp normalize_slack_filetype("svg+xml"), do: "svg"

  defp normalize_slack_filetype(subtype) when is_binary(subtype) do
    subtype
    |> String.replace(~r/[^a-z0-9.+-]/, "")
    |> presence_or(nil)
  end

  defp normalize_slack_filetype(_), do: nil

  defp presence_or(value, fallback) do
    case value do
      nil -> fallback
      "" -> fallback
      _ -> value
    end
  end

  defp prepare_complete_files(files) when is_list(files) do
    files
    |> Enum.map(&prepare_complete_file/1)
    |> Enum.reject(&is_nil/1)
  end

  defp prepare_complete_files(_), do: []

  defp prepare_complete_file(%{} = file) do
    id =
      file
      |> get_field(:id)
      |> presence_or(get_field(file, "id"))

    filename =
      file
      |> get_field(:filename)
      |> presence_or(get_field(file, "filename"))
      |> presence_or(get_field(file, :name))
      |> presence_or(get_field(file, "name"))
      |> presence_or(get_field(file, :title))
      |> presence_or(get_field(file, "title"))
      |> presence_or("attachment.pdf")

    title =
      file
      |> get_field(:title)
      |> presence_or(get_field(file, "title"))
      |> presence_or(filename)

    # For completeUploadExternal, Slack only accepts: id (required) and title (optional)
    %{"id" => id}
    |> maybe_put_optional("title", title)
  rescue
    _ -> nil
  end

  defp prepare_complete_file(_), do: nil

  defp get_field(map, key) when is_atom(key) do
    case Map.get(map, key) do
      nil -> Map.get(map, Atom.to_string(key))
      value -> value
    end
  end

  defp get_field(map, key) when is_binary(key) do
    case Map.get(map, key) do
      nil -> get_existing_atom(map, key)
      value -> value
    end
  end

  defp get_field(_map, _key), do: nil

  defp get_existing_atom(map, key) when is_binary(key) do
    try do
      atom = String.to_existing_atom(key)
      Map.get(map, atom)
    rescue
      ArgumentError -> nil
    end
  end

  defp get_existing_atom(_map, _key), do: nil

  defp update_file_id(files, file_id) do
    Enum.map(files, fn file ->
      file
      |> Map.put(:id, file_id)
      |> Map.put("id", file_id)
    end)
  end

  defp extract_completed_file(%{"files" => files}, file_id) when is_list(files) do
    Enum.find(files, fn
      %{"id" => id} -> id == file_id
      %{"file" => %{"id" => id}} -> id == file_id
      _ -> false
    end)
  end

  defp extract_completed_file(_payload, _file_id), do: nil

  defp maybe_put_content_length(headers, data) when is_binary(data) do
    [{"content-length", Integer.to_string(byte_size(data))} | headers]
    |> Enum.uniq_by(fn {key, _val} -> String.downcase(key) end)
  end

  defp normalize_channel_identifier(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_channel_identifier(value) when is_atom(value) do
    value |> Atom.to_string() |> normalize_channel_identifier()
  end

  defp normalize_channel_identifier(_), do: nil
end
