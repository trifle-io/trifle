defmodule TrifleWeb.DynamicParsers do
  @moduledoc false

  @behaviour Plug

  @persistent_term_key {__MODULE__, :parser_opts}
  @persistent_term_length_key {__MODULE__, :parser_length}

  @impl true
  def init(opts) do
    _ = parser_opts()
    opts
  end

  @impl true
  def call(conn, _opts) do
    Plug.Parsers.call(conn, parser_opts())
  end

  defp parser_opts do
    length = Trifle.Config.request_body_max_bytes()

    case :persistent_term.get(@persistent_term_length_key, nil) do
      ^length ->
        :persistent_term.get(@persistent_term_key)

      _ ->
        refresh_parser_opts(length)
    end
  end

  defp refresh_parser_opts(length) do
    parser_opts =
      Plug.Parsers.init(
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library(),
        body_reader: {TrifleWeb.BodyReader, :read_body, []},
        length: length
      )

    :persistent_term.put(@persistent_term_key, parser_opts)
    :persistent_term.put(@persistent_term_length_key, length)
    parser_opts
  end
end
