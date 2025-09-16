defmodule TrifleApp.Exporters.ChromeCDP do
  @moduledoc """
  Minimal Chrome DevTools Protocol exporter for waiting on page readiness
  (window.TRIFLE_READY) and capturing PDF/PNG deterministically.

  This module launches a headless Chrome with a remote debugging port,
  opens the target page, waits until a readiness expression evaluates
  to true, then calls Page.printToPDF or Page.captureScreenshot.
  """

  alias TrifleApp.Exporters.ChromeExporter
  require Logger

  @default_pdf_opts %{
    landscape: false,
    printBackground: false,
    # Explicit A3 portrait sizing to preserve grid layout
    paperWidth: 11.69,   # inches
    paperHeight: 16.54,  # inches
    # ~8mm margins
    marginTop: 0.33,
    marginBottom: 0.33,
    marginLeft: 0.33,
    marginRight: 0.33
  }
  @default_viewport {1366, 900}
  @default_pdf_viewport {1920, 1080}
  @default_timeout_ms 30000

  def export_pdf(url, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    pdf_base = Map.merge(@default_pdf_opts, Map.new(Keyword.get(opts, :pdf, [])))
    # Derive viewport from printable CSS area to avoid Chrome auto-scaling
    pw = Map.get(pdf_base, :paperWidth, 8.27)
    ph = Map.get(pdf_base, :paperHeight, 11.69)
    mt = Map.get(pdf_base, :marginTop, 0.4)
    mb = Map.get(pdf_base, :marginBottom, 0.4)
    ml = Map.get(pdf_base, :marginLeft, 0.4)
    mr = Map.get(pdf_base, :marginRight, 0.4)
    printable_w_in = max(pw - ml - mr, 1.0)
    printable_h_in = max(ph - mt - mb, 1.0)
    w = trunc(printable_w_in * 96.0)
    h = max(trunc(printable_h_in * 96.0), 800)
    with {:ok, chrome} <- ChromeExporter.find_chrome_binary(),
         _ = Logger.debug("CDP export_pdf launch bin=#{chrome} viewport=#{w}x#{h}"),
         {:ok, state} <- launch_chrome(chrome, w, h),
         {:ok, page_ws} <- open_page_ws(state, url),
         :ok <- wait_until_ready(page_ws, timeout_ms),
         _ = __MODULE__.WS.call(page_ws, "Emulation.setEmulatedMedia", %{media: "screen"}),
         _ = normalize_background(page_ws),
         {:ok, pdf_b64} <- page_print_to_pdf(page_ws, pdf_base) do
      _ = close(page_ws)
      _ = kill_chrome(state)
      Logger.debug("CDP PDF captured (bytes)=#{div(byte_size(pdf_b64) * 3, 4)}")
      {:ok, Base.decode64!(pdf_b64)}
    else
      {:error, reason} = err ->
        Logger.warn("CDP export_pdf failed: #{inspect(reason)}")
        err
    end
  end

  # no-op placeholder (kept for potential future tuning)

  def export_png(url, opts \\ []) do
    {w, h} = Keyword.get(opts, :window_size, @default_viewport)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    theme = Keyword.get(opts, :theme, :light)
    with {:ok, chrome} <- ChromeExporter.find_chrome_binary(),
         _ = Logger.debug("CDP export_png launch bin=#{chrome} viewport=#{w}x#{h}"),
         {:ok, state} <- launch_chrome(chrome, w, h),
         {:ok, page_ws} <- open_page_ws(state, url),
         :ok <- wait_until_ready(page_ws, timeout_ms),
         _ = __MODULE__.WS.call(page_ws, "Emulation.setEmulatedMedia", %{media: "screen"}),
         _ = (theme == :dark && set_dark_theme(page_ws) || normalize_background(page_ws)),
         clip <- expand_viewport_to_content(page_ws),
         {:ok, png_b64} <- page_capture_screenshot(page_ws, clip) do
      _ = close(page_ws)
      _ = kill_chrome(state)
      Logger.debug("CDP PNG captured (bytes)=#{div(byte_size(png_b64) * 3, 4)}")
      {:ok, Base.decode64!(png_b64)}
    else
      {:error, reason} = err ->
        Logger.warn("CDP export_png failed: #{inspect(reason)}")
        err
    end
  end

  # --- Chrome launch + discovery ---

  defp launch_chrome(chrome_bin, w, h) do
    profile_dir = Path.join(System.tmp_dir!(), unique("trifle_cdp_profile"))
    File.mkdir_p!(profile_dir)
    args = [
      "--headless=new",
      "--disable-gpu",
      "--no-sandbox",
      "--hide-scrollbars",
      "--remote-debugging-address=127.0.0.1",
      "--remote-debugging-port=0",
      "--user-data-dir=#{profile_dir}",
      "--window-size=#{w},#{h}"
    ]

    # Start chrome detached; we won't read stdout, we will poll the /json endpoints
    port_ref = Port.open({:spawn_executable, chrome_bin}, [
      :binary,
      {:line, 4096},
      :exit_status,
      args: args
    ])

    # Discover dynamically chosen devtools port via DevToolsActivePort file
    case wait_for_devtools_port(profile_dir, 100) do
      {:ok, port} ->
        case wait_for_ws_browser(port, 50) do
          {:ok, browser_ws_url} -> {:ok, %{port_ref: port_ref, browser_ws: browser_ws_url, http_port: port, profile_dir: profile_dir}}
          {:error, reason} ->
            _ = File.rm_rf(profile_dir)
            {:error, reason}
        end
      {:error, reason} ->
        _ = File.rm_rf(profile_dir)
        {:error, reason}
    end
  end

  defp wait_for_devtools_port(profile_dir, tries) when tries > 0 do
    file = Path.join(profile_dir, "DevToolsActivePort")
    case File.read(file) do
      {:ok, contents} ->
        [port_line | _] = String.split(contents, "\n", trim: true)
        case Integer.parse(port_line) do
          {port, _} -> {:ok, port}
          :error -> :timer.sleep(100); wait_for_devtools_port(profile_dir, tries - 1)
        end
      {:error, _} -> :timer.sleep(100); wait_for_devtools_port(profile_dir, tries - 1)
    end
  end
  defp wait_for_devtools_port(_profile_dir, _tries), do: {:error, :devtools_port_not_found}

  defp wait_for_ws_browser(port, tries) when tries > 0 do
    case http_get("http://127.0.0.1:#{port}/json/version") do
      {:ok, 200, body} ->
        case Jason.decode(body) do
          {:ok, %{"webSocketDebuggerUrl" => url}} -> {:ok, url}
          _ -> :timer.sleep(100); wait_for_ws_browser(port, tries - 1)
        end
      _ -> :timer.sleep(100); wait_for_ws_browser(port, tries - 1)
    end
  end
  defp wait_for_ws_browser(_port, _tries), do: {:error, :chrome_debug_not_ready}

  defp http_get(url) do
    :inets.start()
    :ssl.start()
    request = {String.to_charlist(url), []}
    case :httpc.request(:get, request, [], [body_format: :binary]) do
      {:ok, {{_, status, _}, _headers, body}} -> {:ok, status, body}
      other -> other
    end
  end

  defp open_page_ws(%{http_port: port}, url) do
    # Prefer connecting to existing page target and navigating it
    with {:ok, 200, body} <- http_get("http://127.0.0.1:#{port}/json/list"),
         {:ok, list} <- Jason.decode(body),
         %{"type" => "page", "webSocketDebuggerUrl" => ws_url} <- Enum.find(list, fn m -> m["type"] == "page" and is_binary(m["webSocketDebuggerUrl"]) end),
         {:ok, page_ws} <- __MODULE__.WS.open(ws_url),
         _ <- __MODULE__.WS.call(page_ws, "Page.enable", %{}),
         _ <- __MODULE__.WS.call(page_ws, "Runtime.enable", %{}),
         {:ok, _} <- __MODULE__.WS.call(page_ws, "Page.navigate", %{url: url}, 15_000) do
      {:ok, page_ws}
    else
      _ -> {:error, :target_create_failed}
    end
  end

  # --- Wait logic ---
  defp wait_until_ready(page_ws, timeout_ms) do
    # Hide topbar early to avoid capturing it in PNG as well
    _ = inject_css(page_ws, "#phx-topbar{display:none!important}")
    js = "(function(){return new Promise(function(res){(function check(){var ready = Boolean(window.TRIFLE_READY) || document.querySelector('.grid-stack .grid-widget-body .ts-chart, .grid-stack .grid-widget-body .cat-chart, .grid-stack .grid-widget-body .kpi-wrap'); if(ready){res(true);} else {setTimeout(check, 200);} })();});})()"
    case __MODULE__.WS.call(page_ws, "Runtime.evaluate", %{expression: js, returnByValue: true, awaitPromise: true}, timeout_ms) do
      {:ok, %{"result" => _}} -> :ok
      {:ok, {:error, _}=err} -> {:error, err}
      {:error, reason} -> {:error, reason}
    end
  end

  defp inject_css(page_ws, css) do
    _ = __MODULE__.WS.call(page_ws, "Runtime.evaluate", %{expression: "(function(){var s=document.createElement('style');s.textContent=`" <> css <> "`;document.head.appendChild(s);})();", returnByValue: false})
    :ok
  end

  # --- Capture ---
  defp page_print_to_pdf(page_ws, pdf_opts) do
    case __MODULE__.WS.call(page_ws, "Page.printToPDF", pdf_opts) do
      {:ok, %{"data" => b64}} -> {:ok, b64}
      other -> {:error, {:cdp_print_failed, other}}
    end
  end

  defp page_capture_screenshot(page_ws, clip) do
    params = %{format: "png", captureBeyondViewport: true} |> maybe_put_clip(clip)

    case __MODULE__.WS.call(page_ws, "Page.captureScreenshot", params) do
      {:ok, %{"data" => b64}} -> {:ok, b64}
      other -> {:error, {:cdp_screenshot_failed, other}}
    end
  end

  defp maybe_put_clip(params, {width, height}) when is_integer(width) and is_integer(height) do
    clip = %{x: 0, y: 0, width: width * 1.0, height: height * 1.0, scale: 1}
    Map.put(params, :clip, clip)
  end
  defp maybe_put_clip(params, _), do: params

  defp normalize_background(page_ws) do
    js = "(function(){\ntry{document.documentElement && document.documentElement.classList.remove('dark');}catch(e){}\ntry{if(document.body){if(document.body.classList){document.body.classList.remove('bg-slate-100');} document.body.style.background='#ffffff';}}catch(e){}\ntry{var s=document.createElement('style');\n s.textContent='/* Export-only normalization to avoid print artifacts */\\n .grid-stack-item, .grid-stack-item-content{background:#ffffff !important; background-clip:padding-box !important;}\\n .grid-stack .gs-resize-handle, .grid-stack .ui-resizable-handle, .grid-stack-placeholder{display:none !important;}\\n *:focus{outline:none !important; box-shadow:none !important;}\\n button,[role=button],.rounded-md{outline:none !important; box-shadow:none !important; background:#ffffff !important; border-color:#e5e7eb !important;}\\n #granularity-container button{background:#ffffff !important; border-color:#e5e7eb !important;}';\n document.head.appendChild(s);}catch(e){}\nreturn true;})()"
    _ = __MODULE__.WS.call(page_ws, "Runtime.evaluate", %{expression: js, returnByValue: true})
    :ok
  end

  defp set_dark_theme(page_ws) do
    js = "(function(){\ntry{document.documentElement && document.documentElement.classList.add('dark');}catch(e){}\ntry{if(document.body){if(document.body.classList){document.body.classList.remove('bg-slate-100');} document.body.style.background='#0f172a';}}catch(e){}\nreturn true;})()"
    _ = __MODULE__.WS.call(page_ws, "Runtime.evaluate", %{expression: js, returnByValue: true})
    :ok
  end

  defp close(page_ws) do
    try do
      __MODULE__.WS.close(page_ws)
    rescue
      _ -> :ok
    end
    :ok
  end

  defp kill_chrome(%{port_ref: port_ref, profile_dir: profile_dir}) do
    try do
      Port.close(port_ref)
    rescue
      _ -> :ok
    end
    # Best-effort cleanup of profile dir
    _ = File.rm_rf(profile_dir)
    :ok
  end

  defp expand_viewport_to_content(page_ws) do
    case __MODULE__.WS.call(page_ws, "Page.getLayoutMetrics", %{}) do
      {:ok, %{"contentSize" => %{"width" => width, "height" => height}}} when is_number(width) and is_number(height) ->
        max_dim = 16_384
        w = width |> ceil_to_int() |> min(max_dim) |> max(1)
        h = height |> ceil_to_int() |> min(max_dim) |> max(1)
        device_metrics = %{width: w, height: h, deviceScaleFactor: 1, mobile: false, scale: 1}
        _ = __MODULE__.WS.call(page_ws, "Emulation.setDeviceMetricsOverride", device_metrics)
        _ = __MODULE__.WS.call(page_ws, "Emulation.setVisibleSize", %{width: w, height: h})
        {w, h}
      other ->
        Logger.debug("CDP expand_viewport_to_content skipped: #{inspect(other)}")
        nil
    end
  end

  defp ceil_to_int(value) when is_integer(value), do: value
  defp ceil_to_int(value) when is_float(value), do: Float.ceil(value) |> trunc

  defp unique(prefix) do
    {m, s, us} = :os.timestamp()
    :crypto.hash(:sha256, "#{prefix}-#{m}-#{s}-#{us}-#{:rand.uniform()}" )
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 12)
  end

  # --- Minimal WS client for CDP using Mint.WebSocket ---
  defmodule WS do
    defstruct [:conn, :ws, :ref, :host, :port, :path, :secure, :next_id]

    def open(url) do
      uri = URI.parse(url)
      secure = uri.scheme == "wss"
      port = uri.port || (secure && 443 || 80)
      path = uri.path <> (if uri.query, do: "?" <> uri.query, else: "")
      host = uri.host
      scheme = if secure, do: :wss, else: :ws
      host_header = if port in [80, 443], do: host, else: "#{host}:#{port}"
      with {:ok, conn} <- Mint.HTTP.connect(secure && :https || :http, host, port, []),
           {:ok, conn, ref} <- Mint.WebSocket.upgrade(scheme, conn, path, [{"host", host_header}], []),
           {:ok, conn, {status, resp_headers}} <- await_upgrade(conn, ref) ,
           {:ok, conn, ws} <- Mint.WebSocket.new(conn, ref, status, resp_headers) do
        {:ok, %__MODULE__{conn: conn, ws: ws, ref: ref, host: host, port: port, path: path, secure: secure, next_id: 1}}
      else
        other -> other
      end
    end

    defp await_upgrade(conn, ref, acc_status \\ nil, acc_headers \\ nil) do
      receive do
        msg ->
          case Mint.WebSocket.stream(conn, msg) do
            {:ok, conn, responses} ->
              {status, headers, done} = collect_upgrade(responses, ref, acc_status, acc_headers)
              if done and status != nil and headers != nil do
                {:ok, conn, {status, headers}}
              else
                await_upgrade(conn, ref, status, headers)
              end
            {:error, conn, reason, _responses} -> {:error, reason}
          end
      after 5000 -> {:error, :timeout}
      end
    end

    defp collect_upgrade(responses, ref, acc_status, acc_headers) do
      Enum.reduce(responses, {acc_status, acc_headers, false}, fn resp, {st, hd, done} ->
        case resp do
          {:status, ^ref, code} -> {code, hd, done}
          {:headers, ^ref, headers} -> {st, headers, done}
          {:done, ^ref} -> {st, hd, true}
          _ -> {st, hd, done}
        end
      end)
    end

    def call(%__MODULE__{} = s, method, params, timeout_ms \\ 5000) when is_map(params) do
      id = s.next_id
      msg = Jason.encode!(%{"id" => id, "method" => method, "params" => params})
      {:ok, s} = send_text(s, msg)
      await_response(s, id, timeout_ms)
    end

    def close(%__MODULE__{} = s) do
      {:ok, conn, ws, data} = Mint.WebSocket.encode(s.ws, {:close, 1000, ""})
      {:ok, conn} = Mint.WebSocket.stream_request_body(s.conn, s.ref, data)
      _ = read_until_closed(conn)
      :ok
    end

    defp send_text(%__MODULE__{} = s, text) do
      case Mint.WebSocket.encode(s.ws, {:text, text}) do
        {:ok, ws, data} ->
          case Mint.WebSocket.stream_request_body(s.conn, s.ref, data) do
            {:ok, conn} -> {:ok, %{s | conn: conn, ws: ws, next_id: s.next_id + 1}}
            other -> other
          end
        other -> other
      end
    end

    defp await_response(%__MODULE__{} = s, id, timeout_ms) do
      receive do
        msg ->
          case Mint.WebSocket.stream(s.conn, msg) do
            {:ok, conn, responses} ->
              case handle_responses(s.ws, responses) do
                {:ok, ws, frames} ->
                  case match_response(frames, id) do
                    {:ok, result} -> {:ok, result}
                    :not_found -> await_response(%{s | conn: conn, ws: ws}, id, timeout_ms)
                  end
                {:error, reason} -> {:error, reason}
              end
            {:error, _conn, reason, _responses} -> {:error, reason}
          end
      after timeout_ms -> {:error, :timeout}
      end
    end

    defp handle_responses(ws, responses) do
      Enum.reduce_while(responses, {:ok, ws, []}, fn resp, {:ok, ws, acc} ->
        case resp do
          {:data, _ref, data} ->
            case Mint.WebSocket.decode(ws, data) do
              {:ok, ws, frames} -> {:cont, {:ok, ws, acc ++ frames}}
              {:error, _ws, reason} -> {:halt, {:error, reason}}
            end
          _ -> {:cont, {:ok, ws, acc}}
        end
      end)
    end

    defp match_response(frames, id) do
      Enum.find_value(frames, :not_found, fn frame ->
        case frame do
          {:text, json} ->
            case Jason.decode(json) do
              {:ok, %{"id" => ^id, "result" => result}} -> {:ok, result}
              {:ok, %{"id" => ^id, "error" => error}} -> {:ok, {:error, error}}
              _ -> false
            end
          _ -> false
        end
      end)
    end

    defp read_until_closed(conn) do
      receive do
        msg ->
          case Mint.HTTP.stream(conn, msg) do
            {:ok, conn, _} -> read_until_closed(conn)
            {:error, _conn, _reason, _} -> :ok
          end
      after 500 -> :ok end
    end
  end
end
