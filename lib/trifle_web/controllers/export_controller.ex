defmodule TrifleWeb.ExportController do
  use TrifleWeb, :controller

  alias TrifleApp.Exporters.ChromeExporter
  alias Trifle.Organizations

  def dashboard_pdf(conn, %{"id" => id} = params) do
    # Basic access check: ensure dashboard exists (ownership/visibility can be added later)
    _ = Organizations.get_dashboard!(id)
    case ChromeExporter.export_dashboard_pdf(id) do
      {:ok, bin} when is_binary(bin) and byte_size(bin) > 0 ->
        filename = params["filename"] || default_filename("dashboard", id, ".pdf")
        send_download(conn, {:binary, bin}, filename: filename, content_type: "application/pdf")
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
    case ChromeExporter.export_dashboard_png(id) do
      {:ok, bin} when is_binary(bin) and byte_size(bin) > 0 ->
        filename = params["filename"] || default_filename("dashboard", id, ".png")
        send_download(conn, {:binary, bin}, filename: filename, content_type: "image/png")
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

  defp default_filename(prefix, id, ext) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)
    "#{prefix}-#{id}-#{ts}#{ext}"
  end
end

