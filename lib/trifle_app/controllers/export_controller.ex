defmodule TrifleApp.ExportController do
  use TrifleApp, :controller

  alias TrifleApp.Exporters.ChromeExporter
  alias Trifle.Exports.Series, as: SeriesExport
  alias TrifleApp.Exports.{DashboardLayout, MonitorLayout}
  alias Trifle.Monitors
  alias Trifle.Organizations
  alias TrifleApp.TimeframeParsing.Url, as: UrlParsing
  alias Trifle.Stats.Source
  alias Ecto.NoResultsError
  require Logger

  def dashboard_pdf(conn, %{"id" => id} = params) do
    export_params =
      Map.take(params, ["timeframe", "granularity", "from", "to", "segments", "key"])

    with {:ok, layout} <-
           DashboardLayout.build_from_id(id,
             params: export_params,
             theme: :light,
             viewport: %{width: 1920, height: 1080}
           ),
         {:ok, bin} <- ChromeExporter.export_layout_pdf(layout) do
      filename = params["filename"] || default_filename("dashboard", id, ".pdf")

      conn
      |> put_download_token_cookie(params)
      |> send_download({:binary, bin}, filename: filename, content_type: "application/pdf")
    else
      {:error, %NoResultsError{}} ->
        send_resp(conn, 404, "Dashboard not found")

      {:error, reason} ->
        send_resp(conn, error_status(reason), dashboard_error_message(reason))
    end
  end

  def dashboard_png(conn, %{"id" => id} = params) do
    theme =
      case params["theme"] do
        "dark" -> :dark
        _ -> :light
      end

    Logger.debug(
      "dashboard_png request id=#{id} theme=#{inspect(theme)} params=#{inspect(params)}"
    )

    export_params =
      Map.take(params, ["timeframe", "granularity", "from", "to", "segments", "key"])

    with {:ok, layout} <-
           DashboardLayout.build_from_id(id,
             params: export_params,
             theme: theme,
             viewport: %{width: 1366, height: 900}
           ),
         {:ok, bin} <- ChromeExporter.export_layout_png(layout, theme: theme) do
      filename =
        params["filename"] ||
          default_filename("dashboard-" <> Atom.to_string(theme), id, ".png")

      conn
      |> put_download_token_cookie(params)
      |> send_download({:binary, bin}, filename: filename, content_type: "image/png")
    else
      {:error, %NoResultsError{}} ->
        send_resp(conn, 404, "Dashboard not found")

      {:error, reason} ->
        send_resp(conn, error_status(reason), dashboard_error_message(reason))
    end
  end

  def dashboard_widget_pdf(conn, %{"id" => id, "widget_id" => widget_id} = params) do
    export_params =
      Map.take(params, ["timeframe", "granularity", "from", "to", "segments", "key"])

    case TrifleApp.Exports.DashboardLayout.build_widget_from_id(
           id,
           widget_id,
           params: export_params,
           theme: :light,
           viewport: %{width: 1920, height: 1080}
         ) do
      {:ok, layout} ->
        case ChromeExporter.export_layout_pdf(layout) do
          {:ok, bin} ->
            filename =
              params["filename"] ||
                default_widget_filename("dashboard-widget", id, widget_id, ".pdf")

            conn
            |> put_download_token_cookie(params)
            |> send_download({:binary, bin}, filename: filename, content_type: "application/pdf")

          {:error, reason} ->
            send_resp(conn, error_status(reason), widget_error_message(reason))
        end

      {:error, :widget_not_found} ->
        send_resp(conn, 404, "Widget not found")

      {:error, reason} ->
        send_resp(conn, error_status(reason), widget_error_message(reason))
    end
  end

  def dashboard_widget_png(conn, %{"id" => id, "widget_id" => widget_id} = params) do
    theme =
      case params["theme"] do
        "dark" -> :dark
        _ -> :light
      end

    Logger.debug(
      "dashboard_widget_png request id=#{id} widget=#{widget_id} theme=#{inspect(theme)} params=#{inspect(params)}"
    )

    export_params =
      Map.take(params, ["timeframe", "granularity", "from", "to", "segments", "key"])

    case TrifleApp.Exports.DashboardLayout.build_widget_from_id(
           id,
           widget_id,
           params: export_params,
           theme: theme
         ) do
      {:ok, layout} ->
        case ChromeExporter.export_layout_png(layout, theme: theme) do
          {:ok, bin} ->
            filename =
              params["filename"] ||
                default_widget_filename(
                  "dashboard-widget-" <> Atom.to_string(theme),
                  id,
                  widget_id,
                  ".png"
                )

            conn
            |> put_download_token_cookie(params)
            |> send_download({:binary, bin}, filename: filename, content_type: "image/png")

          {:error, reason} ->
            send_resp(conn, error_status(reason), widget_error_message(reason))
        end

      {:error, :widget_not_found} ->
        send_resp(conn, 404, "Widget not found")

      {:error, reason} ->
        send_resp(conn, error_status(reason), widget_error_message(reason))
    end
  end

  def dashboard_csv(conn, %{"id" => id} = params) do
    with {:ok, export} <- fetch_series_for_export(id, params) do
      csv = SeriesExport.to_csv(export)
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
    with {:ok, export} <- fetch_series_for_export(id, params) do
      json = SeriesExport.to_json(export)
      filename = params["filename"] || default_filename("dashboard", id, ".json")

      conn
      |> put_download_token_cookie(params)
      |> send_download({:binary, json}, filename: filename, content_type: "application/json")
    else
      {:error, :no_data} -> send_resp(conn, 400, "No data to export")
      {:error, reason} -> send_resp(conn, 500, "JSON export failed: #{inspect(reason)}")
    end
  end

  def monitor_pdf(conn, %{"id" => id} = params) do
    with {:ok, monitor} <- fetch_monitor(conn, id),
         export_params <- monitor_export_params(params),
         {:ok, layout} <-
           MonitorLayout.build(monitor,
             params: export_params,
             theme: :light,
             viewport: %{width: 1920, height: 1080}
           ),
         {:ok, bin} <- ChromeExporter.export_layout_pdf(layout) do
      filename =
        params["filename"] ||
          monitor_default_filename("monitor", monitor, ".pdf")

      conn
      |> put_download_token_cookie(params)
      |> send_download({:binary, bin}, filename: filename, content_type: "application/pdf")
    else
      {:error, :unauthorized} ->
        send_resp(conn, 403, "Unauthorized")

      {:error, :not_found} ->
        send_resp(conn, 404, "Monitor not found")

      {:error, reason} ->
        send_resp(conn, error_status(reason), monitor_error_message(reason))
    end
  end

  def monitor_png(conn, %{"id" => id} = params) do
    theme =
      case params["theme"] do
        "dark" -> :dark
        _ -> :light
      end

    Logger.debug("monitor_png request id=#{id} theme=#{inspect(theme)} params=#{inspect(params)}")

    with {:ok, monitor} <- fetch_monitor(conn, id),
         export_params <- monitor_export_params(params),
         {:ok, layout} <-
           MonitorLayout.build(monitor,
             params: export_params,
             theme: theme
           ),
         {:ok, bin} <- ChromeExporter.export_layout_png(layout, theme: theme) do
      filename =
        params["filename"] ||
          monitor_default_filename("monitor-" <> Atom.to_string(theme), monitor, ".png")

      conn
      |> put_download_token_cookie(params)
      |> send_download({:binary, bin}, filename: filename, content_type: "image/png")
    else
      {:error, :unauthorized} ->
        send_resp(conn, 403, "Unauthorized")

      {:error, :not_found} ->
        send_resp(conn, 404, "Monitor not found")

      {:error, reason} ->
        send_resp(conn, error_status(reason), monitor_error_message(reason))
    end
  end

  def monitor_widget_pdf(conn, %{"id" => id, "widget_id" => widget_id} = params) do
    with {:ok, monitor} <- fetch_monitor(conn, id),
         export_params <- monitor_export_params(params),
         {:ok, layout} <-
           MonitorLayout.build_widget(monitor, widget_id,
             params: export_params,
             theme: :light,
             viewport: %{width: 1920, height: 1080}
           ),
         {:ok, bin} <- ChromeExporter.export_layout_pdf(layout) do
      filename =
        params["filename"] ||
          monitor_widget_filename("monitor-widget", monitor, widget_id, ".pdf")

      conn
      |> put_download_token_cookie(params)
      |> send_download({:binary, bin}, filename: filename, content_type: "application/pdf")
    else
      {:error, :unauthorized} ->
        send_resp(conn, 403, "Unauthorized")

      {:error, :not_found} ->
        send_resp(conn, 404, "Monitor not found")

      {:error, :widget_not_found} ->
        send_resp(conn, 404, "Widget not found")

      {:error, reason} ->
        send_resp(conn, error_status(reason), widget_error_message(reason))
    end
  end

  def monitor_widget_png(conn, %{"id" => id, "widget_id" => widget_id} = params) do
    theme =
      case params["theme"] do
        "dark" -> :dark
        _ -> :light
      end

    Logger.debug(
      "monitor_widget_png request id=#{id} widget=#{widget_id} theme=#{inspect(theme)} params=#{inspect(params)}"
    )

    with {:ok, monitor} <- fetch_monitor(conn, id),
         export_params <- monitor_export_params(params),
         {:ok, layout} <-
           MonitorLayout.build_widget(monitor, widget_id,
             params: export_params,
             theme: theme
           ),
         {:ok, bin} <- ChromeExporter.export_layout_png(layout, theme: theme) do
      filename =
        params["filename"] ||
          monitor_widget_filename(
            "monitor-widget-" <> Atom.to_string(theme),
            monitor,
            widget_id,
            ".png"
          )

      conn
      |> put_download_token_cookie(params)
      |> send_download({:binary, bin}, filename: filename, content_type: "image/png")
    else
      {:error, :unauthorized} ->
        send_resp(conn, 403, "Unauthorized")

      {:error, :not_found} ->
        send_resp(conn, 404, "Monitor not found")

      {:error, :widget_not_found} ->
        send_resp(conn, 404, "Widget not found")

      {:error, reason} ->
        send_resp(conn, error_status(reason), widget_error_message(reason))
    end
  end

  defp fetch_series_for_export(dashboard_id, params) do
    dashboard = Organizations.get_dashboard!(dashboard_id)

    source =
      case dashboard.source_type do
        "project" ->
          Source.from_project(
            Organizations.get_project_for_org!(dashboard.organization_id, dashboard.source_id)
          )

        _ ->
          Source.from_database(Organizations.get_database!(dashboard.source_id))
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

    SeriesExport.fetch(
      source,
      resolved_key,
      from,
      to,
      granularity,
      progress_callback: nil
    )
  end

  defp resolved_key_from_params(dashboard, params) do
    case Map.get(params, "key") do
      key when is_binary(key) and key != "" -> key
      _ -> dashboard.key || ""
    end
  end

  defp default_filename(prefix, id, ext) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)
    "#{prefix}-#{id}-#{ts}#{ext}"
  end

  defp default_widget_filename(prefix, dashboard_id, widget_id, ext) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)

    base =
      [prefix, dashboard_id, widget_id]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&sanitize_filename_component/1)
      |> Enum.join("-")

    if base == "" do
      "#{prefix}-#{ts}#{ext}"
    else
      base <> "-" <> ts <> ext
    end
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

  defp fetch_monitor(conn, id) do
    membership = conn.assigns[:current_membership]

    cond do
      is_nil(membership) ->
        {:error, :unauthorized}

      true ->
        try do
          {:ok, Monitors.get_monitor_for_membership!(membership, id, preload: [:dashboard])}
        rescue
          NoResultsError -> {:error, :not_found}
        end
    end
  end

  defp monitor_export_params(params) do
    Map.take(params, ["timeframe", "granularity", "from", "to", "segments", "key"])
  end

  defp monitor_default_filename(prefix, monitor, ext) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)

    base =
      [prefix, monitor.name]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&sanitize_filename_component/1)
      |> Enum.join("-")

    if base == "" do
      prefix <> "-" <> ts <> ext
    else
      base <> "-" <> ts <> ext
    end
  end

  defp monitor_widget_filename(prefix, monitor, widget_id, ext) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)

    base =
      [prefix, monitor.name, widget_id]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&sanitize_filename_component/1)
      |> Enum.join("-")

    if base == "" do
      prefix <> "-" <> ts <> ext
    else
      base <> "-" <> ts <> ext
    end
  end

  defp sanitize_filename_component(value) do
    value
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")
  end

  defp dashboard_error_message(:no_widgets), do: "Dashboard has no widgets to export"
  defp dashboard_error_message(:no_data), do: "No data to export"
  defp dashboard_error_message(:chrome_not_found), do: "Chrome binary not found"

  defp dashboard_error_message({:error, reason}),
    do: "Dashboard export failed: #{inspect(reason)}"

  defp dashboard_error_message(reason), do: "Dashboard export failed: #{inspect(reason)}"

  defp monitor_error_message(:no_widgets), do: "Monitor has no widgets to export"
  defp monitor_error_message(:widget_not_found), do: "Widget not found"
  defp monitor_error_message(:no_data), do: "No data to export"
  defp monitor_error_message(:source_not_configured), do: "Monitor source is not configured"
  defp monitor_error_message(:source_not_found), do: "Monitor source could not be found"
  defp monitor_error_message(:chrome_not_found), do: "Chrome binary not found"
  defp monitor_error_message({:error, reason}), do: "Monitor export failed: #{inspect(reason)}"
  defp monitor_error_message(reason), do: "Monitor export failed: #{inspect(reason)}"

  defp widget_error_message(:widget_not_found), do: "Widget not found"
  defp widget_error_message(:no_widgets), do: "Widget not found"
  defp widget_error_message(:chrome_not_found), do: "Chrome binary not found"
  defp widget_error_message({:error, reason}), do: "Widget export failed: #{inspect(reason)}"
  defp widget_error_message(reason), do: "Widget export failed: #{inspect(reason)}"

  defp error_status({:error, _}), do: 500
  defp error_status(:chrome_not_found), do: 500
  defp error_status(:source_not_found), do: 404
  defp error_status(:no_widgets), do: 400
  defp error_status(:no_data), do: 400
  defp error_status(:source_not_configured), do: 400
  defp error_status(:widget_not_found), do: 404
  defp error_status(_), do: 500
end
