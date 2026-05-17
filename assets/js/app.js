// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import Sortable from "sortablejs"
import * as echarts from "echarts"
import { GridStack } from "gridstack"
import "./components/delivery_selector"
import { registerDashboardRuntimeHooks } from "./widgets/dashboard_runtime"
import { formatCompactNumber } from "./utils/formatting";
import { sanitizeRichHtml } from "./utils/sanitize_html";
import { ECHARTS_DEVICE_PIXEL_RATIO, withChartOpts, chartFontFamily, detectOngoingSegment, extractTimestamp } from "./utils/charts";
import { resolveHeatmapVisualMap, buildHeatmapOptions, buildBucketIndexMap, buildDistributionHeatmapAggregation, buildDistributionScatterSeries } from "./utils/heatmap";
import { TABLE_PATH_HTML_FIELD, AGGRID_PATH_COL_MIN_WIDTH, AGGRID_PATH_COL_MAX_WIDTH, ensureAgGridCommunity, getAggridHeaderComponentClass } from "./utils/aggrid";
import { parseJsonSafe, setHidden, findDashboardGridHook } from "./utils/dom";
import { registerBasicHooks } from "./hooks/basic_hooks";
import { registerDatabaseExploreChartHook } from "./hooks/database_explore_chart_hook";
import { registerTableHoverHook } from "./hooks/table_hover_hook";
import { registerSortableDashboardHooks } from "./hooks/sortable_dashboard_hooks";
import { registerDownloadHooks } from "./hooks/download_hooks";
import { registerPathAutocompleteHook } from "./hooks/path_autocomplete_hook";
import { registerWidgetSeriesRowsHook } from "./hooks/widget_series_rows_hook";
import { registerPhantomRowsHook } from "./hooks/phantom_rows_hook";
import { registerStatusHooks } from "./hooks/status_hooks";
import { registerFilterBarShortcutsHook } from "./hooks/filter_bar_shortcuts_hook";
import { getOrCreateTabId, registerSidebarAlpineComponents } from "./alpine/sidebar";
import { initializeThemeManager } from "./theme_manager";

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")


let Hooks = {}


registerDashboardRuntimeHooks(Hooks, {
  echarts,
  GridStack,
  withChartOpts,
  echartsDevicePixelRatio: ECHARTS_DEVICE_PIXEL_RATIO,
  chartFontFamily,
  formatCompactNumber,
  sanitizeRichHtml,
  resolveHeatmapVisualMap,
  buildHeatmapOptions,
  detectOngoingSegment,
  extractTimestamp,
  buildBucketIndexMap,
  buildDistributionHeatmapAggregation,
  buildDistributionScatterSeries,
  TABLE_PATH_HTML_FIELD,
  AGGRID_PATH_COL_MIN_WIDTH,
  AGGRID_PATH_COL_MAX_WIDTH,
  ensureAgGridCommunity,
  getAggridHeaderComponentClass,
  parseJsonSafe,
  findDashboardGridHook
});

registerBasicHooks(Hooks, { setHidden });
registerDatabaseExploreChartHook(Hooks, { echarts, withChartOpts, formatCompactNumber, chartFontFamily });
registerTableHoverHook(Hooks);
registerSortableDashboardHooks(Hooks, { Sortable, echarts, withChartOpts });
registerDownloadHooks(Hooks);
registerPathAutocompleteHook(Hooks);
registerWidgetSeriesRowsHook(Hooks);
registerPhantomRowsHook(Hooks);
registerStatusHooks(Hooks);
registerFilterBarShortcutsHook(Hooks);
registerSidebarAlpineComponents();



let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken, tab_id: getOrCreateTabId()},
  hooks: Hooks,
  dom: {
    onBeforeElUpdated(from, to) {
      if (from._x_dataStack) {
        window.Alpine.clone(from, to)
      }
    },
  }
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

window.addEventListener("phx:copy", (event) => {
  let text = event.target.textContent;
  navigator.clipboard.writeText(text).then(() => {
    // Copy completed
  })
})

initializeThemeManager();
