defmodule TrifleWeb.DynamicParsers do
  @moduledoc false

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    parser_opts =
      Plug.Parsers.init(
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library(),
        body_reader: {TrifleWeb.BodyReader, :read_body, []},
        length: Trifle.Config.request_body_max_bytes()
      )

    Plug.Parsers.call(conn, parser_opts)
  end
end
