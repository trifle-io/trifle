defmodule TrifleApp.StripeWebhookController do
  use TrifleApp, :controller
  require Logger

  plug :ensure_saas_mode

  def create(conn, _params) do
    with {:ok, payload, conn} <- fetch_raw_payload(conn),
         signature <- List.first(get_req_header(conn, "stripe-signature")),
         secret <- System.get_env("STRIPE_WEBHOOK_SIGNING_SECRET"),
         :ok <- Trifle.Billing.StripeSignature.verify(payload, signature, secret),
         {:ok, decoded} <- Jason.decode(payload),
         {:ok, _event} <- normalize_webhook_result(Trifle.Billing.create_webhook_event(decoded)) do
      json(conn, %{ok: true})
    else
      {:error, :missing_secret} ->
        log_rejection(conn, :missing_secret)

        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "webhook_secret_not_configured"})

      {:error, :missing_header} ->
        log_rejection(conn, :missing_header)

        conn
        |> put_status(:bad_request)
        |> json(%{error: "missing_signature"})

      {:error, :timestamp_out_of_tolerance} ->
        log_rejection(conn, :timestamp_out_of_tolerance)

        conn
        |> put_status(:bad_request)
        |> json(%{error: "timestamp_out_of_tolerance"})

      {:error, :signature_mismatch} ->
        log_rejection(conn, :signature_mismatch)

        conn
        |> put_status(:bad_request)
        |> json(%{error: "signature_mismatch"})

      {:error, :invalid_header} ->
        log_rejection(conn, :invalid_header)

        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_signature_header"})

      {:error, %Jason.DecodeError{}} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_json"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  defp fetch_raw_payload(%Plug.Conn{assigns: %{raw_body: raw}} = conn) when is_binary(raw),
    do: {:ok, raw, conn}

  defp fetch_raw_payload(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, raw, conn} -> {:ok, raw, conn}
      {:more, _partial, conn} -> fetch_raw_payload(conn)
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_webhook_result({:ok, event}), do: {:ok, event}
  defp normalize_webhook_result(:ok), do: {:ok, :duplicate}
  defp normalize_webhook_result({:error, reason}), do: {:error, reason}

  defp log_rejection(conn, reason) do
    signature_present? = get_req_header(conn, "stripe-signature") != []

    raw_body_size =
      conn.assigns[:raw_body]
      |> case do
        body when is_binary(body) -> byte_size(body)
        _ -> 0
      end

    secret_present? =
      case System.get_env("STRIPE_WEBHOOK_SIGNING_SECRET") do
        secret when is_binary(secret) and secret != "" -> true
        _ -> false
      end

    Logger.warning(
      "Stripe webhook rejected " <>
        "reason=#{inspect(reason)} " <>
        "path=#{conn.request_path} " <>
        "raw_body_size=#{raw_body_size} " <>
        "signature_present?=#{signature_present?} " <>
        "secret_present?=#{secret_present?}"
    )
  end

  defp ensure_saas_mode(conn, _opts) do
    if Trifle.Config.saas_mode?() do
      conn
    else
      conn
      |> put_status(:not_found)
      |> put_view(json: TrifleApi.ErrorJSON)
      |> render("404.json")
      |> halt()
    end
  end
end
