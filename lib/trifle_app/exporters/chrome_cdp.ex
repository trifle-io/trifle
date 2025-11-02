defmodule TrifleApp.Exporters.ChromeCDP do
  @moduledoc """
  Minimal Chrome DevTools Protocol exporter for waiting on page readiness
  (window.TRIFLE_READY) and capturing PDF/PNG deterministically.

  This module launches a headless Chrome with a remote debugging port,
  opens the target page, waits until a readiness expression evaluates
  to true, then calls Page.printToPDF or Page.captureScreenshot.
  """

  alias TrifleApp.Exporters.ChromeExporter
  alias TrifleApp.Exporters.ExportLog
  require Logger

  @default_pdf_opts %{
    landscape: false,
    printBackground: false,
    # Explicit A3 portrait sizing to preserve grid layout
    # inches
    paperWidth: 11.69,
    # inches
    paperHeight: 16.54,
    # ~8mm margins
    marginTop: 0.33,
    marginBottom: 0.33,
    marginLeft: 0.33,
    marginRight: 0.33
  }
  @default_viewport {1366, 900}
  # @default_pdf_viewport {1920, 1080} # Currently unused
  @default_timeout_ms 30000
  @png_max_dimension 16_384
  @png_capture_scale 2.0

  def default_pdf_opts, do: @default_pdf_opts

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

    theme = Keyword.get(opts, :theme, :light)
    log_context = ExportLog.normalize(Keyword.get(opts, :log_context, %{}))
    log_label = ExportLog.label(log_context)
    started_ms = ExportLog.monotonic_now_ms()

    Logger.info(
      "[chrome_cdp #{log_label}] start=pdf target=#{ExportLog.summarize_url(url)} theme=#{inspect(theme)} viewport=#{w}x#{h} timeout_ms=#{timeout_ms}"
    )

    with {:ok, chrome} <- ChromeExporter.find_chrome_binary(),
         _ = Logger.debug("[chrome_cdp #{log_label}] chrome_binary=#{chrome}"),
         {:ok, state} <- launch_chrome(chrome, w, h, log_context),
         {:ok, page_ws} <- open_page_ws_with_theme(state, url, theme, log_context),
         # Apply normalization early
         _ = normalize_background(page_ws, theme),
         _ = log_theme_state(page_ws, "pdf-after-normalize"),
         _ = set_background_override(page_ws),
         :ok <- wait_until_ready(page_ws, timeout_ms, log_context),
         _ = __MODULE__.WS.call(page_ws, "Emulation.setEmulatedMedia", %{media: "screen"}),
         {:ok, pdf_b64} <- page_print_to_pdf(page_ws, pdf_base),
         _ <- clear_background_override(page_ws) do
      _ = close(page_ws)
      _ = kill_chrome(state)
      bytes = div(byte_size(pdf_b64) * 3, 4)

      Logger.info(
        "[chrome_cdp #{log_label}] success=pdf elapsed_ms=#{ExportLog.since_ms(started_ms)} bytes=#{bytes}"
      )

      {:ok, Base.decode64!(pdf_b64)}
    else
      {:error, reason} = err ->
        Logger.error(
          "[chrome_cdp #{log_label}] failed=pdf elapsed_ms=#{ExportLog.since_ms(started_ms)} reason=#{inspect(reason)}"
        )

        err
    end
  end

  defp log_readiness_probe(page_ws, log_context) do
    expr = """
    (function() {
      const readyState = document.readyState;
      const trifleReady = !!window.TRIFLE_READY;
      const charts = Array.from(document.querySelectorAll('.grid-stack .grid-widget-body .ts-chart, .grid-stack .grid-widget-body .cat-chart, .grid-stack .grid-widget-body .kpi-wrap'));

      const sample = charts.slice(0, 5).map((chart, index) => {
        const rect = chart.getBoundingClientRect();
        const canvas = chart.querySelector('canvas');
        let canvasSize = null;
        if (canvas) {
          canvasSize = {width: canvas.width || 0, height: canvas.height || 0};
        }
        const svg = chart.querySelector('svg');
        let svgSize = null;
        if (svg) {
          try {
            const box = svg.getBBox();
            svgSize = {width: box.width || 0, height: box.height || 0};
          } catch (_e) {
            svgSize = null;
          }
        }

        return {
          idx: index,
          className: chart.className || null,
          rect: {width: rect.width, height: rect.height, top: rect.top, left: rect.left},
          canvasSize: canvasSize,
          svgSize: svgSize
        };
      });

      return {
        readyState: readyState,
        trifleReady: trifleReady,
        chartCount: charts.length,
        sample: sample,
        timestamp: Date.now()
      };
    })()
    """

    case __MODULE__.WS.call(
           page_ws,
           "Runtime.evaluate",
           %{expression: expr, returnByValue: true, awaitPromise: false},
           5_000
         ) do
      {:ok, %{"result" => %{"value" => value}}} ->
        Logger.warning(
          "[chrome_cdp #{ExportLog.label(log_context)}] readiness_probe=#{inspect(value)}"
        )

        :ok

      other ->
        Logger.warning(
          "[chrome_cdp #{ExportLog.label(log_context)}] readiness_probe_failed=#{inspect(other)}"
        )

        :ok
    end
  end

  # no-op placeholder (kept for potential future tuning)

  def export_png(url, opts \\ []) do
    {w, h} = Keyword.get(opts, :window_size, @default_viewport)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    theme = Keyword.get(opts, :theme, :light)
    log_context = ExportLog.normalize(Keyword.get(opts, :log_context, %{}))
    log_label = ExportLog.label(log_context)
    started_ms = ExportLog.monotonic_now_ms()

    Logger.info(
      "[chrome_cdp #{log_label}] start=png target=#{ExportLog.summarize_url(url)} theme=#{inspect(theme)} viewport=#{w}x#{h} timeout_ms=#{timeout_ms}"
    )

    with {:ok, chrome} <- ChromeExporter.find_chrome_binary(),
         _ = Logger.debug("[chrome_cdp #{log_label}] chrome_binary=#{chrome}"),
         {:ok, state} <- launch_chrome(chrome, w, h, log_context),
         {:ok, page_ws} <- open_page_ws_with_theme(state, url, theme, log_context),
         _ = normalize_background(page_ws, theme),
         _ = log_theme_state(page_ws, "png-after-normalize"),
         _ = set_background_override(page_ws),
         :ok <- wait_until_ready(page_ws, timeout_ms, log_context),
         _ = __MODULE__.WS.call(page_ws, "Emulation.setEmulatedMedia", %{media: "screen"}),
         clip <- expand_viewport_to_content(page_ws),
         {:ok, png_b64} <- page_capture_screenshot(page_ws, clip),
         _ <- clear_background_override(page_ws) do
      _ = close(page_ws)
      _ = kill_chrome(state)
      bytes = div(byte_size(png_b64) * 3, 4)

      Logger.info(
        "[chrome_cdp #{log_label}] success=png elapsed_ms=#{ExportLog.since_ms(started_ms)} bytes=#{bytes}"
      )

      {:ok, Base.decode64!(png_b64)}
    else
      {:error, reason} = err ->
        Logger.error(
          "[chrome_cdp #{log_label}] failed=png elapsed_ms=#{ExportLog.since_ms(started_ms)} reason=#{inspect(reason)}"
        )

        err
    end
  end

  # --- Chrome launch + discovery ---

  defp launch_chrome(chrome_bin, w, h, log_context) do
    profile_dir = Path.join(System.tmp_dir!(), unique("trifle_cdp_profile"))
    File.mkdir_p!(profile_dir)

    args = [
      "--headless=new",
      "--disable-gpu",
      "--no-sandbox",
      "--hide-scrollbars",
      "--disable-crash-reporter",
      "--no-crashpad",
      "--disable-logging",
      "--log-level=3",
      "--remote-debugging-address=127.0.0.1",
      "--remote-debugging-port=0",
      "--user-data-dir=#{profile_dir}",
      "--window-size=#{w},#{h}"
    ]

    log_label = ExportLog.label(log_context)
    launch_started_ms = ExportLog.monotonic_now_ms()

    Logger.debug(
      "[chrome_cdp #{log_label}] launch_chrome start bin=#{chrome_bin} profile=#{profile_dir} viewport=#{w}x#{h}"
    )

    # Start chrome detached; we won't read stdout, we will poll the /json endpoints
    port_ref =
      Port.open({:spawn_executable, chrome_bin}, [
        :binary,
        {:line, 4096},
        :exit_status,
        args: args
      ])

    # Discover dynamically chosen devtools port via DevToolsActivePort file
    case wait_for_devtools_port(profile_dir, 100, log_context) do
      {:ok, port} ->
        Logger.debug(
          "[chrome_cdp #{log_label}] launch_chrome devtools_port=#{port} waited_ms=#{ExportLog.since_ms(launch_started_ms)}"
        )

        case wait_for_ws_browser(port, 50, log_context) do
          {:ok, browser_ws_url} ->
            Logger.debug("[chrome_cdp #{log_label}] launch_chrome ws_ready=#{browser_ws_url}")

            {:ok,
             %{
               port_ref: port_ref,
               browser_ws: browser_ws_url,
               http_port: port,
               profile_dir: profile_dir
             }}

          {:error, reason} ->
            _ = File.rm_rf(profile_dir)

            Logger.error(
              "[chrome_cdp #{log_label}] launch_chrome ws_failed reason=#{inspect(reason)}"
            )

            {:error, reason}
        end

      {:error, reason} ->
        _ = File.rm_rf(profile_dir)

        Logger.error(
          "[chrome_cdp #{log_label}] launch_chrome no_devtools reason=#{inspect(reason)} elapsed_ms=#{ExportLog.since_ms(launch_started_ms)}"
        )

        {:error, reason}
    end
  end

  defp wait_for_devtools_port(profile_dir, tries, log_context) do
    wait_for_devtools_port(profile_dir, tries, log_context, 1)
  end

  defp wait_for_devtools_port(profile_dir, tries, log_context, attempt) when tries > 0 do
    file = Path.join(profile_dir, "DevToolsActivePort")

    case File.read(file) do
      {:ok, contents} ->
        [port_line | _] = String.split(contents, "\n", trim: true)

        case Integer.parse(port_line) do
          {port, _} ->
            Logger.debug(
              "[chrome_cdp #{ExportLog.label(log_context)}] devtools_port_found port=#{port} attempts=#{attempt}"
            )

            {:ok, port}

          :error ->
            :timer.sleep(100)
            log_devtools_wait(log_context, attempt + 1)
            wait_for_devtools_port(profile_dir, tries - 1, log_context, attempt + 1)
        end

      {:error, _} ->
        :timer.sleep(100)
        log_devtools_wait(log_context, attempt + 1)
        wait_for_devtools_port(profile_dir, tries - 1, log_context, attempt + 1)
    end
  end

  defp wait_for_devtools_port(_profile_dir, _tries, log_context, attempt) do
    Logger.error(
      "[chrome_cdp #{ExportLog.label(log_context)}] devtools_port_not_found attempts=#{attempt - 1}"
    )

    {:error, :devtools_port_not_found}
  end

  defp log_devtools_wait(log_context, attempt) do
    if rem(attempt, 20) == 0 do
      Logger.debug(
        "[chrome_cdp #{ExportLog.label(log_context)}] waiting_for_devtools attempt=#{attempt}"
      )
    end
  end

  defp wait_for_ws_browser(port, tries, log_context) do
    wait_for_ws_browser(port, tries, log_context, 1)
  end

  defp wait_for_ws_browser(port, tries, log_context, attempt) when tries > 0 do
    case http_get("http://127.0.0.1:#{port}/json/version") do
      {:ok, 200, body} ->
        case Jason.decode(body) do
          {:ok, %{"webSocketDebuggerUrl" => url}} ->
            Logger.debug(
              "[chrome_cdp #{ExportLog.label(log_context)}] ws_browser_ready attempt=#{attempt}"
            )

            {:ok, url}

          _ ->
            :timer.sleep(100)
            log_ws_wait(log_context, attempt + 1)
            wait_for_ws_browser(port, tries - 1, log_context, attempt + 1)
        end

      _ ->
        :timer.sleep(100)
        log_ws_wait(log_context, attempt + 1)
        wait_for_ws_browser(port, tries - 1, log_context, attempt + 1)
    end
  end

  defp wait_for_ws_browser(_port, _tries, log_context, attempt) do
    Logger.error(
      "[chrome_cdp #{ExportLog.label(log_context)}] ws_browser_not_ready attempts=#{attempt - 1}"
    )

    {:error, :chrome_debug_not_ready}
  end

  defp log_ws_wait(log_context, attempt) do
    if rem(attempt, 20) == 0 do
      Logger.debug(
        "[chrome_cdp #{ExportLog.label(log_context)}] waiting_for_ws attempt=#{attempt}"
      )
    end
  end

  defp http_get(url) do
    :inets.start()
    :ssl.start()
    request = {String.to_charlist(url), []}

    case :httpc.request(:get, request, [], body_format: :binary) do
      {:ok, {{_, status, _}, _headers, body}} -> {:ok, status, body}
      other -> other
    end
  end

  defp open_page_ws(%{http_port: port}, url, log_context) do
    log_label = ExportLog.label(log_context)

    # Prefer connecting to existing page target and navigating it
    with {:ok, 200, body} <- http_get("http://127.0.0.1:#{port}/json/list"),
         {:ok, list} <- Jason.decode(body),
         %{"type" => "page", "webSocketDebuggerUrl" => ws_url} <-
           Enum.find(list, fn m ->
             m["type"] == "page" and is_binary(m["webSocketDebuggerUrl"])
           end),
         {:ok, page_ws} <- __MODULE__.WS.open(ws_url),
         _ <- __MODULE__.WS.call(page_ws, "Page.enable", %{}),
         _ <- __MODULE__.WS.call(page_ws, "Runtime.enable", %{}),
         {:ok, _} <- __MODULE__.WS.call(page_ws, "Page.navigate", %{url: url}, 15_000) do
      Logger.debug(
        "[chrome_cdp #{log_label}] open_page_ws connected port=#{port} ws_url=#{ws_url}"
      )

      {:ok, page_ws}
    else
      error ->
        Logger.error(
          "[chrome_cdp #{log_label}] open_page_ws_failed port=#{port} target=#{ExportLog.summarize_url(url)} error=#{inspect(error)}"
        )

        {:error, :target_create_failed}
    end
  end

  defp open_page_ws_with_theme(state, url, theme, log_context) do
    log_label = ExportLog.label(log_context)

    Logger.debug(
      "[chrome_cdp #{log_label}] open_page_ws_with_theme start theme=#{inspect(theme)} target=#{ExportLog.summarize_url(url)}"
    )

    with {:ok, page_ws} <- open_page_ws(state, url, log_context),
         # Apply theme immediately after opening page but before navigation
         _ = apply_theme_before_load(page_ws, theme),
         # Re-navigate to ensure theme is applied
         {:ok, _} <- __MODULE__.WS.call(page_ws, "Page.navigate", %{url: url}, 15_000) do
      Logger.debug(
        "[chrome_cdp #{log_label}] open_page_ws_with_theme navigation_complete theme=#{inspect(theme)}"
      )

      {:ok, page_ws}
    else
      {:error, reason} = error ->
        Logger.error(
          "[chrome_cdp #{log_label}] open_page_ws_with_theme_failed reason=#{inspect(reason)}"
        )

        error

      error ->
        Logger.error(
          "[chrome_cdp #{log_label}] open_page_ws_with_theme_failed raw=#{inspect(error)}"
        )

        error
    end
  end

  # --- Wait logic ---
  defp wait_until_ready(page_ws, timeout_ms, log_context) do
    # Hide topbar early to avoid capturing it in PNG as well
    _ = inject_css(page_ws, "#phx-topbar{display:none!important}")

    log_label = ExportLog.label(log_context)
    started_ms = ExportLog.monotonic_now_ms()

    Logger.debug("[chrome_cdp #{log_label}] wait_until_ready start timeout_ms=#{timeout_ms}")

    # Enhanced JS that waits for both DOM and chart rendering
    js = """
    (function(){
      return new Promise(function(resolve) {
        let checkCount = 0;
        const maxChecks = #{div(timeout_ms, 200)}; // timeout_ms with 200ms intervals
        
        function checkReady() {
          checkCount++;
          
          // Check for TRIFLE_READY flag
          if (window.TRIFLE_READY) {
            // Additional delay to ensure charts are rendered
            setTimeout(() => resolve(true), 500);
            return;
          }
          
          // Check for chart elements
          const charts = document.querySelectorAll('.grid-stack .grid-widget-body .ts-chart, .grid-stack .grid-widget-body .cat-chart, .grid-stack .grid-widget-body .kpi-wrap');
          
          if (charts.length > 0) {
            // Check if chart canvases are ready (for ECharts)
            let allChartsReady = true;
            charts.forEach(chart => {
              const canvas = chart.querySelector('canvas');
              if (!canvas || canvas.width === 0 || canvas.height === 0) {
                allChartsReady = false;
              }
              // Also check for SVG charts
              const svg = chart.querySelector('svg');
              if (!canvas && (!svg || svg.getBBox().width === 0)) {
                allChartsReady = false;
              }
            });
            
            if (allChartsReady) {
              // Wait a bit more for any final rendering
              setTimeout(() => resolve(true), 1000);
              return;
            }
          }
          
          if (checkCount < maxChecks) {
            setTimeout(checkReady, 200);
          } else {
            resolve(false); // Timeout
          }
        }
        
        checkReady();
      });
    })()
    """

    case __MODULE__.WS.call(
           page_ws,
           "Runtime.evaluate",
           %{expression: js, returnByValue: true, awaitPromise: true},
           # Add buffer for internal delays
           timeout_ms + 2000
         ) do
      {:ok, %{"result" => %{"value" => true}}} ->
        Logger.debug(
          "[chrome_cdp #{log_label}] wait_until_ready ready elapsed_ms=#{ExportLog.since_ms(started_ms)}"
        )

        # Add stabilization check after initial readiness
        wait_for_stable_rendering(page_ws, 300, log_context)

      {:ok, %{"result" => %{"value" => false}}} ->
        Logger.warning(
          "[chrome_cdp #{log_label}] wait_until_ready timeout elapsed_ms=#{ExportLog.since_ms(started_ms)}"
        )

        log_readiness_probe(page_ws, log_context)
        {:error, :charts_not_ready_timeout}

      {:ok, %{"result" => result}} ->
        Logger.warning(
          "[chrome_cdp #{log_label}] wait_until_ready unexpected_result=#{inspect(result)}"
        )

        :ok

      other ->
        Logger.error(
          "[chrome_cdp #{log_label}] wait_until_ready evaluation_failed=#{inspect(other)} elapsed_ms=#{ExportLog.since_ms(started_ms)}"
        )

        {:error, {:evaluation_failed, other}}
    end
  end

  defp inject_css(page_ws, css) do
    _ =
      __MODULE__.WS.call(page_ws, "Runtime.evaluate", %{
        expression:
          "(function(){var s=document.createElement('style');s.textContent=`" <>
            css <> "`;document.head.appendChild(s);})();",
        returnByValue: false
      })

    :ok
  end

  defp wait_for_stable_rendering(page_ws, stability_duration_ms \\ 300, log_context \\ %{}) do
    log_label = ExportLog.label(log_context)
    started_ms = ExportLog.monotonic_now_ms()

    Logger.debug(
      "[chrome_cdp #{log_label}] wait_for_stable_rendering start duration_ms=#{stability_duration_ms}"
    )

    js = """
    (function() {
      return new Promise((resolve) => {
        let lastChangeTime = Date.now();
        const observer = new MutationObserver(() => {
          lastChangeTime = Date.now();
        });
        
        // Observe chart containers
        const chartContainers = document.querySelectorAll('.ts-chart, .cat-chart, .kpi-wrap');
        chartContainers.forEach(container => {
          observer.observe(container, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['style', 'class', 'width', 'height']
          });
        });
        
        // Check for stability
        const checkStability = setInterval(() => {
          if (Date.now() - lastChangeTime > #{stability_duration_ms}) {
            clearInterval(checkStability);
            observer.disconnect();
            resolve(true);
          }
        }, 100);
        
        // Timeout after 5 seconds
        setTimeout(() => {
          clearInterval(checkStability);
          observer.disconnect();
          resolve(true);
        }, 5000);
      });
    })()
    """

    case __MODULE__.WS.call(
           page_ws,
           "Runtime.evaluate",
           %{
             expression: js,
             returnByValue: true,
             awaitPromise: true
           },
           10_000
         ) do
      {:ok, _} ->
        Logger.debug(
          "[chrome_cdp #{log_label}] wait_for_stable_rendering complete elapsed_ms=#{ExportLog.since_ms(started_ms)}"
        )

        :ok

      {:error, reason} ->
        Logger.warning(
          "[chrome_cdp #{log_label}] wait_for_stable_rendering_failed=#{inspect(reason)} elapsed_ms=#{ExportLog.since_ms(started_ms)}"
        )

        # Continue anyway
        :ok
    end
  end

  # --- Capture ---
  defp page_print_to_pdf(page_ws, pdf_opts) do
    case __MODULE__.WS.call(page_ws, "Page.printToPDF", pdf_opts) do
      {:ok, %{"data" => b64}} -> {:ok, b64}
      other -> {:error, {:cdp_print_failed, other}}
    end
  end

  defp page_capture_screenshot(page_ws, clip) do
    params =
      %{format: "png", captureBeyondViewport: true, omitBackground: true} |> maybe_put_clip(clip)

    case __MODULE__.WS.call(page_ws, "Page.captureScreenshot", params) do
      {:ok, %{"data" => b64}} -> {:ok, b64}
      other -> {:error, {:cdp_screenshot_failed, other}}
    end
  end

  defp maybe_put_clip(params, %{width: width, height: height, scale: scale})
       when is_integer(width) and is_integer(height) and is_number(scale) do
    clip = %{x: 0, y: 0, width: width * 1.0, height: height * 1.0, scale: scale}
    Map.put(params, :clip, clip)
  end

  defp maybe_put_clip(params, {width, height}) when is_integer(width) and is_integer(height) do
    maybe_put_clip(params, %{width: width, height: height, scale: 1.0})
  end

  defp maybe_put_clip(params, _), do: params

  defp normalize_background(page_ws, theme) do
    theme_string =
      case theme do
        :dark -> "dark"
        :light -> "light"
        value when is_binary(value) -> value
        _ -> "light"
      end

    Logger.debug("CDP normalize_background theme=#{theme_string}")

    js = """
    (function(){
      const theme = "#{theme_string}";
      return new Promise((resolve) => {
        try{
          if(document.documentElement){
            document.documentElement.style.background='transparent';
            document.documentElement.dataset.exportTheme = theme;
            if(theme === 'dark'){
              document.documentElement.classList.add('dark');
            } else {
              document.documentElement.classList.remove('dark');
            }
          }
        }catch(e){}
        try{
          if(document.body){
            if(theme === 'dark'){
              if(document.body.classList){document.body.classList.add('dark'); document.body.classList.remove('bg-slate-100');}
            } else {
              if(document.body.classList){document.body.classList.remove('dark'); document.body.classList.remove('bg-slate-100');}
            }
            document.body.style.background='transparent';
            document.body.setAttribute('data-theme', theme);
          }
        }catch(e){}
        try{
          var style=document.getElementById('export-normalize-style');
          if(!style){
            style=document.createElement('style');
            style.id='export-normalize-style';
            if(theme === 'dark'){
              style.textContent='/* Dark export normalization */\\n:root, body, #export-layout-root, #export-layout-root .export-layout-canvas{background:transparent !important;}\\n #export-layout-root .grid-stack{background:transparent !important;}\\n body.dark{color:#f8fafc !important;}\\n .grid-stack .gs-resize-handle, .grid-stack .ui-resizable-handle, .grid-stack-placeholder{display:none !important;}\\n *:focus{outline:none !important; box-shadow:none !important;}';
            } else {
              style.textContent='/* Light export normalization */\\n:root, body, #export-layout-root, #export-layout-root .export-layout-canvas{background:transparent !important;}\\n #export-layout-root .grid-stack{background:transparent !important;}\\n .grid-stack .gs-resize-handle, .grid-stack .ui-resizable-handle, .grid-stack-placeholder{display:none !important;}\\n *:focus{outline:none !important; box-shadow:none !important;}';
            }
            document.head.appendChild(style);
          }
        }catch(e){}
        try{window.dispatchEvent(new CustomEvent('trifle:theme-changed',{detail:{theme:theme}}));}catch(e){}
      setTimeout(() => resolve(true), 100);
    });
    })()
    """

    _ =
      __MODULE__.WS.call(
        page_ws,
        "Runtime.evaluate",
        %{
          expression: js,
          returnByValue: true,
          awaitPromise: true
        },
        5000
      )

    :ok
  end

  defp apply_theme_before_load(page_ws, theme) do
    Logger.debug("CDP apply_theme_before_load theme=#{inspect(theme)}")
    # Inject a script that will apply theme immediately on page load
    js =
      case theme do
        :dark ->
          """
            (function() {
              // Apply dark theme via localStorage and DOM manipulation
              localStorage.setItem('theme', 'dark');
              document.addEventListener('DOMContentLoaded', function() {
                document.documentElement.classList.add('dark');
                if(document.body){
                  document.body.classList.add('dark');
                  document.body.style.background = 'transparent';
                  document.body.setAttribute('data-theme', 'dark');
                }
                document.documentElement.style.background = 'transparent';
                document.body.setAttribute('data-theme', 'dark');
              });
            })();
          """

        _ ->
          """
            (function() {
              // Apply light theme via localStorage and DOM manipulation
              localStorage.setItem('theme', 'light');
              document.addEventListener('DOMContentLoaded', function() {
                document.documentElement.classList.remove('dark');
                if(document.body){
                  document.body.classList.remove('dark');
                  document.body.style.background = 'transparent';
                  document.body.setAttribute('data-theme', 'light');
                }
                document.documentElement.style.background = 'transparent';
                document.body.setAttribute('data-theme', 'light');
              });
            })();
          """
      end

    _ =
      __MODULE__.WS.call(page_ws, "Page.addScriptToEvaluateOnNewDocument", %{
        source: js
      })

    :ok
  end

  defp log_theme_state(page_ws, stage) do
    expr =
      "(() => { const root = document.getElementById('export-layout-root'); const grid = root ? root.querySelector('.grid-stack') : null; return { htmlClass: document.documentElement ? document.documentElement.className : null, bodyClass: document.body ? document.body.className : null, bodyTheme: document.body ? document.body.getAttribute('data-theme') : null, bodyBg: window.getComputedStyle(document.body || document.documentElement).backgroundColor, rootBg: root ? window.getComputedStyle(root).backgroundColor : null, gridBg: grid ? window.getComputedStyle(grid).backgroundColor : null }; })()"

    case __MODULE__.WS.call(
           page_ws,
           "Runtime.evaluate",
           %{expression: expr, returnByValue: true},
           5_000
         ) do
      {:ok, %{"result" => %{"value" => value}}} ->
        Logger.debug("CDP theme_state #{stage} #{inspect(value)}")
        :ok

      other ->
        Logger.debug("CDP theme_state #{stage} error=#{inspect(other)}")
        :ok
    end
  end

  defp set_background_override(page_ws) do
    params = %{color: %{r: 0, g: 0, b: 0, a: 0}}

    case __MODULE__.WS.call(page_ws, "Emulation.setDefaultBackgroundColorOverride", params, 5_000) do
      {:ok, _} ->
        :ok

      other ->
        Logger.debug("CDP set_background_override error=#{inspect(other)}")
        :ok
    end
  end

  defp clear_background_override(page_ws) do
    case __MODULE__.WS.call(page_ws, "Emulation.setDefaultBackgroundColorOverride", %{}, 5_000) do
      {:ok, _} ->
        :ok

      other ->
        Logger.debug("CDP clear_background_override error=#{inspect(other)}")
        :ok
    end
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
      {:ok, %{"contentSize" => %{"width" => width, "height" => height}}}
      when is_number(width) and is_number(height) and width > 0 and height > 0 ->
        w = width |> ceil_to_int() |> min(@png_max_dimension) |> max(1)
        h = height |> ceil_to_int() |> min(@png_max_dimension) |> max(1)
        device_metrics = %{width: w, height: h, deviceScaleFactor: 1, mobile: false, scale: 1}
        _ = __MODULE__.WS.call(page_ws, "Emulation.setDeviceMetricsOverride", device_metrics)
        _ = __MODULE__.WS.call(page_ws, "Emulation.setVisibleSize", %{width: w, height: h})
        %{width: w, height: h, scale: png_capture_scale(w, h)}

      other ->
        Logger.debug("CDP expand_viewport_to_content skipped: #{inspect(other)}")
        nil
    end
  end

  defp png_capture_scale(width, height) do
    max_side = max(width, height)

    cond do
      max_side <= 0 ->
        1.0

      true ->
        max_scale = @png_max_dimension / max_side
        scale = min(@png_capture_scale, max_scale)
        if scale < 1.0, do: 1.0, else: scale
    end
  end

  defp ceil_to_int(value) when is_integer(value), do: value
  defp ceil_to_int(value) when is_float(value), do: Float.ceil(value) |> trunc

  defp unique(prefix) do
    {m, s, us} = :os.timestamp()

    :crypto.hash(:sha256, "#{prefix}-#{m}-#{s}-#{us}-#{:rand.uniform()}")
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 12)
  end

  # --- Minimal WS client for CDP using Mint.WebSocket ---
  defmodule WS do
    defstruct [:conn, :ws, :ref, :host, :port, :path, :secure, :next_id]

    def open(url) do
      uri = URI.parse(url)
      secure = uri.scheme == "wss"
      port = uri.port || ((secure && 443) || 80)
      path = uri.path <> if uri.query, do: "?" <> uri.query, else: ""
      host = uri.host
      scheme = if secure, do: :wss, else: :ws
      host_header = if port in [80, 443], do: host, else: "#{host}:#{port}"

      with {:ok, conn} <- Mint.HTTP.connect((secure && :https) || :http, host, port, []),
           {:ok, conn, ref} <-
             Mint.WebSocket.upgrade(scheme, conn, path, [{"host", host_header}], []),
           {:ok, conn, {status, resp_headers}} <- await_upgrade(conn, ref),
           {:ok, conn, ws} <- Mint.WebSocket.new(conn, ref, status, resp_headers) do
        {:ok,
         %__MODULE__{
           conn: conn,
           ws: ws,
           ref: ref,
           host: host,
           port: port,
           path: path,
           secure: secure,
           next_id: 1
         }}
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

            {:error, _conn, reason, _responses} ->
              {:error, reason}
          end
      after
        5000 -> {:error, :timeout}
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
      {:ok, _conn, _ws, data} = Mint.WebSocket.encode(s.ws, {:close, 1000, ""})
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

        other ->
          other
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

                {:error, reason} ->
                  {:error, reason}
              end

            {:error, _conn, reason, _responses} ->
              {:error, reason}
          end
      after
        timeout_ms -> {:error, :timeout}
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

          _ ->
            {:cont, {:ok, ws, acc}}
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

          _ ->
            false
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
      after
        500 -> :ok
      end
    end
  end
end
