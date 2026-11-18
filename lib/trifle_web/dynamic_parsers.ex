defmodule TrifleWeb.DynamicParsers do
  @moduledoc """
  `Plug.Parsers` with a body size limit chosen per route.

  Ordinary requests are capped at `Trifle.Config.request_body_max_bytes/0`. Only
  the routes that accept a SQLite file upload get the larger
  `Trifle.Config.upload_request_body_max_bytes/0`, so unauthenticated endpoints
  (login, signup, webhooks) cannot be made to buffer upload-sized bodies.

  The browser CSP report endpoint is unauthenticated and gets a few kilobytes.

  LiveView uploads travel over the socket and are not affected by these limits.
  """

  @behaviour Plug

  # Path prefixes (as `conn.path_info`) that may carry an uploaded SQLite file.
  @upload_prefixes [["api", "v1", "bootstrap", "databases"]]

  # Unauthenticated endpoints that only ever receive a small document.
  @small_paths [["csp-report"]]
  @small_body_max_bytes 16_384

  @impl true
  def init(opts) do
    _ = parser_opts(:default)
    opts
  end

  @impl true
  def call(conn, _opts) do
    kind =
      cond do
        conn.path_info in @small_paths -> :small
        upload_route?(conn) -> :upload
        true -> :default
      end

    Plug.Parsers.call(conn, parser_opts(kind))
  end

  @doc false
  def upload_route?(%Plug.Conn{path_info: path_info}) do
    Enum.any?(@upload_prefixes, &List.starts_with?(path_info, &1))
  end

  defp length_for(:small), do: @small_body_max_bytes
  defp length_for(:upload), do: Trifle.Config.upload_request_body_max_bytes()
  defp length_for(:default), do: Trifle.Config.request_body_max_bytes()

  # Parser options are cached per kind and rebuilt if the configured limit changes.
  defp parser_opts(kind) do
    length = length_for(kind)
    key = {__MODULE__, :parser_opts, kind}

    case :persistent_term.get(key, nil) do
      {^length, opts} ->
        opts

      _ ->
        opts =
          Plug.Parsers.init(
            parsers: [:urlencoded, :multipart, :json],
            pass: ["*/*"],
            json_decoder: Phoenix.json_library(),
            body_reader: {TrifleWeb.BodyReader, :read_body, []},
            length: length
          )

        :persistent_term.put(key, {length, opts})
        opts
    end
  end
end
