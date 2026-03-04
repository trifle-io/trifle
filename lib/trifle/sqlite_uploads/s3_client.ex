defmodule Trifle.SqliteUploads.S3Client do
  @moduledoc false

  @service "s3"
  @default_timeout_ms 120_000

  def put_object(object_key, source_path, config) do
    with :ok <- validate_config(config),
         {:ok, binary} <- File.read(source_path),
         {:ok, target} <- request_target(config, object_key),
         headers <- signed_headers("PUT", target, binary, config),
         :ok <- request("PUT", target.url, headers, binary, request_timeout(config)) do
      :ok
    end
  end

  def get_object(object_key, destination_path, config) do
    with :ok <- validate_config(config),
         {:ok, target} <- request_target(config, object_key),
         headers <- signed_headers("GET", target, "", config),
         {:ok, body} <-
           request_with_body("GET", target.url, headers, "", request_timeout(config)),
         :ok <- File.write(destination_path, body, [:binary]) do
      :ok
    end
  end

  def delete_object(object_key, config) do
    with :ok <- validate_config(config),
         {:ok, target} <- request_target(config, object_key),
         headers <- signed_headers("DELETE", target, "", config),
         :ok <- request("DELETE", target.url, headers, "", request_timeout(config)) do
      :ok
    end
  end

  defp validate_config(config) when is_map(config) do
    missing =
      [
        {:endpoint, config[:endpoint]},
        {:bucket, config[:bucket]},
        {:region, config[:region]},
        {:access_key_id, config[:access_key_id]},
        {:secret_access_key, config[:secret_access_key]}
      ]
      |> Enum.filter(fn {_key, value} -> value in [nil, ""] end)
      |> Enum.map(fn {key, _value} -> key end)

    case missing do
      [] -> :ok
      _ -> {:error, "SQLite object storage missing config: #{Enum.join(missing, ", ")}"}
    end
  end

  defp validate_config(_), do: {:error, "SQLite object storage config is invalid"}

  defp request_target(config, object_key) do
    endpoint_uri = URI.parse(config[:endpoint] || "")

    with host when is_binary(host) and host != "" <- endpoint_uri.host do
      scheme = endpoint_uri.scheme || "https"
      port = endpoint_uri.port
      base_segments = path_segments(endpoint_uri.path)
      key_segments = path_segments(object_key)
      force_path_style = Map.get(config, :force_path_style, true)
      bucket = config[:bucket]

      {request_host, request_path_segments} =
        if force_path_style do
          {host, base_segments ++ [bucket] ++ key_segments}
        else
          {"#{bucket}.#{host}", base_segments ++ key_segments}
        end

      canonical_uri = encode_canonical_uri(request_path_segments)
      url_host = host_with_optional_port(request_host, port)
      url = "#{scheme}://#{url_host}#{canonical_uri}"
      host_header = host_with_optional_port(request_host, port, scheme)

      {:ok, %{url: url, canonical_uri: canonical_uri, host_header: host_header}}
    else
      _ -> {:error, "SQLite object storage endpoint is invalid"}
    end
  end

  defp request_timeout(config) do
    case Map.get(config, :request_timeout_ms, @default_timeout_ms) do
      timeout when is_integer(timeout) and timeout > 0 -> timeout
      _ -> @default_timeout_ms
    end
  end

  defp signed_headers(method, target, payload, config) do
    payload_hash = sha256_hex(payload)
    amz_date = amz_date()
    date = binary_part(amz_date, 0, 8)
    region = config[:region]

    headers_to_sign = %{
      "host" => target.host_header,
      "x-amz-content-sha256" => payload_hash,
      "x-amz-date" => amz_date
    }

    canonical_headers = canonical_headers(headers_to_sign)
    signed_headers = signed_header_names(headers_to_sign)

    canonical_request =
      [
        method,
        target.canonical_uri,
        "",
        canonical_headers,
        signed_headers,
        payload_hash
      ]
      |> Enum.join("\n")

    credential_scope = "#{date}/#{region}/#{@service}/aws4_request"

    string_to_sign =
      [
        "AWS4-HMAC-SHA256",
        amz_date,
        credential_scope,
        sha256_hex(canonical_request)
      ]
      |> Enum.join("\n")

    signature =
      signature_key(config[:secret_access_key], date, region, @service)
      |> hmac_sha256(string_to_sign)
      |> Base.encode16(case: :lower)

    authorization =
      "AWS4-HMAC-SHA256 Credential=#{config[:access_key_id]}/#{credential_scope}, SignedHeaders=#{signed_headers}, Signature=#{signature}"

    [
      {"host", target.host_header},
      {"x-amz-content-sha256", payload_hash},
      {"x-amz-date", amz_date},
      {"authorization", authorization}
    ]
  end

  defp request(method, url, headers, body, timeout) do
    req = Finch.build(method, url, headers, body)

    case Finch.request(req, Trifle.Finch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, {:http_error, status, preview_body(body)}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp request_with_body(method, url, headers, body, timeout) do
    req = Finch.build(method, url, headers, body)

    case Finch.request(req, Trifle.Finch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, {:http_error, status, preview_body(body)}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp path_segments(nil), do: []
  defp path_segments(""), do: []

  defp path_segments(path) when is_binary(path) do
    path
    |> String.split("/", trim: true)
    |> Enum.reject(&(&1 == ""))
  end

  defp encode_canonical_uri([]), do: "/"

  defp encode_canonical_uri(segments) when is_list(segments) do
    encoded_segments =
      Enum.map(segments, fn segment ->
        URI.encode(segment, &URI.char_unreserved?/1)
      end)

    "/" <> Enum.join(encoded_segments, "/")
  end

  defp host_with_optional_port(host, nil, _scheme), do: host

  defp host_with_optional_port(host, port, scheme) do
    default_port =
      case scheme do
        "http" -> 80
        "https" -> 443
        _ -> nil
      end

    if port == default_port do
      host
    else
      "#{host}:#{port}"
    end
  end

  defp host_with_optional_port(host, nil), do: host
  defp host_with_optional_port(host, port), do: "#{host}:#{port}"

  defp canonical_headers(headers) do
    headers
    |> Enum.map(fn {name, value} ->
      {String.downcase(name),
       value |> to_string() |> String.trim() |> String.replace(~r/\s+/, " ")}
    end)
    |> Enum.sort_by(fn {name, _value} -> name end)
    |> Enum.map_join("\n", fn {name, value} -> "#{name}:#{value}" end)
  end

  defp signed_header_names(headers) do
    headers
    |> Enum.map(fn {name, _value} -> String.downcase(name) end)
    |> Enum.sort()
    |> Enum.join(";")
  end

  defp signature_key(secret_access_key, date, region, service) do
    ("AWS4" <> secret_access_key)
    |> hmac_sha256(date)
    |> hmac_sha256(region)
    |> hmac_sha256(service)
    |> hmac_sha256("aws4_request")
  end

  defp hmac_sha256(key, value), do: :crypto.mac(:hmac, :sha256, key, value)
  defp sha256_hex(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp amz_date do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%Y%m%dT%H%M%SZ")
  end

  defp preview_body(nil), do: ""
  defp preview_body(""), do: ""

  defp preview_body(body) when is_binary(body) do
    body
    |> String.slice(0, 300)
  end

  defp preview_body(body), do: inspect(body, limit: 50, printable_limit: 300)
end
