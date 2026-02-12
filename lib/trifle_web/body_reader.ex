defmodule TrifleWeb.BodyReader do
  @moduledoc false

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = maybe_store_raw_body(conn, body)
        {:ok, body, conn}

      {:more, body, conn} ->
        conn = maybe_store_raw_body(conn, body)
        {:more, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_store_raw_body(%Plug.Conn{} = conn, body) when is_binary(body) do
    if stripe_webhook_request?(conn) do
      Plug.Conn.assign(conn, :raw_body, (conn.assigns[:raw_body] || "") <> body)
    else
      conn
    end
  end

  defp stripe_webhook_request?(%Plug.Conn{method: "POST", request_path: "/webhooks/stripe"}),
    do: true

  defp stripe_webhook_request?(_conn), do: false
end
