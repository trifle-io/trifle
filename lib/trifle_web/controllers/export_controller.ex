defmodule TrifleWeb.ExportController do
  use TrifleWeb, :controller

  alias TrifleApp.Exporters.ChromeExporter
  alias Trifle.Organizations
  alias TrifleApp.TimeframeParsing
  alias TrifleApp.TimeframeParsing.Url, as: UrlParsing
  alias Trifle.Stats.SeriesFetcher
  alias Trifle.Stats.Source
  alias Trifle.Stats.Tabler

  def dashboard_pdf(conn, %{"id" => id} = params) do
    # Basic access check: ensure dashboard exists (ownership/visibility can be added later)
    _ = Organizations.get_dashboard!(id)

    export_params =
      Map.take(params, ["timeframe", "granularity", "from", "to", "segments", "key"])

    case ChromeExporter.export_dashboard_pdf(id, params: export_params) do
      {:ok, bin} when is_binary(bin) and byte_size(bin) > 0 ->
        filename = params["filename"] || default_filename("dashboard", id, ".pdf")

        conn
        |> put_download_token_cookie(params)
        |> send_download({:binary, bin}, filename: filename, content_type: "application/pdf")

      {:ok, _} ->
        send_resp(conn, 500, "Empty PDF output")

      {:error, :chrome_not_found} ->
        send_resp(conn, 500, "Chrome binary not found")

      {:error, {_status, out}} ->
        send_resp(conn, 500, "PDF export failed: #{out}")

      {:error, reason} ->
        send_resp(conn, 500, "PDF export failed: #{inspect(reason)}")
    end
  end

  def dashboard_png(conn, %{"id" => id} = params) do
    _ = Organizations.get_dashboard!(id)

    theme =
      case params["theme"] do
        "dark" -> :dark
        _ -> :light
      end

    export_params =
      Map.take(params, ["timeframe", "granularity", "from", "to", "segments", "key"])

    case ChromeExporter.export_dashboard_png(id, theme: theme, params: export_params) do
      {:ok, bin} when is_binary(bin) and byte_size(bin) > 0 ->
        filename =
          params["filename"] ||
            default_filename("dashboard-" <> ((theme == :dark && "dark") || "light"), id, ".png")

        conn
        |> put_download_token_cookie(params)
        |> send_download({:binary, bin}, filename: filename, content_type: "image/png")

      {:ok, _} ->
        send_resp(conn, 500, "Empty PNG output")

      {:error, :chrome_not_found} ->
        send_resp(conn, 500, "Chrome binary not found")

      {:error, {_status, out}} ->
        send_resp(conn, 500, "PNG export failed: #{out}")

      {:error, reason} ->
        send_resp(conn, 500, "PNG export failed: #{inspect(reason)}")
    end
  end

  def dashboard_csv(conn, %{"id" => id} = params) do
    with {:ok, series} <- fetch_series_for_export(id, params) do
      csv = series_to_csv(series)
      filename = params["filename"] || default_filename("dashboard", id, ".csv")

      conn
      |> put_download_token_cookie(params)
      |> send_download({:binary, csv}, filename: filename, content_type: "text/csv")
    else
      {:error, :no_data} -> send_resp(conn, 400, "No data to export")
      {:error, reason} -> send_resp(conn, 500, "CSV export failed: #{inspect(reason)}")
    end
  end

  def dashboard_json(conn, %{"id" => id} = params) do
    with {:ok, series} <- fetch_series_for_export(id, params) do
      at = (series[:at] || []) |> Enum.map(&DateTime.to_iso8601/1)
      values = series[:values] || []
      json = Jason.encode!(%{at: at, values: values})
      filename = params["filename"] || default_filename("dashboard", id, ".json")

      conn
      |> put_download_token_cookie(params)
      |> send_download({:binary, json}, filename: filename, content_type: "application/json")
    else
      {:error, :no_data} -> send_resp(conn, 400, "No data to export")
      {:error, reason} -> send_resp(conn, 500, "JSON export failed: #{inspect(reason)}")
    end
  end

  defp fetch_series_for_export(dashboard_id, params) do
    dashboard = Organizations.get_dashboard!(dashboard_id)

    source =
      case dashboard.source_type do
        "project" -> Source.from_project(Organizations.get_project!(dashboard.source_id))
        _ -> Source.from_database(Organizations.get_database!(dashboard.source_id))
      end
    config = Source.stats_config(source)
    available_granularities = Source.available_granularities(source)

    defaults = %{
      default_timeframe: dashboard.default_timeframe || Source.default_timeframe(source) || "24h",
      default_granularity:
        dashboard.default_granularity || Source.default_granularity(source) || "1h"
    }

    {from, to, granularity, _smart, _use_fixed} =
      UrlParsing.parse_url_params(params, config, available_granularities, defaults)

    resolved_key = resolved_key_from_params(dashboard, params)

    matching_transponders =
      Source.transponders(source)
      |> Enum.filter(& &1.enabled)
      |> Enum.filter(fn t -> key_matches_pattern?(t.key, resolved_key) end)
      |> Enum.sort_by(& &1.order)

    case SeriesFetcher.fetch_series(
           source,
           resolved_key,
           from,
           to,
           granularity,
           matching_transponders,
           progress_callback: nil
         ) do
      {:ok, result} ->
        s = normalize_series(result.series)

        if is_map(s) and (s[:at] || []) != [] do
          {:ok, s}
        else
          {:error, :no_data}
        end

      other ->
        other
    end
  end

  defp key_matches_pattern?(pattern, key) when is_binary(pattern) and is_binary(key) do
    if String.contains?(pattern, "^") or String.contains?(pattern, "$") do
      case Regex.compile(pattern) do
        {:ok, regex} -> Regex.match?(regex, key)
        _ -> false
      end
    else
      pattern == key
    end
  end

  defp resolved_key_from_params(dashboard, params) do
    case Map.get(params, "key") do
      key when is_binary(key) and key != "" -> key
      _ -> dashboard.key || ""
    end
  end

  defp series_to_csv(series) do
    # Accept either a plain series map (%{at: [], values: []}) or a Trifle.Stats.Series struct
    series_map = normalize_series(series)
    table = Tabler.tabulize(series_map)
    at = Enum.reverse(table[:at] || [])
    paths = table[:paths] || []
    values_map = table[:values] || %{}
    header = ["Path" | Enum.map(at, &DateTime.to_iso8601/1)]

    rows =
      Enum.map(paths, fn path ->
        [path | Enum.map(at, fn t -> Map.get(values_map, {path, t}) || 0 end)]
      end)

    to_csv([header | rows])
  end

  defp normalize_series(%Trifle.Stats.Series{series: inner}) when is_map(inner), do: inner
  defp normalize_series(%{} = series_map), do: series_map
  defp normalize_series(other), do: other

  defp to_csv(rows) do
    rows
    |> Enum.map(fn cols -> cols |> Enum.map(&csv_escape/1) |> Enum.join(",") end)
    |> Enum.join("\n")
  end

  defp csv_escape(v) when is_binary(v) do
    escaped = String.replace(v, "\"", "\"\"")
    "\"" <> escaped <> "\""
  end

  defp csv_escape(nil), do: ""
  defp csv_escape(v) when is_integer(v) or is_float(v), do: to_string(v)
  defp csv_escape(v), do: csv_escape(to_string(v))

  defp default_filename(prefix, id, ext) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)
    "#{prefix}-#{id}-#{ts}#{ext}"
  end

  defp put_download_token_cookie(conn, params) do
    token =
      case Map.get(params, "download_token") do
        token when is_binary(token) and token != "" -> token
        _ -> Integer.to_string(System.system_time(:millisecond))
      end

    Plug.Conn.put_resp_cookie(conn, "download_token", token,
      max_age: 60,
      http_only: false,
      path: "/"
    )
  end
end
