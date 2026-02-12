defmodule Trifle.Billing.StripeSignature do
  def verify(payload, header, secret, tolerance_seconds \\ 300)

  def verify(_payload, _header, nil, _tolerance_seconds), do: {:error, :missing_secret}
  def verify(_payload, _header, "", _tolerance_seconds), do: {:error, :missing_secret}
  def verify(_payload, nil, _secret, _tolerance_seconds), do: {:error, :missing_header}

  def verify(payload, header, secret, tolerance_seconds)
      when is_binary(payload) and is_binary(header) and is_binary(secret) do
    with {:ok, timestamp, signatures} <- parse_header(header),
         :ok <- validate_timestamp(timestamp, tolerance_seconds),
         :ok <- validate_signature(payload, timestamp, signatures, secret) do
      :ok
    end
  end

  defp validate_timestamp(timestamp, tolerance_seconds) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    if abs(now - timestamp) <= tolerance_seconds do
      :ok
    else
      {:error, :timestamp_out_of_tolerance}
    end
  end

  defp validate_signature(payload, timestamp, signatures, secret) do
    signed_payload = "#{timestamp}.#{payload}"

    expected =
      signed_payload
      |> then(&:crypto.mac(:hmac, :sha256, secret, &1))
      |> Base.encode16(case: :lower)

    if Enum.any?(signatures, &secure_compare(expected, &1)) do
      :ok
    else
      {:error, :signature_mismatch}
    end
  end

  defp secure_compare(a, b) when byte_size(a) == byte_size(b) do
    a
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(b))
    |> Enum.reduce(0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)
    |> Kernel.==(0)
  end

  defp secure_compare(_, _), do: false

  defp parse_header(header) do
    {timestamp, signatures} =
      header
      |> String.split(",", trim: true)
      |> Enum.reduce({nil, []}, fn part, {ts, sigs} ->
        trimmed_part = String.trim(part)

        case String.split(trimmed_part, "=", parts: 2) do
          ["t", value] -> {value, sigs}
          ["v1", value] -> {ts, [value | sigs]}
          _ -> {ts, sigs}
        end
      end)

    with true <- is_binary(timestamp) and timestamp != "",
         {int_ts, ""} <- Integer.parse(timestamp),
         true <- signatures != [] do
      {:ok, int_ts, signatures}
    else
      _ -> {:error, :invalid_header}
    end
  end
end
