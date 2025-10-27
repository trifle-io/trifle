defmodule TrifleApp.Exporters.ChromeExporter do
  @moduledoc """
  Server-side export of Dashboard pages to PDF or PNG using a headless Chrome binary.

  This uses a single engine (Chromium/Chrome) for both PDF and image exports, so the
  output looks the same and JS charts render faithfully.

  Configure the Chrome binary via the CHROME_PATH env var or rely on common defaults
  like "google-chrome", "chromium", or "chromium-browser" being available in PATH.
  """

  alias TrifleApp.Exports.{Layout, LayoutSession}
  alias TrifleWeb.Endpoint

  @default_window_size {1366, 900}
  @default_pdf_window_size {1920, 1080}
  @doc """
  Exports a pre-built layout to PDF.
  """
  def export_layout_pdf(%Layout{} = layout, opts \\ []) do
    export_layout(:pdf, layout, opts)
  end

  @doc """
  Exports a pre-built layout to PNG.
  """
  def export_layout_png(%Layout{} = layout, opts \\ []) do
    export_layout(:png, layout, opts)
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

  defp export_layout(:pdf, layout, opts) do
    opts =
      Keyword.put_new(
        opts,
        :window_size,
        window_size_from_layout(layout, @default_pdf_window_size)
      )

    with {:ok, url, cleanup} <- layout_export_url(layout, opts) do
      try do
        TrifleApp.Exporters.ChromeCDP.export_pdf(url, opts)
      after
        cleanup.()
      end
    end
  end

  defp export_layout(:png, layout, opts) do
    opts =
      Keyword.put_new(opts, :window_size, window_size_from_layout(layout, @default_window_size))

    with {:ok, url, cleanup} <- layout_export_url(layout, opts) do
      try do
        TrifleApp.Exporters.ChromeCDP.export_png(url, opts)
      after
        cleanup.()
      end
    end
  end

  defp layout_export_url(layout, opts) do
    ttl = Keyword.get(opts, :token_ttl, 120_000)
    token = LayoutSession.sign(layout, ttl: ttl)
    base = base_url()
    url = base <> "/export/layouts/" <> token

    cleanup = fn ->
      _ = LayoutSession.consume(token)
      :ok
    end

    {:ok, url, cleanup}
  end

  defp viewport_from_size({w, h}) when is_integer(w) and is_integer(h) do
    %{width: w, height: h}
  end

  defp viewport_from_size(_), do: %{width: 1366, height: 900}

  defp window_size_from_layout(%Layout{viewport: %{width: w, height: h}}, default)
       when is_integer(w) and is_integer(h) do
    {w, h}
  end

  defp window_size_from_layout(_layout, default), do: default
end
