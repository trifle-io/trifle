defmodule TrifleApp.CspReportController do
  @moduledoc """
  Receives Content-Security-Policy violation reports from browsers and logs
  them. See `TrifleWeb.Plugs.ContentSecurityPolicy`.

  The endpoint is unauthenticated and everything in a report is chosen by the
  sender, so:

    * the body is limited to 16 KB before it is parsed (`TrifleWeb.DynamicParsers`)
    * requests are rate limited per client
    * every field is type-checked, cut to a short single line, and URLs lose
      their query string and fragment (public dashboard links carry a token)
    * each distinct violation is logged at most once an hour, and at most
      `:csp_report_log` distinct violations are logged per hour in total; the
      de-duplication key is a fixed-size digest, so neither the log nor the
      cache can be grown by sending varied reports
  """

  use TrifleApp, :controller

  require Logger

  plug TrifleWeb.Plugs.RateLimit, policy: :csp_report

  @max_body_bytes 16_384
  @dedupe_ttl_ms :timer.hours(1)
  @max_reports_per_request 10
  @max_field_length 200
  @max_line 10_000_000

  def create(conn, params) do
    conn
    |> reports(params)
    |> Enum.take(@max_reports_per_request)
    |> Enum.each(&log_once/1)

    send_resp(conn, :no_content, "")
  end

  # `report-to` (Reporting API): a JSON array, already parsed into "_json".
  defp reports(_conn, %{"_json" => list}) when is_list(list) do
    for %{"body" => %{} = body} <- Enum.take(list, @max_reports_per_request), do: normalize(body)
  end

  # `report-uri` sent as application/json.
  defp reports(_conn, %{"csp-report" => %{} = body}), do: [normalize(body)]

  # `report-uri` with its usual content type, application/csp-report, which the
  # JSON parser does not claim: the body is still unread.
  defp reports(conn, _params) do
    with {:ok, raw, _conn} <- Plug.Conn.read_body(conn, length: @max_body_bytes),
         {:ok, %{"csp-report" => %{} = body}} <- Jason.decode(raw) do
      [normalize(body)]
    else
      _ -> []
    end
  end

  defp normalize(body) do
    %{
      directive:
        clean(
          body["effective-directive"] || body["effectiveDirective"] || body["violated-directive"]
        ),
      blocked: bare_url(body["blocked-uri"] || body["blockedURL"]),
      document: bare_url(body["document-uri"] || body["documentURL"]),
      source: bare_url(body["source-file"] || body["sourceFile"]),
      line: line(body["line-number"] || body["lineNumber"]),
      sample: clean(body["script-sample"] || body["sample"], 80)
    }
  end

  defp log_once(report) do
    digest =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({report.directive, report.blocked, report.source, report.line})
      )

    key = {:csp_report, digest}

    with :error <- Trifle.Cache.get(key),
         :ok <- Trifle.RateLimit.check(:csp_report_log, :node) do
      Trifle.Cache.put(key, true, @dedupe_ttl_ms)

      Logger.warning(
        "[CSP] would block #{report.directive} #{report.blocked} on #{report.document}" <>
          " (source #{report.source}:#{inspect(report.line)}, sample #{inspect(report.sample)})"
      )
    end

    :ok
  end

  defp clean(value, max \\ @max_field_length)

  defp clean(value, max) when is_binary(value) do
    if String.valid?(value) do
      value |> String.replace(~r/[[:cntrl:]]+/u, " ") |> String.slice(0, max)
    else
      ""
    end
  end

  defp clean(_value, _max), do: ""

  # Browsers put a URL here, or a keyword such as "inline" or "eval". Anything
  # after "?" or "#" is dropped either way.
  defp bare_url(value) when is_binary(value) do
    value |> String.split(["?", "#"], parts: 2) |> hd() |> clean()
  end

  defp bare_url(_), do: ""

  defp line(value) when is_integer(value) and value >= 0 and value <= @max_line, do: value
  defp line(_), do: nil
end
