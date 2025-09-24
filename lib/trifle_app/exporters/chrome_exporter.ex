defmodule TrifleApp.Exporters.ChromeExporter do
  @moduledoc """
  Server-side export of Dashboard pages to PDF or PNG using a headless Chrome binary.

  This uses a single engine (Chromium/Chrome) for both PDF and image exports, so the
  output looks the same and JS charts render faithfully.

  Configure the Chrome binary via the CHROME_PATH env var or rely on common defaults
  like "google-chrome", "chromium", or "chromium-browser" being available in PATH.
  """

  alias Trifle.Organizations
  alias TrifleWeb.Endpoint
  require Logger

  @default_window_size {1366, 900}
  @default_pdf_window_size {1920, 1080}
  @default_budget_ms 10000

  @doc """
  Export the dashboard to a PDF. Returns {:ok, binary} or {:error, reason}.
  """
  def export_dashboard_pdf(dashboard_id, opts \\ []) do
    with {:ok, url, cleanup} <-
           public_url_for_dashboard(dashboard_id, Keyword.merge([print: true], opts)),
         # Prefer CDP (wait-for-ready) exporter for determinism
         {:ok, bin} <- TrifleApp.Exporters.ChromeCDP.export_pdf(url, opts) do
      cleanup.()
      {:ok, bin}
    else
      {:error, reason} ->
        Logger.warn("ChromeExporter CDP PDF failed: #{inspect(reason)} — falling back to CLI")
        # Fallback to CLI flags
        with {:ok, url, cleanup} <-
               public_url_for_dashboard(dashboard_id, Keyword.merge([print: true], opts)),
             {:ok, chrome} <- find_chrome_binary(),
             {:ok, tmpfile} <- tmp_path(".pdf"),
             _ = Logger.debug("ChromeExporter PDF start url=#{url} out=#{tmpfile}"),
             {:ok, _} <- run_chrome(chrome, :pdf, url, tmpfile, opts),
             {:ok, bin} <- File.read(tmpfile) do
          Logger.debug("ChromeExporter PDF ok size=#{byte_size(bin)} url=#{url} out=#{tmpfile}")
          File.rm(tmpfile)
          cleanup.()
          {:ok, bin}
        else
          {:error, reason} = err -> err
          other -> {:error, other}
        end
    end
  end

  @doc """
  Export the dashboard to a PNG screenshot. Returns {:ok, binary} or {:error, reason}.
  """
  def export_dashboard_png(dashboard_id, opts \\ []) do
    with {:ok, url, cleanup} <-
           public_url_for_dashboard(dashboard_id, Keyword.merge([print: true], opts)),
         {:ok, bin} <- TrifleApp.Exporters.ChromeCDP.export_png(url, opts) do
      cleanup.()
      {:ok, bin}
    else
      {:error, reason} ->
        Logger.warn("ChromeExporter CDP PNG failed: #{inspect(reason)} — falling back to CLI")

        with {:ok, url, cleanup} <-
               public_url_for_dashboard(dashboard_id, Keyword.merge([print: true], opts)),
             {:ok, chrome} <- find_chrome_binary(),
             {:ok, tmpfile} <- tmp_path(".png"),
             _ = Logger.debug("ChromeExporter PNG start url=#{url} out=#{tmpfile}"),
             {:ok, _} <- run_chrome(chrome, :png, url, tmpfile, opts),
             {:ok, bin} <- File.read(tmpfile) do
          File.rm(tmpfile)
          cleanup.()
          {:ok, bin}
        else
          {:error, reason} = err -> err
          other -> {:error, other}
        end
    end
  end

  defp public_url_for_dashboard(dashboard_id, opts) do
    dashboard = Organizations.get_dashboard!(dashboard_id)
    token_was_nil = is_nil(dashboard.access_token)

    {:ok, dashboard} =
      if token_was_nil do
        Organizations.generate_dashboard_public_token(dashboard)
      else
        {:ok, dashboard}
      end

    base = base_url()
    # Use the public route so no auth is required for headless export
    base_params = %{
      "token" => dashboard.access_token,
      "print" => if(opts[:print], do: "1", else: nil)
    }

    extra_params =
      (opts[:params] || %{})
      |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)

    query_params =
      Map.merge(base_params, extra_params)
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        cond do
          is_nil(value) -> acc
          value == "" -> acc
          is_map(value) and map_size(value) == 0 -> acc
          true -> Map.put(acc, key, value)
        end
      end)

    query = Plug.Conn.Query.encode(query_params)
    url = base <> "/d/" <> dashboard.id <> if(query == "", do: "", else: "?" <> query)

    cleanup = fn ->
      if token_was_nil do
        # Best-effort removal of the temporary token
        Organizations.remove_dashboard_public_token(dashboard)
      end
    end

    {:ok, url, cleanup}
  end

  defp base_url do
    base = Endpoint.url()
    uri = URI.parse(base)

    port =
      cond do
        is_integer(uri.port) and uri.port > 0 -> uri.port
        true -> endpoint_port() || 4000
      end

    # Ensure we always have explicit port and a loopback host (avoid 0.0.0.0)
    host =
      case uri.host do
        nil -> System.get_env("PHX_HOST") || "localhost"
        "0.0.0.0" -> "127.0.0.1"
        "::" -> "127.0.0.1"
        "0:0:0:0:0:0:0:0" -> "127.0.0.1"
        other -> other
      end

    %URI{uri | port: port, scheme: uri.scheme || "http", host: host}
    |> URI.to_string()
  end

  defp endpoint_port do
    try do
      case Endpoint.config(:http) do
        list when is_list(list) -> Keyword.get(list, :port)
        _ -> nil
      end
    rescue
      _ -> nil
    end
  end

  defp tmp_path(ext) do
    {:ok, Path.join(System.tmp_dir!(), unique("trifle_export") <> ext)}
  end

  defp unique(prefix) do
    {m, s, us} = :os.timestamp()

    :crypto.hash(:sha256, "#{prefix}-#{m}-#{s}-#{us}-#{:rand.uniform()}")
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 12)
  end

  def find_chrome_binary do
    candidates =
      [
        System.get_env("CHROME_PATH"),
        "google-chrome-stable",
        "google-chrome",
        "chromium",
        "chromium-browser"
      ]
      |> Enum.reject(&is_nil/1)

    case Enum.find(candidates, &System.find_executable/1) do
      nil -> {:error, :chrome_not_found}
      bin -> {:ok, bin}
    end
  end

  # Public helper to obtain Chrome path for debug flows
  def chrome_path, do: find_chrome_binary()

  # Public helper to build the public dashboard URL for debugging
  def public_dashboard_url(dashboard_id, opts \\ []),
    do: public_url_for_dashboard(dashboard_id, opts)

  defp run_chrome(chrome_bin, :pdf, url, out_path, opts) do
    {w, h} = Keyword.get(opts, :window_size, @default_pdf_window_size)
    budget = Keyword.get(opts, :virtual_time_budget, @default_budget_ms)

    # Minimal, proven-stable flags first
    args_min = [
      "--headless=new",
      "--disable-gpu",
      "--no-sandbox",
      "--hide-scrollbars",
      "--disable-crash-reporter",
      "--no-crashpad",
      "--disable-logging",
      "--log-level=3",
      "--window-size=#{w},#{h}",
      "--virtual-time-budget=#{budget}",
      "--print-to-pdf=#{out_path}",
      "--print-to-pdf-no-header",
      url
    ]

    Logger.debug(
      "ChromeExporter run (pdf:min) bin=#{inspect(chrome_bin)} args=#{inspect(args_min)}"
    )

    case run_cmd(chrome_bin, args_min) do
      {:ok, out1} ->
        case ensure_non_empty_file(out_path, out1) do
          :ok ->
            {:ok, out1}

          {:empty_file, _} ->
            # Fallback: legacy headless
            args_legacy = List.replace_at(args_min, 0, "--headless")
            Logger.debug("ChromeExporter retry legacy headless (pdf)")

            case run_cmd(chrome_bin, args_legacy) do
              {:ok, out2} ->
                case ensure_non_empty_file(out_path, out2) do
                  :ok ->
                    {:ok, out2}

                  {:empty_file, out2} ->
                    _ = debug_dump_dom(chrome_bin, url)
                    {:error, {:empty_pdf, out2}}
                end

              {:error, _} = err2 ->
                err2
            end
        end

      {:error, _} = err ->
        err
    end
  end

  defp run_chrome(chrome_bin, :png, url, out_path, opts) do
    {w, h} = Keyword.get(opts, :window_size, @default_window_size)
    budget = Keyword.get(opts, :virtual_time_budget, @default_budget_ms)

    args_min = [
      "--headless=new",
      "--disable-gpu",
      "--no-sandbox",
      "--hide-scrollbars",
      "--disable-crash-reporter",
      "--no-crashpad",
      "--disable-logging",
      "--log-level=3",
      "--window-size=#{w},#{h}",
      "--virtual-time-budget=#{budget}",
      "--screenshot=#{out_path}",
      url
    ]

    Logger.debug(
      "ChromeExporter run (png:min) bin=#{inspect(chrome_bin)} args=#{inspect(args_min)}"
    )

    case run_cmd(chrome_bin, args_min) do
      {:ok, out1} ->
        case ensure_non_empty_file(out_path, out1) do
          :ok ->
            {:ok, out1}

          {:empty_file, _} ->
            args_legacy = List.replace_at(args_min, 0, "--headless")
            Logger.debug("ChromeExporter retry legacy headless (png)")

            case run_cmd(chrome_bin, args_legacy) do
              {:ok, out2} ->
                case ensure_non_empty_file(out_path, out2) do
                  :ok ->
                    {:ok, out2}

                  {:empty_file, out2} ->
                    _ = debug_dump_dom(chrome_bin, url)
                    {:error, {:empty_png, out2}}
                end

              {:error, _} = err2 ->
                err2
            end
        end

      {:error, _} = err ->
        err
    end
  end

  defp run_cmd(bin, args) do
    case System.cmd(bin, args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, status} -> {:error, {status, out}}
    end
  end

  defp ensure_non_empty_file(path, out) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} when size > 0 -> :ok
      {:ok, %File.Stat{size: 0}} -> {:empty_file, out}
      {:error, _} -> {:empty_file, out}
    end
  end

  defp debug_dump_dom(chrome_bin, url) do
    # Best-effort DOM dump to debug what Chrome actually loads
    args = ["--headless=new", "--disable-gpu", "--no-sandbox", "--dump-dom", url]
    Logger.debug("ChromeExporter DOM dump attempt")

    case System.cmd(chrome_bin, args, stderr_to_stdout: true) do
      {out, 0} ->
        Logger.debug("ChromeExporter DOM dump size=#{byte_size(out)}")
        :ok

      {out, status} ->
        Logger.debug("ChromeExporter DOM dump failed status=#{status} out=#{out}")
        :error
    end
  end
end
