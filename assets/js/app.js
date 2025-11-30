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

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const ECHARTS_RENDERER = 'svg';
const ECHARTS_DEVICE_PIXEL_RATIO = Math.max(1, window.devicePixelRatio || 1);
const withChartOpts = (opts = {}) => Object.assign({ renderer: ECHARTS_RENDERER, devicePixelRatio: ECHARTS_DEVICE_PIXEL_RATIO }, opts);
const chartFontFamily =
  'Inter var, Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';

const formatCompactNumber = (value) => {
  if (value === null || value === undefined || value === '') return '0';
  const n = Number(value);
  if (!Number.isFinite(n)) return String(value);
  const abs = Math.abs(n);
  if (abs >= 1_000) {
    const units = ['', 'K', 'M', 'B', 'T'];
    let unitIndex = 0;
    let scaled = abs;
    while (scaled >= 1000 && unitIndex < units.length - 1) {
      scaled /= 1000;
      unitIndex += 1;
    }
    const decimals = scaled < 10 ? 2 : scaled < 100 ? 1 : 0;
    const formatted = scaled
      .toFixed(decimals)
      .replace(/\.0+$/, '')
      .replace(/(\.\d*?[1-9])0+$/, '$1');
    return `${n < 0 ? '-' : ''}${formatted}${units[unitIndex]}`;
  }

  const decimals = abs < 1 ? 2 : Number.isInteger(n) ? 0 : abs < 10 ? 2 : 1;
  return n
    .toFixed(decimals)
    .replace(/\.0+$/, '')
    .replace(/(\.\d*?[1-9])0+$/, '$1');
};

const TABLE_PATH_HTML_FIELD = '__table_path_html__';
const AGGRID_PATH_COL_MIN_WIDTH = 160;
const AGGRID_PATH_COL_MAX_WIDTH = 640;
const AGGRID_SCRIPT_SRC = 'https://cdn.jsdelivr.net/npm/ag-grid-community@31.0.3/dist/ag-grid-community.min.js';
const AGGRID_BASE_STYLE_SRC = 'https://cdn.jsdelivr.net/npm/ag-grid-community@31.0.3/styles/ag-grid.css';
const AGGRID_THEME_LIGHT_STYLE_SRC = 'https://cdn.jsdelivr.net/npm/ag-grid-community@31.0.3/styles/ag-theme-alpine.css';
const AGGRID_THEME_DARK_STYLE_SRC = 'https://cdn.jsdelivr.net/npm/ag-grid-community@31.0.3/styles/ag-theme-alpine-dark.css';
let aggridLoaderPromise = null;
let aggridHeaderComponentClass = null;

const ensureStylesheet = (id, href) => {
  if (typeof document === 'undefined') return;
  if (document.getElementById(id)) return;
  const existing = Array.from(document.querySelectorAll(`link[data-trifle-css="${id}"]`));
  if (existing.length) return;
  const link = document.createElement('link');
  link.rel = 'stylesheet';
  link.href = href;
  link.id = id;
  link.dataset.trifleCss = id;
  document.head.appendChild(link);
};

const ensureAgGridCommunity = () => {
  if (typeof window !== 'undefined' && window.agGrid && window.agGrid.Grid) {
    return Promise.resolve(window.agGrid);
  }
  if (!aggridLoaderPromise) {
    aggridLoaderPromise = new Promise((resolve, reject) => {
      if (typeof document === 'undefined') {
        reject(new Error('Document not available'));
        return;
      }
      ensureStylesheet('ag-grid-base-css', AGGRID_BASE_STYLE_SRC);
      ensureStylesheet('ag-grid-alpine-css', AGGRID_THEME_LIGHT_STYLE_SRC);
      ensureStylesheet('ag-grid-alpine-dark-css', AGGRID_THEME_DARK_STYLE_SRC);
      const script = document.createElement('script');
      script.src = AGGRID_SCRIPT_SRC;
      script.async = true;
      script.onload = () => resolve(window.agGrid);
      script.onerror = (err) => {
        console.error('[AGGrid] failed to load ag-grid-community script', err);
        aggridLoaderPromise = null;
        reject(err);
      };
      document.head.appendChild(script);
    });
  }
  return aggridLoaderPromise;
};

const getAggridHeaderComponentClass = () => {
  if (aggridHeaderComponentClass) return aggridHeaderComponentClass;
  class TrifleAgGridHeader {
    init(params) {
      this.eGui = document.createElement('div');
      this.eGui.className = 'aggrid-header-cell-wrapper';
      if (params && params.align === 'left') {
        this.eGui.classList.add('aggrid-header-align-left');
      } else {
        this.eGui.classList.add('aggrid-header-align-right');
      }
      const lines =
        (params &&
          params.column &&
          params.column.getColDef &&
          params.column.getColDef() &&
          params.column.getColDef().headerComponentParams &&
          params.column.getColDef().headerComponentParams.lines) ||
        [];
      const displayName = params && typeof params.displayName === 'string' ? params.displayName : '';
      const segments = Array.isArray(lines) && lines.length ? lines : [displayName];
      segments.forEach((segment, idx) => {
        const span = document.createElement('span');
        span.className = 'aggrid-header-line';
        span.textContent = segment;
        this.eGui.appendChild(span);
      });
    }

    getGui() {
      return this.eGui;
    }

    destroy() {}
  }
  aggridHeaderComponentClass = TrifleAgGridHeader;
  return aggridHeaderComponentClass;
};

let Hooks = {}

const parseJsonSafe = (value) => {
  if (value == null || value === '') return null;
  try {
    return JSON.parse(value);
  } catch (_) {
    return null;
  }
};

const findDashboardGridHook = (el) => {
  if (!el) return null;
  const gridId = el.dataset && el.dataset.gridId;
  if (gridId) {
    const direct = document.getElementById(gridId);
    if (direct && direct.__dashboardGrid) return direct.__dashboardGrid;
  }
  const gridEl = el.closest('#dashboard-grid') || el.closest('.grid-stack');
  if (gridEl && gridEl.__dashboardGrid) return gridEl.__dashboardGrid;
  if (gridId) {
    const fallback = document.querySelector(`#${gridId}`);
    if (fallback && fallback.__dashboardGrid) return fallback.__dashboardGrid;
  }
  return null;
};

Hooks.DocumentTitle = {
  mounted() {
    // Create bound event handler so we can properly remove it
    this.handleNavigate = () => {
      // Force LiveView to update the title after navigation
      // This ensures the title updates even when using push_navigate
      requestAnimationFrame(() => {
        const liveTitle = document.querySelector('[data-phx-main] title')
        if (liveTitle && liveTitle.textContent) {
          document.title = liveTitle.textContent
        } else {
          // Fallback to our element's data
          this.updateTitle()
        }
      })
    }
    
    this.updateTitle()
    
    // Listen for both navigation events
    window.addEventListener("phx:page-loading-stop", this.handleNavigate)
    window.addEventListener("phx:navigate", this.handleNavigate)
  },
  updated() {
    this.updateTitle()
  },
  destroyed() {
    if (this.handleNavigate) {
      window.removeEventListener("phx:page-loading-stop", this.handleNavigate)
      window.removeEventListener("phx:navigate", this.handleNavigate)
    }
  },
  updateTitle() {
    const title = this.el.dataset.title || 'Trifle'
    const suffix = this.el.dataset.suffix || ''
    document.title = `${title}${suffix}`
  }
}

Hooks.SmartTimeframeInput = {
  mounted() {
    this.handleEvent("update_smart_timeframe_input", ({value}) => {
      this.el.value = value;
    });
  }
}

Hooks.SmartTimeframeBlur = {
  mounted() {
    this.el.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        // Blur the input after Enter to trigger value update
        setTimeout(() => this.el.blur(), 100);
      }
    });
    
    // Auto-select text when input is focused
    this.el.addEventListener('focus', () => {
      // Use setTimeout to ensure selection happens after other focus events
      setTimeout(() => {
        this.el.select();
      }, 10);
    });
    
    // Also handle click events in case focus doesn't work
    this.el.addEventListener('click', () => {
      // Only select if the input wasn't already focused
      if (document.activeElement !== this.el) {
        setTimeout(() => {
          this.el.select();
        }, 10);
      }
    });
    
    this.handleEvent("update_timeframe_input", ({value}) => {
      this.el.value = value;
    });
  }
}

Hooks.ChatScroll = {
  mounted() {
    this._pendingScroll = null
    this.scrollToBottom()
    this.handleEvent("chat_scroll_bottom", () => this.scrollToBottom())
  },
  updated() {
    this.scrollToBottom()
  },
  scrollToBottom() {
    if (this._pendingScroll) {
      clearTimeout(this._pendingScroll)
    }

    const performScroll = (behavior = "auto") => {
      const el = this.el
      if (!el) return
      el.scrollTo({ top: el.scrollHeight, behavior })
    }

    requestAnimationFrame(() => {
      performScroll("auto")
      requestAnimationFrame(() => performScroll("smooth"))
    })

    this._pendingScroll = setTimeout(() => performScroll("auto"), 300)
  },
  destroyed() {
    if (this._pendingScroll) {
      clearTimeout(this._pendingScroll)
    }
  }
}

Hooks.ChatInput = {
  mounted() {
    this.handleKeydown = (event) => {
      if (event.defaultPrevented || this.el.disabled || this.el.readOnly) {
        return
      }

      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault()

        const form = this.el.form || this.el.closest("form")
        if (!form) return

        if (typeof form.requestSubmit === "function") {
          form.requestSubmit()
        } else {
          const submit = form.querySelector('[type="submit"]:not([disabled])')
          if (submit) submit.click()
        }
      }
    }

    this.el.addEventListener("keydown", this.handleKeydown)
  },
  destroyed() {
    if (this.handleKeydown) {
      this.el.removeEventListener("keydown", this.handleKeydown)
    }
  }
}

Hooks.ExportTheme = {
  mounted() {
    this.applyTheme();
  },
  updated() {
    this.applyTheme();
  },
  destroyed() {
    if (this._themeTimer) {
      clearTimeout(this._themeTimer);
      this._themeTimer = null;
    }
  },
  applyTheme() {
    const dataset = this.el.dataset || {};
    const value = (dataset.exportTheme || dataset.theme || '').toLowerCase();
    const theme = value === 'dark' ? 'dark' : 'light';
    const root = document.documentElement;
    const body = document.body;
    try {
      if (theme === 'dark') {
        root.classList.add('dark');
        if (body && body.classList) body.classList.add('dark');
      } else {
        root.classList.remove('dark');
        if (body && body.classList) body.classList.remove('dark');
      }
      root.dataset.exportTheme = theme;
      if (body) body.dataset.theme = theme;
      root.style.background = 'transparent';
      if (body) body.style.background = 'transparent';
    } catch (_) {}

    if (this._themeTimer) {
      clearTimeout(this._themeTimer);
      this._themeTimer = null;
    }

    this._themeTimer = setTimeout(() => {
      try {
        window.dispatchEvent(new CustomEvent('trifle:theme-changed', { detail: { theme } }));
      } catch (_) {}
    }, 0);
  }
}

Hooks.ChatChart = {
  mounted() {
    this.chart = null;
    this.theme = null;
    this.retryTimer = null;
    this.resizeObserver = null;
    this.pendingRender = false;
    this.resizeHandler = () => {
      if (this.chart && typeof this.chart.resize === 'function') {
        try { this.chart.resize(); } catch (_) {}
      }
    };
    this.themeHandler = () => this.render(true);
    this.createResizeObserver();
    window.addEventListener('resize', this.resizeHandler);
    window.addEventListener('trifle:theme-changed', this.themeHandler);
    this.render();
  },
  updated() {
    this.render();
  },
  destroyed() {
    if (this.retryTimer) {
      clearTimeout(this.retryTimer);
      this.retryTimer = null;
    }
    this.destroyResizeObserver();
    if (this.chart && typeof this.chart.dispose === 'function') {
      try { this.chart.dispose(); } catch (_) {}
    }
    this.chart = null;
    this.pendingRender = false;
    window.removeEventListener('resize', this.resizeHandler);
    window.removeEventListener('trifle:theme-changed', this.themeHandler);
  },
  render(force = false) {
    const chartData = this.parseChart();
    if (!chartData) return;
    if (this.retryTimer) {
      clearTimeout(this.retryTimer);
      this.retryTimer = null;
    }
    const width = this.el.clientWidth;
    const height = this.el.clientHeight;
    if (!width || !height) {
      this.pendingRender = true;
      if (!this.retryTimer) {
        this.retryTimer = setTimeout(() => this.render(true), 160);
      }
      return;
    }
    const theme = document.documentElement.classList.contains('dark') ? 'dark' : 'light';
    if (this.chart) {
      try { this.chart.dispose(); } catch (_) {}
      this.chart = null;
    }
    const chart = this.ensureChart(theme);
    if (!chart) return;
    const palette = this.palette();

    let option;
    if (chartData.type === 'category') {
      option = this.categoryOption(chartData, palette, theme);
    } else {
      option = this.timeseriesOption(chartData, palette, theme);
    }
    chart.setOption(option, true);
    requestAnimationFrame(() => {
      if (this.chart && typeof this.chart.resize === 'function') {
        try { this.chart.resize(); } catch (_) {}
      }
    });

    this.pendingRender = false;
  },
  parseChart() {
    const raw = this.el.dataset.chart || '';
    if (!raw) return null;
    try {
      const chart = JSON.parse(raw);
      chart.type = (chart.type || '').toLowerCase();
      chart.dataset = chart.dataset || {};
      return chart;
    } catch (_) {
      return null;
    }
  },
  palette() {
    const raw = this.el.dataset.colors || '[]';
    try {
      const colors = JSON.parse(raw);
      if (Array.isArray(colors) && colors.length) return colors;
    } catch (_) {}
    return ["#14b8a6", "#f59e0b", "#8b5cf6", "#06b6d4", "#10b981"];
  },
  ensureChart(theme) {
    if (this.chart) {
      const hasVisual = this.el && this.el.querySelector('canvas, svg');
      if (!hasVisual) {
        try { this.chart.dispose(); } catch (_) {}
        this.chart = null;
      }
    }

    if (this.chart) {
      try {
        const dom = typeof this.chart.getDom === 'function' ? this.chart.getDom() : null;
        if (!dom || dom !== this.el) {
          this.chart.dispose();
          this.chart = null;
        }
      } catch (_) {
        this.chart = null;
      }
    }

    if (this.chart && this.theme === theme) {
      if (this.el.clientWidth === 0 || this.el.clientHeight === 0) {
        this.scheduleRetry();
        return null;
      }
      return this.chart;
    }
    if (this.chart && typeof this.chart.dispose === 'function') {
      try { this.chart.dispose(); } catch (_) {}
    }
    this.chart = null;
    if (this.el.clientWidth === 0 || this.el.clientHeight === 0) {
      this.scheduleRetry();
      return null;
    }
    this.chart = echarts.init(this.el, theme === 'dark' ? 'dark' : undefined, withChartOpts());
    this.theme = theme;
    return this.chart;
  },
  scheduleRetry() {
    if (this.retryTimer) return;
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null;
      this.render(true);
    }, 160);
  },
  timeseriesOption(chartData, palette, theme) {
    const dataset = chartData.dataset || {};
    const seriesConfig = Array.isArray(dataset.series) ? dataset.series : [];
    const chartType = (dataset.chart_type || 'line').toLowerCase();
    const stacked = !!dataset.stacked;
    const showLegend = dataset.legend === undefined ? seriesConfig.length > 1 : !!dataset.legend;
    const textColor = theme === 'dark' ? '#9CA3AF' : '#6B7280';
    const axisLineColor = theme === 'dark' ? '#374151' : '#E5E7EB';
    const gridLineColor = theme === 'dark' ? '#1F2937' : '#E5E7EB';
    const legendText = theme === 'dark' ? '#D1D5DB' : '#374151';
    const yLabel = dataset.y_label || '';

    const series = seriesConfig.map((entry, idx) => {
      const dataPoints = Array.isArray(entry.data) ? entry.data : [];
      const sanitized = dataPoints.map((point) => {
        const toNumber = (val) => {
          const num = Number(val);
          return Number.isFinite(num) ? num : 0;
        };

        if (Array.isArray(point)) {
          const ts = toNumber(point[0]);
          const value = toNumber(point[1]);
          return [ts, value];
        }

        if (typeof point === 'object' && point !== null) {
          const ts = toNumber(point.at ?? point[0]);
          const value = toNumber(point.value ?? point[1]);
          return [ts, value];
        }

        const ts = toNumber(point);
        return [ts, 0];
      });

      const base = {
        name: entry.name || `Series ${idx + 1}`,
        type: chartType === 'bar' ? 'bar' : 'line',
        data: sanitized,
        smooth: chartType !== 'bar',
        showSymbol: false,
        emphasis: { focus: 'series' }
      };

      if (chartType === 'area') base.areaStyle = { opacity: 0.12 };
      if (stacked) base.stack = 'total';
      if (chartType === 'bar') base.barMaxWidth = 26;
      if (palette.length) base.itemStyle = { color: palette[idx % palette.length] };

      return base;
    });

    const gridBottom = showLegend ? 64 : 36;

    return {
      color: palette,
      animation: false,
      tooltip: {
        trigger: 'axis',
        axisPointer: { type: chartType === 'bar' ? 'shadow' : 'cross' }
      },
      legend: showLegend
        ? { bottom: 0, textStyle: { color: legendText } }
        : { show: false },
      grid: { left: 48, right: 20, top: 20, bottom: gridBottom },
      xAxis: {
        type: 'time',
        boundaryGap: chartType === 'bar',
        axisLabel: { color: textColor },
        axisLine: { lineStyle: { color: axisLineColor } },
        splitLine: { lineStyle: { color: gridLineColor } }
      },
      yAxis: {
        type: 'value',
        name: yLabel || null,
        nameLocation: 'end',
        nameTextStyle: { color: textColor, padding: [0, 0, 0, 8] },
        axisLabel: { color: textColor },
        axisLine: { lineStyle: { color: axisLineColor } },
        splitLine: { lineStyle: { color: gridLineColor } }
      },
      series
    };
  },
  categoryOption(chartData, palette, theme) {
    const dataset = chartData.dataset || {};
    const data = Array.isArray(dataset.data) ? dataset.data : [];
    const chartType = (dataset.chart_type || 'bar').toLowerCase();
    const textColor = theme === 'dark' ? '#9CA3AF' : '#475569';
    const axisLineColor = theme === 'dark' ? '#374151' : '#E5E7EB';

    if (chartType === 'pie' || chartType === 'donut') {
      return {
        color: palette,
        animation: false,
        tooltip: { trigger: 'item' },
        legend: {
          orient: 'vertical',
          left: 'left',
          textStyle: { color: textColor }
        },
        series: [
          {
            type: 'pie',
            radius: chartType === 'donut' ? ['45%', '80%'] : ['0%', '72%'],
            center: ['55%', '55%'],
            data: data.map((entry, idx) => {
              const numeric = Number(entry.value ?? 0);
              const value = Number.isFinite(numeric) ? numeric : 0;
              return {
                value,
                name: entry.name || `Slice ${idx + 1}`
              };
            }),
            label: { color: textColor }
          }
        ]
      };
    }

    const categories = data.map((entry) => entry.name || '');
    const values = data.map((entry, idx) => {
      const numeric = Number(entry.value ?? 0);
      const value = Number.isFinite(numeric) ? numeric : 0;
      return {
        value,
        itemStyle: { color: palette[idx % palette.length] }
      };
    });

    return {
      color: palette,
      animation: false,
      tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
      grid: { left: 48, right: 20, top: 20, bottom: 32 },
      xAxis: {
        type: 'category',
        data: categories,
        axisLabel: { color: textColor },
        axisLine: { lineStyle: { color: axisLineColor } }
      },
      yAxis: {
        type: 'value',
        axisLabel: { color: textColor },
        axisLine: { lineStyle: { color: axisLineColor } },
        splitLine: { lineStyle: { color: axisLineColor } }
      },
      series: [
        {
          type: 'bar',
          data: values,
          barWidth: 32
        }
      ]
    };
  },
  createResizeObserver() {
    if (typeof ResizeObserver !== 'function') return;
    if (this.resizeObserver) return;
    this.resizeObserver = new ResizeObserver((entries) => {
      if (!Array.isArray(entries)) return;
      const entry = entries[0];
      if (!entry) return;
      const { width, height } = entry.contentRect || {};
      if (width > 0 && height > 0) {
        if (this.pendingRender) {
          this.pendingRender = false;
          this.render(true);
        } else if (this.chart && typeof this.chart.resize === 'function') {
          try { this.chart.resize(); } catch (_) {}
        }
      }
    });
    try {
      this.resizeObserver.observe(this.el);
    } catch (_) {
      this.destroyResizeObserver();
    }
  },
  destroyResizeObserver() {
    if (this.resizeObserver && typeof this.resizeObserver.disconnect === 'function') {
      try { this.resizeObserver.disconnect(); } catch (_) {}
    }
    this.resizeObserver = null;
  }
}


Hooks.DatabaseExploreChart = {
  _resolveTheme() {
    return document.documentElement.classList.contains('dark') ? 'dark' : 'default';
  },

  _normalizeColors(colors) {
    if (Array.isArray(colors)) return colors;
    if (typeof colors === 'string') {
      try { return JSON.parse(colors); } catch (_) { return []; }
    }
    return [];
  },

  _parseJson(value, fallback) {
    try {
      return value ? JSON.parse(value) : fallback;
    } catch (_) {
      return fallback;
    }
  },

  _bindThemeListener() {
    if (this._themeListenerBound) return;
    this._themeListenerBound = true;
    this.handleEvent('phx:theme-changed', () => this._handleThemeChanged());
  },

  _handleThemeChanged() {
    if (!this.chart || this.chart.isDisposed()) return;
    const themeName = this._resolveTheme();
    if (themeName !== this._currentThemeName && typeof this.chart.setTheme === 'function') {
      try {
        this.chart.setTheme(themeName);
        this._currentThemeName = themeName;
      } catch (_) {}
    }

    this._refreshChartFromDataset();
  },

  _buildOption(data, key, chartType, colors, selectedKeyColor) {
    const themeName = this._resolveTheme();
    const isDarkMode = themeName === 'dark';
    const colorArray = this._normalizeColors(colors);

    const isStacked = chartType === 'stacked';
    let series;
    if (isStacked) {
      series = (data && data.length > 0) ? data.map((seriesData, index) => ({
        name: seriesData.name,
        type: 'bar',
        stack: 'total',
        data: seriesData.data,
        itemStyle: {
          color: colorArray.length ? colorArray[index % colorArray.length] : undefined
        }
      })) : [];
    } else {
      const seriesColor = selectedKeyColor || colorArray[0];
      series = [{
        name: key || 'Data',
        type: 'bar',
        data: data || [],
        itemStyle: {
          color: seriesColor
        }
      }];
    }

    const textColor = isDarkMode ? '#9CA3AF' : '#6B7280';
    const axisLineColor = isDarkMode ? '#374151' : '#E5E7EB';

    return {
      backgroundColor: 'transparent',
      grid: {
        top: 8,
        bottom: 12,
        left: 32,
        right: 8,
        containLabel: true
      },
      textStyle: {
        color: textColor
      },
      tooltip: {
        trigger: 'item',
        axisPointer: {
          type: 'shadow'
        },
        backgroundColor: isDarkMode ? '#1F2937' : '#FFFFFF',
        borderColor: isDarkMode ? '#374151' : '#E5E7EB',
        textStyle: {
          color: isDarkMode ? '#F3F4F6' : '#1F2937'
        },
        appendToBody: true,
        extraCssText: 'z-index: 9999;',
        formatter: function(params) {
          const date = new Date(params.value[0]);
          const dateStr = echarts.format.formatTime('yyyy-MM-dd hh:mm:ss', date, false);
          const value = formatCompactNumber(params.value[1]);
          return `${dateStr}<br/>${params.marker} ${params.seriesName}: ${value}`;
        }
      },
      xAxis: {
        type: 'time',
        axisLine: {
          lineStyle: {
            color: axisLineColor
          }
        },
        axisLabel: {
          color: textColor,
          margin: 6,
          formatter: function(value) {
            const date = new Date(value);
            const hours = date.getHours();
            const minutes = date.getMinutes();

            if (hours === 0 && minutes === 0) {
              return echarts.format.formatTime('MM-dd', value, false);
            }
            return echarts.format.formatTime('hh:mm', value, false);
          }
        },
        splitLine: {
          show: false
        }
      },
      yAxis: {
        type: 'value',
        min: 0,
        axisLine: {
          lineStyle: {
            color: axisLineColor
          }
        },
        axisLabel: {
          color: textColor,
          margin: 6,
          formatter: (value) => formatCompactNumber(value)
        },
        splitLine: {
          lineStyle: {
            color: axisLineColor
          }
        }
      },
      series,
      animation: true,
      animationDuration: 300
    };
  },

  _applyOption(option) {
    if (!this.chart || this.chart.isDisposed() || !option) return;
    try {
      this.chart.setOption(option, true);
      this.chart.resize();
    } catch (_) {}
  },

  _refreshChartFromDataset() {
    if (!this.chart || this.chart.isDisposed()) return;
    const data = this._parseJson(this.el.dataset.events, []);
    const key = this.el.dataset.key;
    const chartType = this.el.dataset.chartType;
    const colors = this._parseJson(this.el.dataset.colors, []);
    const selectedKeyColor = this.el.dataset.selectedKeyColor;

    const option = this._buildOption(data, key, chartType, colors, selectedKeyColor);
    this._applyOption(option);
  },

  createChart(data, key, timezone, chartType, colors, selectedKeyColor) {
    // Initialize ECharts instance
    const themeName = this._resolveTheme();
    const initTheme = themeName === 'dark' ? 'dark' : undefined;
    const container = document.getElementById('timeline-chart');
    if (container) {
      container.style.height = '140px';
      container.style.width = '100%';
    }

    // Set theme based on dark mode
    this.chart = echarts.init(container, initTheme, withChartOpts({ height: 140 }));
    this._currentThemeName = themeName;
    this._bindThemeListener();

    // Build and apply the base option
    const option = this._buildOption(data, key, chartType, colors, selectedKeyColor);
    this._applyOption(option);

    // Handle window resize
    this.resizeHandler = () => {
      if (this.chart && !this.chart.isDisposed()) {
        this.chart.resize();
      }
    };
    window.addEventListener('resize', this.resizeHandler);
    
    // Handle theme changes
    return this.chart;
  },

  mounted() {
    let data = JSON.parse(this.el.dataset.events);
    let key = this.el.dataset.key;
    let timezone = this.el.dataset.timezone;
    let chartType = this.el.dataset.chartType;
    let colors = JSON.parse(this.el.dataset.colors);
    let selectedKeyColor = this.el.dataset.selectedKeyColor;

    this.currentChartType = chartType;
    this.chart = this.createChart(data, key, timezone, chartType, colors, selectedKeyColor);
  },

  updated() {
    let data = JSON.parse(this.el.dataset.events);
    let key = this.el.dataset.key;
    let timezone = this.el.dataset.timezone;
    let chartType = this.el.dataset.chartType;
    let colors = JSON.parse(this.el.dataset.colors);
    let selectedKeyColor = this.el.dataset.selectedKeyColor;

    // Check if chart type changed - if so, recreate the entire chart
    if (this.currentChartType !== chartType) {
      if (this.chart && !this.chart.isDisposed()) {
        this.chart.dispose();
      }
      this.chart = this.createChart(data, key, timezone, chartType, colors, selectedKeyColor);
      this.currentChartType = chartType;
      return;
    }

    // Update existing chart with new data
    if (this.chart && !this.chart.isDisposed()) {
      const option = this._buildOption(data, key, chartType, colors, selectedKeyColor);
      this._applyOption(option);
    }
  },

  destroyed() {
    // Remove resize handler
    if (this.resizeHandler) {
      window.removeEventListener('resize', this.resizeHandler);
    }

    // Dispose chart
    if (this.chart && !this.chart.isDisposed()) {
      this.chart.dispose();
    }
  }
}

Hooks.TableHover = {
  mounted() {
    this.initHover();
  },
  
  updated() {
    this.initHover();
  },
  
  initHover() {
    const table = this.el;
    
    // Add hover listeners to data cells (not headers or row headers)
    const dataCells = table.querySelectorAll('td[data-row][data-col]');
    
    dataCells.forEach(cell => {
      cell.addEventListener('mouseenter', (e) => {
        const row = e.target.dataset.row;
        const col = e.target.dataset.col;
        
        // Detect if we're in dark mode
        const isDarkMode = document.documentElement.classList.contains('dark');
        const highlightColor = isDarkMode ? '#334155' : '#f9fafb';
        
        // Highlight current cell's row header with important style
        const rowHeader = table.querySelector(`td[data-row="${row}"]:not([data-col])`);
        if (rowHeader) {
          rowHeader.style.backgroundColor = highlightColor;
          rowHeader.classList.add('table-highlight');
        }
        
        // Highlight current cell's column header
        const colHeader = table.querySelector(`th[data-col="${col}"]`);
        if (colHeader) {
          colHeader.style.backgroundColor = highlightColor;
          colHeader.classList.add('table-highlight');
        }
        
        // Highlight all cells in the same column
        const colCells = table.querySelectorAll(`td[data-col="${col}"]`);
        colCells.forEach(colCell => {
          colCell.style.backgroundColor = highlightColor;
          colCell.classList.add('table-highlight');
        });
        
        // Highlight all cells in the same row
        const rowCells = table.querySelectorAll(`td[data-row="${row}"]`);
        rowCells.forEach(rowCell => {
          rowCell.style.backgroundColor = highlightColor;
          rowCell.classList.add('table-highlight');
        });
      });
      
      cell.addEventListener('mouseleave', (e) => {
        // Remove all highlights
        table.querySelectorAll('.table-highlight').forEach(el => {
          el.style.backgroundColor = '';
          el.classList.remove('table-highlight');
        });
      });
    });
  }
}

Hooks.Sortable = {
  mounted() {
    const group = this.el.dataset.group;
    const handle = this.el.dataset.handle;
    const eventName = this.el.dataset.event || "reorder_transponders";
    
    const groupName = group || 'default';
    // Restrict cross-type moves: only allow within same named group
    const groupOpt = { name: groupName, pull: [groupName], put: [groupName] };

    this.lastTo = null;
    this.lastHeader = null;

    this.sortable = Sortable.create(this.el, {
      group: groupOpt,
      handle: handle,
      draggable: '[data-id]',
      animation: 150,
      ghostClass: 'sortable-ghost',
      chosenClass: 'sortable-chosen',
      dragClass: 'sortable-drag',
      emptyInsertThreshold: 5,
      onMove: (evt, originalEvent) => {
        try {
          // Highlight drop container
          if (this.lastTo && this.lastTo !== evt.to) {
            this.lastTo.style.backgroundColor = '';
          }
          evt.to.style.backgroundColor = 'rgba(20,184,166,0.08)';
          this.lastTo = evt.to;

          // Highlight corresponding group header if present
          const pid = evt.to.dataset.parentId;
          if (pid) {
            const header = document.querySelector(`[data-group-header="${pid}"]`);
            if (this.lastHeader && this.lastHeader !== header) {
              this.lastHeader.style.backgroundColor = '';
            }
            if (header) {
              header.style.backgroundColor = 'rgba(20,184,166,0.10)';
              this.lastHeader = header;
            }
          }
        } catch (_) {}
      },
      onEnd: (evt) => {
        const parentId = evt.to.dataset.parentId || null;
        const fromParentId = evt.from.dataset.parentId || null;
        const movedId = evt.item && evt.item.dataset ? evt.item.dataset.id : null;
        const movedType = evt.item && evt.item.dataset ? evt.item.dataset.type : null;

        if (eventName === 'reorder_transponders') {
          const ids = Array.from(evt.to.children).map(child => child.dataset.id).filter(Boolean);
          this.pushEvent(eventName, { ids });
        } else {
          // Mixed nodes payload with type info
          const items = Array.from(evt.to.children)
            .map(child => (child.dataset && child.dataset.id) ? { id: child.dataset.id, type: child.dataset.type } : null)
            .filter(Boolean);
          const fromItems = Array.from(evt.from.children)
            .map(child => (child.dataset && child.dataset.id) ? { id: child.dataset.id, type: child.dataset.type } : null)
            .filter(Boolean);
          this.pushEvent(eventName, { items, parent_id: parentId, from_items: fromItems, from_parent_id: fromParentId, moved_id: movedId, moved_type: movedType });
        }

        // Clear highlights
        try {
          if (this.lastTo) this.lastTo.style.backgroundColor = '';
          if (this.lastHeader) this.lastHeader.style.backgroundColor = '';
          this.lastTo = null;
          this.lastHeader = null;
        } catch (_) {}
      }
    });
  },
  
  destroyed() {
    if (this.sortable) {
      this.sortable.destroy();
    }
  }
}

// Collapsible Dashboard Groups: sync collapsed state to localStorage
Hooks.DashboardGroupsCollapse = {
  mounted() {
    const dbId = this.el.dataset.dbId || 'default';
    const key = `dashboard_group_collapsed_${dbId}`;
    let map = {};
    try { map = JSON.parse(localStorage.getItem(key) || '{}'); } catch (_) { map = {}; }
    const ids = Object.keys(map).filter(id => map[id]);
    try { this.pushEvent('set_collapsed_groups', { ids }); } catch (_) {}
    this.handleEvent('save_collapsed_groups', ({ ids }) => {
      const store = {};
      (ids || []).forEach(id => { store[id] = true; });
      try { localStorage.setItem(key, JSON.stringify(store)); } catch (_) {}
    });
  }
}

// GridStack layout for Dashboards
Hooks.DashboardGrid = {
  mounted() {
    // colors palette for sparklines
    try {
      this.colors = this.el.dataset.colors ? JSON.parse(this.el.dataset.colors) : [];
    } catch (_) {
      this.colors = [];
    }
    this._sparklines = {};
    this._sparkTypes = {};
    this._tsCharts = {};
    this._catCharts = {};
    this._distCharts = {};
    this._tableCache = {};
    this._lastKpiValues = [];
    this._lastKpiVisuals = [];
    this._lastTimeseries = [];
    this._lastCategory = [];
    this._lastDistribution = [];
    this._lastTable = [];
    this._lastText = [];
    this._lastList = [];

    // Global window resize handler to resize all charts
    this._onWindowResize = () => {
      try {
        // Apply responsive column toggle if available
        if (typeof this._applyResponsiveGrid === 'function') {
          this._applyResponsiveGrid();
        }
        if (this._sparklines) {
          Object.values(this._sparklines).forEach(c => c && !c.isDisposed() && c.resize());
        }
        if (this._tsCharts) {
          Object.values(this._tsCharts).forEach(c => c && !c.isDisposed() && c.resize());
        }
        if (this._catCharts) {
          Object.values(this._catCharts).forEach(c => c && !c.isDisposed() && c.resize());
        }
        if (this._distCharts) {
          Object.values(this._distCharts).forEach(c => c && !c.isDisposed() && c.resize());
        }
        this._resizeAgGridTables();
      } catch (_) {}
    };
    window.addEventListener('resize', this._onWindowResize);
    // Avoid persisting transient responsive changes when navigating away
    const hideableLoadingKinds = new Set(['patch', 'redirect']);
    this._gridHiddenForLoading = false;
    this._onPageLoadingStart = (event) => {
      const kind = event && event.detail && event.detail.kind;
      if (kind && !hideableLoadingKinds.has(kind)) return;
      this._suppressSave = true;
      this._gridHiddenForLoading = true;
      if (this.el) {
        this.el.classList.remove('opacity-100');
        this.el.classList.add('opacity-0', 'pointer-events-none');
      }
    };
    window.addEventListener('phx:page-loading-start', this._onPageLoadingStart);
    this._onPageLoadingStop = (event) => {
      const kind = event && event.detail && event.detail.kind;
      if (kind && !hideableLoadingKinds.has(kind) && !this._gridHiddenForLoading) return;
      this._suppressSave = false;
      if (this.el) {
        this.el.classList.remove('opacity-0', 'pointer-events-none');
        this.el.classList.add('opacity-100');
      }
      this._gridHiddenForLoading = false;
      // ensure widgets remain in sync after LiveView patches
      requestAnimationFrame(() => {
        try {
          this.syncServerRenderedItems();
          if (typeof this._applyResponsiveGrid === 'function') {
            this._applyResponsiveGrid();
          }
        } catch (_) {}
      });
    };
    window.addEventListener('phx:page-loading-stop', this._onPageLoadingStop);
    this._sparkTimers = {};
    const editableAttr = this.el.dataset.editable;
    this.editable = (editableAttr === 'true' || editableAttr === '' || editableAttr === '1');
    this.cols = parseInt(this.el.dataset.cols || '12', 10);
    this.minRows = parseInt(this.el.dataset.minRows || '8', 10);
    this.addBtnId = this.el.dataset.addBtnId;
    try {
      this.initialItems = this.el.dataset.initialGrid ? JSON.parse(this.el.dataset.initialGrid) : [];
    } catch (_) {
      this.initialItems = [];
    }
    this._widgetRegistry = {
      kpiValues: {},
      kpiVisuals: {},
      timeseries: {},
      category: {},
      table: {},
      text: {},
      list: {}
    };
    this._aggridTables = {};
    this._aggridResizeTimers = {};
    this._aggridThemeIsDark = document.documentElement.classList.contains('dark');
    this.el.__dashboardGrid = this;

    // Determine renderer/devicePixelRatio for charts (SVG for print exports for crisp output)
    const printMode = (this.el.dataset.printMode === 'true' || this.el.dataset.printMode === '');
    this._chartInitOpts = (extra = {}) => {
      const base = printMode ? { devicePixelRatio: Math.max(2, ECHARTS_DEVICE_PIXEL_RATIO) } : {};
      return withChartOpts(Object.assign({}, base, extra));
    };

    this.initGrid();
    this.syncServerRenderedItems();

    const revealGrid = () => {
      if (!this.el) return;
      this.el.classList.remove('opacity-0', 'pointer-events-none');
      this.el.classList.add('opacity-100');
    };

    requestAnimationFrame(() => requestAnimationFrame(revealGrid));

    // Ensure multi-column layout during export (print mode)
    try {
      if (printMode && this.grid && typeof this.grid.column === 'function') {
        this._suppressSave = true;
        this.grid.column(this.cols);
        // Disable responsive one-column toggling for print
        this._applyResponsiveGrid = () => {};
      }
    } catch (_) { /* noop */ }

    // Toggle to one column on MD and smaller screens
    // Tailwind defaults: md=768px, lg=1024px; we want < lg (i.e., MD and below)
    this._applyResponsiveGrid = () => {
      if (!this.grid) return;
      const oneCol = window.innerWidth < 1024; // MD and below
      if (oneCol !== this._isOneCol) {
        this._isOneCol = oneCol;
        try {
          // Avoid persisting layout while switching responsive columns
          this._suppressSave = true;
          if (typeof this.grid.column === 'function') {
            this.grid.column(oneCol ? 1 : this.cols);
          }
          // Disable reordering/resizing when only 1 column to avoid breaking 12-col layout
          if (this.editable) {
            if (typeof this.grid.enableMove === 'function') {
              this.grid.enableMove(!oneCol);
              if (typeof this.grid.enableResize === 'function') {
                this.grid.enableResize(!oneCol);
              }
            } else if (typeof this.grid.setStatic === 'function') {
              // Fallback: set static when oneCol, re-enable when multi-col
              this.grid.setStatic(oneCol);
            }
          }
        } catch (_) {
          // noop
        } finally {
          this._suppressSave = false;
        }
      }
    };
    // Apply once on mount
    this._applyResponsiveGrid();

    // If server precomputed items for print mode, render immediately
    try { this.initialKpiValues = this.el.dataset.initialKpiValues ? JSON.parse(this.el.dataset.initialKpiValues) : []; } catch (_) { this.initialKpiValues = []; }
    try {
      if (this.el.dataset.initialKpiVisual) {
        this.initialKpiVisual = JSON.parse(this.el.dataset.initialKpiVisual);
      } else {
        this.initialKpiVisual = [];
      }
    } catch (_) { this.initialKpiVisual = []; }
    try { this.initialTimeseries = this.el.dataset.initialTimeseries ? JSON.parse(this.el.dataset.initialTimeseries) : []; } catch (_) { this.initialTimeseries = []; }
    try { this.initialCategory = this.el.dataset.initialCategory ? JSON.parse(this.el.dataset.initialCategory) : []; } catch (_) { this.initialCategory = []; }
    try { this.initialText = this.el.dataset.initialText ? JSON.parse(this.el.dataset.initialText) : []; } catch (_) { this.initialText = []; }
    try { this.initialList = this.el.dataset.initialList ? JSON.parse(this.el.dataset.initialList) : []; } catch (_) { this.initialList = []; }
    if ((this.initialKpiValues && this.initialKpiValues.length) || (this.initialKpiVisual && this.initialKpiVisual.length) || (this.initialTimeseries && this.initialTimeseries.length) || (this.initialCategory && this.initialCategory.length) || (this.initialText && this.initialText.length) || (this.initialList && this.initialList.length)) {
      setTimeout(() => {
        try {
          if (this.initialKpiValues && this.initialKpiValues.length) this._render_kpi_values(this.initialKpiValues);
          if (this.initialKpiVisual && this.initialKpiVisual.length) this._render_kpi_visuals(this.initialKpiVisual);
          if (this.initialTimeseries && this.initialTimeseries.length) this._render_timeseries(this.initialTimeseries);
          if (this.initialCategory && this.initialCategory.length) this._render_category(this.initialCategory);
          if (this.initialText && this.initialText.length) this._render_text(this.initialText);
          if (this.initialList && this.initialList.length) this._render_list(this.initialList);
        } catch (e) { console.error('initial print render failed', e); }
      }, 0);
    }

    // Ready signaling for export capture
    this._seen = { kpi_values: false, kpi_visual: false, timeseries: false, category: false, text: false, table: false, list: false, distribution: false };
    this._markedReady = false;

    this._onThemeChange = (event) => {
      const theme = event && event.detail && event.detail.theme;
      const isDark = theme ? theme === 'dark' : document.documentElement.classList.contains('dark');
      this._applyThemeToCharts(isDark);
    };
    window.addEventListener('trifle:theme-changed', this._onThemeChange);
    this._applyThemeToCharts(document.documentElement.classList.contains('dark'));

    // Delegate click for Add Widget button to survive DOM patches
    if (this.editable && this.addBtnId) {
      this._docClick = (e) => {
        const btn = e.target && (e.target.id === this.addBtnId ? e.target : e.target.closest && e.target.closest(`#${this.addBtnId}`));
        if (btn) {
          e.preventDefault();
          this.addNewWidget();
        }
      };
      document.addEventListener('click', this._docClick, true);
    }

    // Handle edit button clicks inside grid
    this._gridClick = (e) => {
      const expandBtn = e.target && (e.target.closest && e.target.closest('.grid-widget-expand'));
      if (expandBtn) {
        e.preventDefault();
        const id = expandBtn.getAttribute('data-widget-id');
        if (id) this.pushEvent('expand_widget', { id });
        return;
      }
      const editBtn = e.target && (e.target.closest && e.target.closest('.grid-widget-edit'));
      if (editBtn) {
        e.preventDefault();
        const id = editBtn.getAttribute('data-widget-id');
        if (id) this.pushEvent('open_widget_editor', { id });
      }
    };
    this.el.addEventListener('click', this._gridClick, true);

    // Ready signaling helpers for export (used by CDP waiter)
    try {
      window.TRIFLE_READY = false;
      const requireChartsReady = () => {
        const rawNodes = Array.from(document.querySelectorAll('.ts-chart, .cat-chart, .kpi-visual'));
        const chartNodes = rawNodes.filter((node) => {
          if (!node) return false;
          if (node.classList && node.classList.contains('kpi-visual')) {
            const hasVisual = node.dataset && node.dataset.visualType && node.dataset.visualType !== '';
            const isHidden = node.offsetParent === null || getComputedStyle(node).display === 'none';
            return hasVisual && !isHidden;
          }
          return true;
        });

        if (chartNodes.length === 0) {
        return this._seen.timeseries || this._seen.category || this._seen.text || this._seen.list || this._seen.distribution || (this._seen.kpi_values && this._seen.kpi_visual);
        }

        return chartNodes.every((node) => node.dataset && node.dataset.echartsReady === '1');
      };

      this._scheduleReadyMark = () => {
        if (this._markedReady) return;
        if (this._readyTimer) clearTimeout(this._readyTimer);
        this._readyTimer = setTimeout(() => {
          try {
            if (this._markedReady) return;
            if (requireChartsReady()) {
              this._markedReady = true;
              requestAnimationFrame(() => requestAnimationFrame(() => { window.TRIFLE_READY = true; }));
            }
          } catch (_) {}
        }, 120);
      };
    } catch (_) {}

    // LiveView -> Hook updates for widget edits/deletes
    this.handleEvent('dashboard_grid_widget_updated', ({ id, title }) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${id}"]`);
      const content = item && item.querySelector('.grid-stack-item-content');
      const titleEl = item && item.querySelector('.grid-widget-title');
      const isTextWidget = content && content.dataset.textWidget === '1';

      if (titleEl) {
        if (isTextWidget) {
          const rawTitle = title || '';
          content.dataset.widgetTitle = rawTitle;
          titleEl.dataset.originalTitle = rawTitle;
          titleEl.textContent = '';
          titleEl.setAttribute('aria-hidden', 'true');
          titleEl.style.opacity = '0';
          titleEl.style.pointerEvents = 'none';
        } else {
          if (content) delete content.dataset.widgetTitle;
          titleEl.dataset.originalTitle = title || '';
          titleEl.removeAttribute('aria-hidden');
          titleEl.style.opacity = '';
          titleEl.style.pointerEvents = '';
          titleEl.textContent = title;
        }
      }

      // ensure layout save reflects new title when we're in multi-column mode
      if (!this._isOneCol) {
        this.saveLayout();
      }
    });
    this.handleEvent('dashboard_grid_widget_deleted', ({ id }) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${id}"]`);
      if (item) {
        const content = item.querySelector('.grid-stack-item-content');
        const type = content && content.dataset && content.dataset.widgetType;
        this.grid.removeWidget(item);
        this.unregisterWidget(type || null, id);
        this.saveLayout();
      } else {
        this.unregisterWidget(null, id);
      }
    });

  },

  updated() {
    this.syncServerRenderedItems();
  },

  destroyed() {
    if (this.el) {
      this.el.classList.remove('opacity-100');
      this.el.classList.add('opacity-0', 'pointer-events-none');
    }

    if (this.el && this.el.__dashboardGrid === this) {
      delete this.el.__dashboardGrid;
    }
    this._widgetRegistry = null;
    if (this.grid && this.grid.destroy) {
      this.grid.destroy(false);
    }
    if (this._docClick) {
      document.removeEventListener('click', this._docClick, true);
      this._docClick = null;
    }
    if (this._gridClick) {
      this.el.removeEventListener('click', this._gridClick, true);
      this._gridClick = null;
    }
    if (this._sparkResize) {
      window.removeEventListener('resize', this._sparkResize);
      this._sparkResize = null;
    }
    if (this._onWindowResize) {
      window.removeEventListener('resize', this._onWindowResize);
      this._onWindowResize = null;
    }
    if (this._onPageLoadingStart) {
      window.removeEventListener('phx:page-loading-start', this._onPageLoadingStart);
      this._onPageLoadingStart = null;
    }
    if (this._onPageLoadingStop) {
      window.removeEventListener('phx:page-loading-stop', this._onPageLoadingStop);
      this._onPageLoadingStop = null;
    }
    if (this._sparklines) {
      Object.values(this._sparklines).forEach((c) => {
        if (c && !c.isDisposed()) c.dispose();
      });
      this._sparklines = {};
    }
    if (this._tsCharts) {
      Object.values(this._tsCharts).forEach((c) => {
        if (c && !c.isDisposed()) c.dispose();
      });
      this._tsCharts = {};
    }
    if (this._catCharts) {
      Object.values(this._catCharts).forEach((c) => {
        if (c && !c.isDisposed()) c.dispose();
      });
      this._catCharts = {};
    }
    if (this._distCharts) {
      Object.values(this._distCharts).forEach((c) => {
        if (c && !c.isDisposed()) c.dispose();
      });
      this._distCharts = {};
    }
    if (this._aggridTables) {
      Object.keys(this._aggridTables).forEach((id) => this._destroy_aggrid_table(id));
      this._aggridTables = {};
    }
    if (this._aggridResizeTimers) {
      Object.keys(this._aggridResizeTimers).forEach((key) => {
        try { clearTimeout(this._aggridResizeTimers[key]); } catch (_) {}
        delete this._aggridResizeTimers[key];
      });
    }
    if (this._onThemeChange) {
      window.removeEventListener('trifle:theme-changed', this._onThemeChange);
      this._onThemeChange = null;
    }
  },

  initGrid() {
    const hasServerRenderedItems = !!this.el.querySelector('.grid-stack-item');
    // Pre-populate items into DOM only when server hasn’t rendered them
    if (!hasServerRenderedItems && Array.isArray(this.initialItems) && this.initialItems.length > 0) {
      this.initialItems.forEach((item) => this.addGridItemEl(item));
    }

    const customCellHeight = parseInt(this.el.dataset.printCellHeight || '', 10);
    const resolvedCellHeight = (this.el.dataset.printMode === 'true' && customCellHeight > 0)
      ? customCellHeight
      : 80;

    this.grid = GridStack.init({
      column: this.cols,
      minRow: this.minRows,
      float: true,
      margin: 5,
      disableOneColumnMode: true,
      styleInHead: true,
      cellHeight: resolvedCellHeight,
      // drag only by the title bar (between title and cog button)
      draggable: { handle: '.grid-widget-handle' },
    }, this.el);
    this._cellHeight = resolvedCellHeight;

    if (!this.editable) {
      this.grid.setStatic(true);
    }

    const save = () => this.saveLayout();
    const resizeCharts = () => {
      if (this._sparklines) {
        Object.values(this._sparklines).forEach(c => c && !c.isDisposed() && c.resize());
      }
      if (this._tsCharts) {
        Object.values(this._tsCharts).forEach(c => c && !c.isDisposed() && c.resize());
      }
      if (this._catCharts) {
        Object.values(this._catCharts).forEach(c => c && !c.isDisposed() && c.resize());
      }
      if (this._distCharts) {
        Object.values(this._distCharts).forEach(c => c && !c.isDisposed() && c.resize());
      }
      this._resizeAgGridTables();
    };
    this.grid.on('change', () => { if (!this._suppressSave && !this._isOneCol && document.visibilityState !== 'hidden') save(); resizeCharts(); });
    this.grid.on('added', () => { if (!this._isOneCol) save(); resizeCharts(); });
    this.grid.on('removed', () => { if (!this._isOneCol) save(); resizeCharts(); });

    // No direct button binding needed; delegated handler set in mounted
  },

  // Reusable renderers (used by LiveView events and initial print rendering)
  _render_kpi_values(items) {
    if (!Array.isArray(items)) return;

    const formatNumber = (value) => {
      if (value === null || value === undefined || value === '') return '—';
      const n = Number(value);
      if (!Number.isFinite(n)) return String(value);
      if (Math.abs(n) >= 1000) {
        const units = ['', 'K', 'M', 'B', 'T'];
        let idx = 0;
        let num = Math.abs(n);
        while (num >= 1000 && idx < units.length - 1) {
          num /= 1000;
          idx += 1;
        }
        const sign = n < 0 ? '-' : '';
        return `${sign}${num.toFixed(num < 10 ? 2 : 1)}${units[idx]}`;
      }
      return n.toFixed(2).replace(/\.00$/, '');
    };

    const toNumber = (value) => {
      if (value === null || value === undefined || value === '') return null;
      const n = Number(value);
      return Number.isFinite(n) ? n : null;
    };

    const formatPercent = (ratio) => {
      if (ratio === null || ratio === undefined) return '—';
      const pct = Number(ratio) * 100;
      if (!Number.isFinite(pct)) return '—';
      const abs = Math.abs(pct);
      const decimals = abs < 10 ? 1 : 0;
      return `${pct.toFixed(decimals).replace(/\.0$/, '')}%`;
    };

    items.forEach((it) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
      const body = item && item.querySelector('.grid-widget-body');
      if (!body) return;

      body.classList.remove('items-center', 'justify-center', 'text-sm', 'text-gray-500', 'dark:text-slate-400');
      body.classList.add('flex-col', 'items-stretch');

      const sizeClass = (() => {
        const sz = (it.size || 'm');
        if (sz === 's') return 'text-2xl';
        if (sz === 'l') return 'text-4xl';
        return 'text-3xl';
      })();

      let wrap = body.querySelector('.kpi-wrap');
      if (!wrap) {
        body.innerHTML = `<div class="kpi-wrap w-full flex flex-col flex-1 grow" style="min-height: 0; gap: 12px;"><div class="kpi-top px-3"></div><div class="kpi-meta px-3" style="display: none;"></div><div class="kpi-visual" style="margin-top: auto; height: 40px; width: 100%; margin-left: 0; margin-right: 0; margin-bottom: 0;"></div></div>`;
        wrap = body.querySelector('.kpi-wrap');
      }
      if (!wrap) return;

      wrap.classList.add('flex', 'flex-col', 'flex-1', 'grow');
      wrap.classList.remove('justify-center');
      wrap.style.minHeight = '0';

      const top = wrap.querySelector('.kpi-top');
      const meta = wrap.querySelector('.kpi-meta');
      const visual = wrap.querySelector('.kpi-visual');

      const subtype = String(it.subtype || 'number').toLowerCase();
      const hasVisual = !!it.has_visual;
      const visualType = hasVisual && it.visual_type ? String(it.visual_type).toLowerCase() : null;
      wrap.style.gap = (subtype === 'goal' && hasVisual && visualType === 'progress') ? '6px' : '12px';

      if (meta) {
        meta.innerHTML = '';
        meta.style.display = 'none';
        meta.style.marginTop = '0';
        meta.style.marginBottom = '0';
      }

      if (visual) {
        if (!hasVisual) {
          visual.style.display = 'none';
          delete visual.dataset.visualType;
          visual.dataset.echartsReady = '1';
          const chart = this._sparklines && this._sparklines[it.id];
          if (chart && !chart.isDisposed()) chart.dispose();
          if (this._sparklines) delete this._sparklines[it.id];
          if (this._sparkTimers && this._sparkTimers[it.id]) {
            clearTimeout(this._sparkTimers[it.id]);
            delete this._sparkTimers[it.id];
          }
          if (this._sparkTypes) delete this._sparkTypes[it.id];
        } else {
          visual.style.display = '';
          visual.dataset.echartsReady = '0';
          visual.dataset.visualType = visualType || 'sparkline';
          if (visualType !== 'progress') {
            visual.style.marginTop = 'auto';
            visual.style.height = '40px';
            visual.style.width = '100%';
            visual.style.marginLeft = '0';
            visual.style.marginRight = '0';
            visual.style.marginBottom = '0';
          }
        }
      }

      if (!top) return;

      if (subtype === 'split') {
        const previous = toNumber(it.previous);
        const current = toNumber(it.current);
        const prevLabel = formatNumber(it.previous);
        const currLabel = formatNumber(it.current);
        const showDiff = !!it.show_diff && previous !== null && current !== null && previous !== 0;
        let diffHtml = '';
        if (showDiff) {
          const delta = current - previous;
          const pct = (delta / Math.abs(previous)) * 100;
          const up = delta >= 0;
          const pctText = `${Math.abs(pct).toFixed(Math.abs(pct) < 10 ? 2 : 1)}%`;
          const clrWrap = up ? 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200' : 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200';
          const arrow = up
            ? '<span class="inline-block align-middle" style="width:0;height:0;border-left:4px solid transparent;border-right:4px solid transparent;border-bottom:6px solid currentColor;line-height:0"></span>'
            : '<span class="inline-block align-middle" style="width:0;height:0;border-left:4px solid transparent;border-right:4px solid transparent;border-top:6px solid currentColor;line-height:0"></span>';
          diffHtml = `<span class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium leading-none whitespace-nowrap ${clrWrap}">${arrow}<span class="sr-only"> ${up ? 'Increased' : 'Decreased'} by </span><span>${pctText}</span></span>`;
        }

        top.innerHTML = `
          <div class="w-full">
            <div class="flex items-baseline justify-between w-full">
              <div class="flex flex-wrap items-baseline gap-x-2 ${sizeClass} font-bold text-gray-900 dark:text-white">
                <span>${currLabel}</span>
                <span class="text-sm font-medium text-gray-500 dark:text-slate-400">from ${prevLabel}</span>
              </div>
              ${diffHtml}
            </div>
          </div>`;
        if (meta) meta.style.display = 'none';
      } else if (subtype === 'goal') {
        const valueLabel = formatNumber(it.value);
        const targetLabel = formatNumber(it.target);
        const ratio = toNumber(it.progress_ratio != null ? it.progress_ratio : it.ratio);
        const invertGoal = !!it.invert;
        const showProgress = hasVisual && visualType === 'progress';
        const goalValue = targetLabel && targetLabel !== '—' ? targetLabel : '';
        const badge = goalValue
          ? `<div class="flex flex-col items-end gap-1 text-right">
              <span class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium leading-none whitespace-nowrap bg-slate-100 text-slate-700 dark:bg-slate-800/70 dark:text-slate-200">Goal</span>
              ${showProgress ? '' : `<span class="text-sm font-medium text-gray-500 dark:text-slate-400">${goalValue}</span>`}
            </div>`
          : '';

        top.innerHTML = `
          <div class="w-full">
            <div class="flex items-baseline justify-between w-full">
              <div class="flex flex-wrap items-baseline gap-x-2 ${sizeClass} font-bold text-gray-900 dark:text-white">
                <span>${valueLabel}</span>
              </div>
              ${badge}
            </div>
          </div>`;

        if (meta && showProgress) {
          const pctText = formatPercent(ratio);
          const goalText = goalValue || '';
          meta.style.display = 'flex';
          meta.style.alignItems = 'baseline';
          meta.style.justifyContent = 'space-between';
          meta.style.gap = '8px';
          meta.style.marginTop = 'auto';
          meta.style.marginBottom = '-8px';
          const goalMarkup = goalText
            ? `<span class="text-sm font-medium text-gray-500 dark:text-slate-400">${goalText}</span>`
            : '';
          let statusClass;
          if (ratio == null) {
            statusClass = 'text-gray-700 dark:text-slate-200';
          } else if (invertGoal) {
            statusClass = ratio <= 1 ? 'text-teal-600 dark:text-teal-300' : 'text-red-600 dark:text-red-300';
          } else {
            statusClass = ratio >= 1 ? 'text-green-600 dark:text-green-300' : 'text-teal-600 dark:text-teal-300';
          }
          meta.innerHTML = `
            <span class="text-sm font-semibold ${statusClass}">${pctText}</span>
            ${goalMarkup}`;
          if (visual && visual.dataset.visualType === 'progress') {
            visual.style.marginTop = '-10px';
          }
        }
      } else {
        const val = formatNumber(it.value);
        top.innerHTML = `<div class="${sizeClass} font-bold text-gray-900 dark:text-white">${val}</div>`;
        if (meta) meta.style.display = 'none';
      }
    });
    this._lastKpiValues = this._deepClone(items);
  },

  _render_kpi_visuals(items) {
    if (!Array.isArray(items)) return;
    const isDarkMode = document.documentElement.classList.contains('dark');
    const lineColor = (this.colors && this.colors[0]) || '#14b8a6';
    items.forEach((it) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
      const body = item && item.querySelector('.grid-widget-body');
      if (!body) return;
      const wrap = body.querySelector('.kpi-wrap');
      if (!wrap) return;

      let visual = wrap.querySelector('.kpi-visual');
      if (!visual) {
        visual = document.createElement('div');
        visual.className = 'kpi-visual';
        wrap.appendChild(visual);
      }

      const type = (it.type || 'sparkline').toLowerCase();
      this._sparkTypes[it.id] = type;

      const ensureClass = (mode) => {
        visual.className = `kpi-visual ${mode === 'progress' ? 'kpi-progress' : 'kpi-spark'}`;
        if (mode === 'progress') {
          visual.style.marginTop = '4px';
          visual.style.height = '20px';
          visual.style.width = '100%';
          visual.style.marginLeft = '0';
          visual.style.marginRight = '0';
          visual.style.marginBottom = '0';
        } else {
          visual.style.marginTop = 'auto';
          visual.style.height = '40px';
          visual.style.width = '100%';
          visual.style.marginLeft = '0';
          visual.style.marginRight = '0';
          visual.style.marginBottom = '0';
        }
        visual.dataset.visualType = mode;
        visual.dataset.echartsReady = '0';
      };

      ensureClass(type);

      const render = () => {
        let chart = this._sparklines[it.id];
        const initTheme = isDarkMode ? 'dark' : undefined;
       if (!chart) {
         if (visual.clientWidth === 0 || visual.clientHeight === 0) {
           if (this._sparkTimers && this._sparkTimers[it.id]) clearTimeout(this._sparkTimers[it.id]);
           if (this._sparkTimers) {
             this._sparkTimers[it.id] = setTimeout(render, 80);
           }
           return;
         }
         chart = echarts.init(visual, initTheme, withChartOpts({ height: type === 'progress' ? 20 : 40 }));
         this._sparklines[it.id] = chart;
       }
       if (this._sparkTimers && this._sparkTimers[it.id]) delete this._sparkTimers[it.id];

        if (type === 'progress') {
          const currentNum = Number.isFinite(Number(it.current)) ? Math.max(Number(it.current), 0) : 0;
          const rawTarget = Number(isFinite(Number(it.target)) ? Number(it.target) : null);
          const targetNum = Number.isFinite(rawTarget) ? Math.max(rawTarget, 0) : null;
          const axisMax = Math.max(targetNum ?? 0, currentNum, 1);
          const baseValue = targetNum == null || targetNum === 0 ? axisMax : targetNum;
          const ratio = Number.isFinite(Number(it.ratio)) ? Number(it.ratio) : (targetNum && targetNum !== 0 ? currentNum / targetNum : null);
          const invertGoal = !!it.invert;
          let progressColor;
          if (ratio == null) {
            progressColor = lineColor;
          } else if (invertGoal) {
            progressColor = ratio <= 1 ? lineColor : '#ef4444';
          } else {
            progressColor = ratio >= 1 ? '#22c55e' : lineColor;
          }
          const background = isDarkMode ? '#1f2937' : '#E5E7EB';
          chart.setOption({
            backgroundColor: 'transparent',
            grid: { top: 0, bottom: 0, left: 0, right: 0, containLabel: false },
            xAxis: { type: 'value', show: false, min: 0, max: axisMax },
            yAxis: { type: 'category', show: false, data: [''] },
            series: [
              { type: 'bar', data: [baseValue], barWidth: 10, silent: true, itemStyle: { color: background, borderRadius: 5 }, animation: false, barGap: '-100%', barCategoryGap: '60%' },
              { type: 'bar', data: [currentNum], barWidth: 10, itemStyle: { color: progressColor, borderRadius: 5 }, animation: false, z: 3 }
            ]
          }, true);
        } else {
          chart.setOption({
            backgroundColor: 'transparent',
            grid: { top: 0, bottom: 0, left: 0, right: 0 },
            xAxis: { type: 'time', show: false },
            yAxis: { type: 'value', show: false },
            tooltip: { show: false },
            series: [{
              type: 'line',
              data: Array.isArray(it.data) ? it.data : [],
              smooth: true,
              showSymbol: false,
              lineStyle: { width: 1, color: lineColor },
              areaStyle: { color: lineColor, opacity: 0.08 },
            }],
            animation: false
          }, true);
        }
       try {
         chart.off('finished');
         chart.on('finished', () => {
           try { visual.dataset.echartsReady = '1'; this._scheduleReadyMark(); } catch (_) {}
         });
       } catch (_) {}
       chart.resize();

        if (!this._sparkResize) {
          this._sparkResize = () => {
            Object.values(this._sparklines || {}).forEach((c) => c && !c.isDisposed() && c.resize());
          };
          window.addEventListener('resize', this._sparkResize);
        }
      };

      if (this._sparkTimers && this._sparkTimers[it.id]) clearTimeout(this._sparkTimers[it.id]);
      if (!this._sparkTimers) this._sparkTimers = {};
      this._sparkTimers[it.id] = setTimeout(render, 0);
    });
    this._seen.kpi_visual = true; this._scheduleReadyMark();
    this._lastKpiVisuals = this._deepClone(items);
  },

  _render_timeseries(items) {
    if (!Array.isArray(items)) return;
    const isDarkMode = document.documentElement.classList.contains('dark');
    const colors = this.colors || [];
    items.forEach((it) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
      const body = item && item.querySelector('.grid-widget-body');
      if (!body) return;
      let container = body.querySelector('.ts-chart');
      if (!container) {
        body.innerHTML = '';
        body.classList.remove('items-center','justify-center','text-sm','text-gray-500','dark:text-slate-400');
        container = document.createElement('div');
        container.className = 'ts-chart';
        container.style.width = '100%';
        container.style.height = '100%';
        body.appendChild(container);
      }
      let chart = this._tsCharts[it.id];
      const initTheme = isDarkMode ? 'dark' : undefined;
      const ensureInit = () => {
        if (!chart) {
          if (container.clientWidth === 0 || container.clientHeight === 0) { setTimeout(ensureInit, 80); return; }
          chart = echarts.init(container, initTheme, withChartOpts());
          this._tsCharts[it.id] = chart;
        }
        const type = (it.chart_type || 'line');
        const stacked = !!it.stacked;
        const normalized = !!it.normalized;
        const textColor = isDarkMode ? '#9CA3AF' : '#6B7280';
        const axisLineColor = isDarkMode ? '#374151' : '#E5E7EB';
        const gridLineColor = isDarkMode ? '#1F2937' : '#E5E7EB';
        const legendText = isDarkMode ? '#D1D5DB' : '#374151';
        const showLegend = !!it.legend;
        const bottomPadding = showLegend ? 56 : 28;
        const chartFontFamily = 'Inter var, Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
        const overlayLabelBackground = isDarkMode ? 'rgba(15, 23, 42, 0.85)' : 'rgba(255, 255, 255, 0.92)';
        const overlayLabelText = isDarkMode ? '#F8FAFC' : '#0F172A';
        const series = (it.series || []).map((s, idx) => {
          const base = { name: s.name || `Series ${idx+1}`, type: (type === 'area') ? 'line' : type, data: s.data || [], showSymbol: false };
          if (stacked) base.stack = 'total';
          if (type === 'area') base.areaStyle = { opacity: 0.1 };
          const customColor = typeof s.color === 'string' && s.color.trim() !== '' ? s.color.trim() : null;
          const paletteColor = colors.length ? colors[idx % colors.length] : null;
          const appliedColor = customColor || paletteColor;
          if (appliedColor) {
            base.color = appliedColor;
            base.itemStyle = Object.assign({}, base.itemStyle, { color: appliedColor });
            base.lineStyle = Object.assign({}, base.lineStyle, { color: appliedColor });
            if (type === 'area') {
              base.areaStyle = Object.assign({ opacity: 0.1 }, { color: appliedColor });
            }
          }
          return base;
        });
        const overlay = it.alert_overlay || null;
        const alertStrategy = String(it.alert_strategy || '').toLowerCase();
        const shouldApplyAlertAxis = !!overlay && (alertStrategy === 'threshold' || alertStrategy === 'range');
        if (overlay && series.length) {
          const primarySeries = series[0];
          const markAreas = [];
          const defaultSegmentColor = 'rgba(248,113,113,0.22)';
          const defaultBandColor = 'rgba(16,185,129,0.08)';
          const defaultLineColor = '#f87171';
          const defaultPointColor = '#f97316';
          const isoValue = (iso, ts) => {
            if (iso) return iso;
            if (typeof ts === 'number') {
              const dt = new Date(ts);
              if (!Number.isNaN(dt.getTime())) return dt.toISOString();
            }
            return null;
          };
          if (Array.isArray(overlay.segments)) {
            overlay.segments.forEach((seg, index) => {
              const startIso = isoValue(seg.from_iso, seg.from_ts);
              let endIso = isoValue(seg.to_iso, seg.to_ts);
              if (startIso && endIso && startIso === endIso) {
                const adjusted = new Date(startIso);
                if (!Number.isNaN(adjusted.getTime())) {
                  adjusted.setMinutes(adjusted.getMinutes() + 1);
                  endIso = adjusted.toISOString();
                }
              }
              if (startIso && endIso) {
                const itemStyle = seg.color ? { color: seg.color } : { color: defaultSegmentColor };
                const label = seg.label || `Alert window #${index + 1}`;
                markAreas.push([
                  {
                    name: label,
                    xAxis: startIso,
                    itemStyle,
                    label: {
                      color: overlayLabelText,
                      fontFamily: chartFontFamily,
                      position: 'insideTop',
                      distance: 6,
                      overflow: 'break',
                      align: 'left',
                      backgroundColor: overlayLabelBackground,
                      padding: [2, 6],
                      borderRadius: 4
                    },
                    emphasis: { disabled: true }
                  },
                  {
                    xAxis: endIso
                  }
                ]);
              }
            });
          }
          if (Array.isArray(overlay.bands)) {
            overlay.bands.forEach((band) => {
              if (typeof band.min === 'number' && typeof band.max === 'number') {
                const itemStyle = band.color ? { color: band.color } : { color: defaultBandColor };
                const label = band.label || 'Target band';
                markAreas.push([
                  {
                    name: label,
                    yAxis: band.min,
                    xAxis: 'min',
                    itemStyle,
                    label: {
                      color: overlayLabelText,
                      fontFamily: chartFontFamily,
                      position: 'insideTop',
                      distance: 6,
                      overflow: 'break',
                      align: 'left',
                      backgroundColor: overlayLabelBackground,
                      padding: [2, 6],
                      borderRadius: 4
                    },
                    emphasis: { disabled: true }
                  },
                  {
                    yAxis: band.max,
                    xAxis: 'max'
                  }
                ]);
              }
            });
          }
          if (markAreas.length) {
            primarySeries.markArea = { data: markAreas, silent: true, emphasis: { disabled: true } };
          }
          if (Array.isArray(overlay.reference_lines) && overlay.reference_lines.length) {
            primarySeries.markLine = {
              symbol: 'none',
              silent: true,
              animation: false,
              emphasis: { disabled: true },
              data: overlay.reference_lines
                .filter((line) => typeof line.value === 'number')
                .map((line) => ({
                  yAxis: line.value,
                  name: line.label || formatCompactNumber(line.value),
                  lineStyle: {
                    color: line.color || defaultLineColor,
                    type: 'dashed',
                    width: 1.2
                  },
                  label: {
                    formatter: line.label || formatCompactNumber(line.value),
                    color: overlayLabelText,
                    fontFamily: chartFontFamily,
                    position: 'insideEndTop',
                    distance: 8,
                    overflow: 'break',
                    backgroundColor: overlayLabelBackground,
                    padding: [2, 6],
                    borderRadius: 4
                  },
                  emphasis: { disabled: true }
                }))
            };
          }
          if (Array.isArray(overlay.points)) {
            const markPoints = overlay.points
              .filter((point) => typeof point.value === 'number')
              .map((point, idx) => {
                const coordX = isoValue(point.at_iso, point.ts);
                if (!coordX) return null;
                const color = point.color || defaultPointColor;
                return {
                  coord: [coordX, point.value],
                  value: point.value,
                  name: point.label || `Alert point #${idx + 1}`,
                  itemStyle: { color },
                  label: {
                    color: overlayLabelText,
                    formatter: point.label || formatCompactNumber(point.value),
                    fontFamily: chartFontFamily,
                    position: 'top',
                    distance: 10,
                    backgroundColor: overlayLabelBackground,
                    padding: [2, 6],
                    borderRadius: 4,
                    overflow: 'truncate'
                  }
                };
              })
              .filter(Boolean);
            if (markPoints.length) {
              primarySeries.markPoint = {
                symbol: 'circle',
                symbolSize: 16,
                animation: false,
                silent: true,
                emphasis: { disabled: true },
                data: markPoints
              };
            }
          }
          const baselineSeries = []
            .concat(Array.isArray(it.alert_baseline_series) ? it.alert_baseline_series : [])
            .concat(overlay && Array.isArray(overlay.baseline_series) ? overlay.baseline_series : []);
          const seenBaselineKeys = new Set();
          baselineSeries
            .filter((baseline) => {
              if (!baseline || !Array.isArray(baseline.data) || baseline.data.length === 0) return false;
              const key = baseline.name || `${baseline.color || 'baseline'}-${baseline.line_type || 'line'}`;
              if (seenBaselineKeys.has(key)) return false;
              seenBaselineKeys.add(key);
              return true;
            })
            .forEach((baseline) => {
              const baselineData = Array.isArray(baseline.data) ? baseline.data : [];
              if (!baselineData.length) return;
              const baselineColor = baseline.color || overlayLabelText;
              const lineType = baseline.line_type || 'dashed';
              const lineWidth = typeof baseline.width === 'number' ? baseline.width : 1.3;
              const lineOpacity = typeof baseline.opacity === 'number' ? baseline.opacity : 0.85;
              series.push({
                name: baseline.name || 'Detection baseline',
                type: 'line',
                data: baselineData,
                showSymbol: false,
                smooth: false,
                connectNulls: true,
                animation: false,
                lineStyle: {
                  width: lineWidth,
                  type: lineType,
                  color: baselineColor,
                  opacity: lineOpacity
                },
                itemStyle: { color: baselineColor, opacity: lineOpacity },
                emphasis: { focus: 'series' },
                tooltip: {
                  valueFormatter: (v) => (v == null ? '-' : formatCompactNumber(v))
                },
                zlevel: 1,
                z: 25
              });
            });
        }
        const extractPointValue = (point) => {
          if (Array.isArray(point)) return Number(point[1]);
          if (point && typeof point === 'object') {
            if (Array.isArray(point.value)) return Number(point.value[1]);
            if ('value' in point) return Number(point.value);
          }
          if (Number.isFinite(point)) return Number(point);
          return null;
        };
        const updateBounds = (bounds, value) => {
          if (!Number.isFinite(value)) return;
          if (value < bounds.min) bounds.min = value;
          if (value > bounds.max) bounds.max = value;
        };
        const seriesBounds = { min: Infinity, max: -Infinity };
        series.forEach((s) => {
          (s.data || []).forEach((point) => updateBounds(seriesBounds, extractPointValue(point)));
        });
        let alertAxis = null;
        if (shouldApplyAlertAxis) {
          const overlayBounds = { min: Infinity, max: -Infinity };
          if (overlay) {
            if (Array.isArray(overlay.reference_lines)) {
              overlay.reference_lines.forEach((line) => updateBounds(overlayBounds, Number(line.value)));
            }
            if (Array.isArray(overlay.bands)) {
              overlay.bands.forEach((band) => {
                updateBounds(overlayBounds, Number(band.min));
                updateBounds(overlayBounds, Number(band.max));
              });
            }
            if (Array.isArray(overlay.points)) {
              overlay.points.forEach((point) => updateBounds(overlayBounds, Number(point.value)));
            }
          }
          const minCandidates = [seriesBounds.min, overlayBounds.min].filter(Number.isFinite);
          const maxCandidates = [seriesBounds.max, overlayBounds.max].filter(Number.isFinite);
          const positiveOnly = minCandidates.length === 0 || minCandidates.every((value) => value >= 0);
          let axisMinCandidate = minCandidates.length ? Math.min(...minCandidates) : (positiveOnly ? 0 : -1);
          let axisMaxCandidate = maxCandidates.length ? Math.max(...maxCandidates) : (axisMinCandidate > 0 ? axisMinCandidate : 1);
          if (Number.isFinite(axisMaxCandidate)) {
            if (!Number.isFinite(axisMinCandidate)) {
              axisMinCandidate = positiveOnly ? 0 : axisMaxCandidate;
            }
            alertAxis = { positiveOnly, axisMinCandidate, axisMaxCandidate };
          }
        }
        const yName = normalized ? (it.y_label || 'Percentage') : (it.y_label || '');
        const yAxis = {
          type: 'value',
          min: 0,
          name: yName,
          nameLocation: 'middle',
          nameGap: 40,
          nameTextStyle: { color: textColor, fontFamily: chartFontFamily },
          axisLine: { lineStyle: { color: axisLineColor } },
          axisLabel: { color: textColor, margin: 8, hideOverlap: true, fontFamily: chartFontFamily },
          splitLine: { lineStyle: { color: gridLineColor, opacity: isDarkMode ? 0.4 : 1 } }
        };
        if (normalized) {
          yAxis.axisLabel = Object.assign({}, yAxis.axisLabel, { formatter: (v) => `${v}%` });
          if (alertAxis) {
            const normalizedMax = Math.max(alertAxis.axisMaxCandidate, 100);
            const topPad = normalizedMax * 0.05 || 5;
            yAxis.min = 0;
            yAxis.max = normalizedMax + topPad;
          } else {
            yAxis.max = 100;
          }
        } else {
          yAxis.axisLabel = Object.assign({}, yAxis.axisLabel, {
            formatter: (v) => formatCompactNumber(v)
          });
          if (alertAxis) {
            let axisMin = alertAxis.positiveOnly ? 0 : alertAxis.axisMinCandidate;
            let axisMax = Math.max(alertAxis.axisMaxCandidate, axisMin + 1);
            if (!Number.isFinite(axisMin)) axisMin = 0;
            if (!Number.isFinite(axisMax)) axisMax = axisMin + 1;
            if (axisMax <= axisMin) axisMax = axisMin + Math.max(Math.abs(axisMin), 1);
            const span = axisMax - axisMin;
            const topPad = span * 0.12 || Math.max(Math.abs(axisMax), 1) * 0.12;
            const bottomPad = alertAxis.positiveOnly ? 0 : (span * 0.05 || topPad * 0.5);
            axisMax += topPad;
            axisMin -= bottomPad;
            if (alertAxis.positiveOnly && axisMin < 0) axisMin = 0;
            yAxis.min = axisMin;
            yAxis.max = axisMax;
          } else if (Number.isFinite(seriesBounds.min) && seriesBounds.min < 0) {
            const axisMin = seriesBounds.min;
            const axisMaxCandidate = Number.isFinite(seriesBounds.max) ? seriesBounds.max : 0;
            let axisMax = axisMaxCandidate;
            if (!Number.isFinite(axisMax) || axisMax <= axisMin) {
              axisMax = axisMin + Math.max(Math.abs(axisMin), 1);
            }
            const span = axisMax - axisMin;
            const pad = span * 0.1 || Math.max(Math.abs(axisMax), 1) * 0.1;
            yAxis.min = axisMin - pad * 0.4;
            yAxis.max = axisMax + pad;
          }
        }
        chart.setOption({
          backgroundColor: 'transparent',
          textStyle: { fontFamily: chartFontFamily },
          grid: { top: 12, bottom: bottomPadding, left: 56, right: 20, containLabel: true },
          xAxis: {
            type: 'time',
            axisLine: { lineStyle: { color: axisLineColor } },
            axisLabel: { color: textColor, margin: 8, hideOverlap: true, fontFamily: chartFontFamily },
            splitLine: { show: false }
          },
          yAxis,
          legend: showLegend ? { type: 'scroll', bottom: 4, textStyle: { color: legendText, fontFamily: chartFontFamily } } : { show: false },
          tooltip: {
            trigger: 'axis',
            appendToBody: true,
            textStyle: { fontFamily: chartFontFamily },
            valueFormatter: (v) => {
              if (v == null) return '-';
              if (normalized) {
                const pct = Number(v);
                return Number.isFinite(pct) ? `${pct.toFixed(2)}%` : '-';
              }
              return formatCompactNumber(v);
            }
          },
          series
        }, true);
        try {
          chart.off('finished');
          chart.on('finished', () => {
            try { container.dataset.echartsReady = '1'; this._scheduleReadyMark(); } catch (_) {}
          });
        } catch (_) {}
        chart.resize();
      };
      setTimeout(ensureInit, 0);
    });
    this._seen.timeseries = true;
    this._scheduleReadyMark();
    this._lastTimeseries = this._deepClone(items);
  },

  _render_category(items) {
    if (!Array.isArray(items)) return;
    const isDarkMode = document.documentElement.classList.contains('dark');
    const colors = this.colors || [];
    items.forEach((it) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
      const body = item && item.querySelector('.grid-widget-body');
      if (!body) return;
      let container = body.querySelector('.cat-chart');
      if (!container) {
        body.innerHTML = '';
        body.classList.remove('items-center','justify-center','text-sm','text-gray-500','dark:text-slate-400');
        container = document.createElement('div');
        container.className = 'cat-chart';
        container.style.width = '100%';
        container.style.height = '100%';
        body.appendChild(container);
      }
      let chart = this._catCharts[it.id];
      const initTheme = isDarkMode ? 'dark' : undefined;
      const ensureInit = () => {
        if (!chart) {
          if (container.clientWidth === 0 || container.clientHeight === 0) { setTimeout(ensureInit, 80); return; }
          chart = echarts.init(container, initTheme, withChartOpts());
          this._catCharts[it.id] = chart;
        }
        const data = it.data || [];
        const type = (it.chart_type || 'bar');
        let option;
        if (type === 'pie' || type === 'donut') {
          const labelColor = isDarkMode ? '#E5E7EB' : '#374151';
          const labelLineColor = isDarkMode ? '#475569' : '#9CA3AF';
          option = {
            backgroundColor: 'transparent',
            tooltip: {
              trigger: 'item',
              textStyle: { color: isDarkMode ? '#F3F4F6' : '#1F2937' },
              backgroundColor: isDarkMode ? '#1F2937' : '#FFFFFF',
              borderColor: isDarkMode ? '#4B5563' : '#E5E7EB',
              appendToBody: true
            },
            color: (colors && colors.length ? colors : undefined),
            series: [{
              type: 'pie',
              radius: (type === 'donut') ? ['50%', '70%'] : '70%',
              avoidLabelOverlap: true,
              data,
              label: { color: labelColor },
              labelLine: { lineStyle: { color: labelLineColor } },
              itemStyle: {
                color: (params) => (colors && colors.length)
                  ? colors[params.dataIndex % colors.length]
                  : params.color
              }
            }]
          };
        } else {
          option = {
            backgroundColor: 'transparent',
            grid: { top: 12, bottom: 28, left: 48, right: 16 },
            xAxis: { type: 'category', data: data.map((d) => d.name) },
            yAxis: {
              type: 'value',
              min: 0,
              axisLabel: {
                formatter: (v) => formatCompactNumber(v)
              }
            },
            tooltip: { trigger: 'axis', appendToBody: true },
            series: [{
              type: 'bar',
              data: data.map((d) => d.value),
              itemStyle: {
                color: (params) => colors[params.dataIndex % (colors.length || 1)] || '#14b8a6'
              }
            }]
          };
        }
        chart.setOption(option, true);
        try {
          chart.off('finished');
          chart.on('finished', () => {
            try { container.dataset.echartsReady = '1'; this._scheduleReadyMark(); } catch (_) {}
          });
        } catch (_) {}
        chart.resize();
      };
      setTimeout(ensureInit, 0);
    });
    this._seen.category = true;
    this._scheduleReadyMark();
    this._lastCategory = this._deepClone(items);
  },

  _render_distribution(items) {
    if (!Array.isArray(items)) return;
    const isDarkMode = document.documentElement.classList.contains('dark');
    const colors = this.colors || [];
    this._distCharts = this._distCharts || {};

    items.forEach((it) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
      const body = item && item.querySelector('.grid-widget-body');
      if (!body) return;

      const errors = Array.isArray(it.errors) ? it.errors.filter(Boolean) : [];
      if (errors.length) {
        body.innerHTML = `
          <div class="flex items-center justify-center text-sm text-red-600 dark:text-red-300 text-center px-3">
            ${this.escapeHtml(errors.join(', '))}
          </div>`;
        return;
      }

      const labels = Array.isArray(it.bucket_labels) ? it.bucket_labels : [];
      const verticalLabels = Array.isArray(it.vertical_bucket_labels) ? it.vertical_bucket_labels : [];
      const is3d = (it.mode || '').toLowerCase() === '3d';
      if (is3d) {
        if (!labels.length || !verticalLabels.length) {
          body.innerHTML = `
            <div class="flex items-center justify-center text-sm text-gray-500 dark:text-slate-400 text-center px-3">
              No 3D buckets available. Add both horizontal and vertical bucket definitions in the editor.
            </div>`;
          return;
        }
      } else {
        if (!labels.length) {
          body.innerHTML = `
            <div class="flex items-center justify-center text-sm text-gray-500 dark:text-slate-400 text-center px-3">
              No distribution buckets available. Add bucket definitions in the editor.
            </div>`;
          return;
        }
      }

      let container = body.querySelector('.distribution-chart');
      if (!container) {
        body.innerHTML = '';
        body.classList.remove('items-center', 'justify-center', 'text-sm', 'text-gray-500', 'dark:text-slate-400');
        container = document.createElement('div');
        container.className = 'distribution-chart';
        container.style.width = '100%';
        container.style.height = '100%';
        container.dataset.echartsReady = '0';
        body.appendChild(container);
      }

      let chart = this._distCharts[it.id];
      const initTheme = isDarkMode ? 'dark' : undefined;
      const ensureInit = () => {
        if (!chart || chart.isDisposed?.()) {
          const existing = echarts.getInstanceByDom(container);
          if (existing) {
            chart = existing;
          } else {
            if (container.clientWidth === 0 || container.clientHeight === 0) { setTimeout(ensureInit, 80); return; }
            chart = echarts.init(container, initTheme, withChartOpts());
          }
          this._distCharts[it.id] = chart;
        }

        const legendNames = [];
        const hasLegendData = Array.isArray(it.series) && it.series.length > 1;
        const showLegend = it.legend === undefined ? hasLegendData : !!it.legend;
        const bottomPadding = showLegend ? 56 : 20;

        let seriesData;
        if (is3d) {
          let maxValue = 0;
          seriesData = (Array.isArray(it.series) ? it.series : []).map((series, idx) => {
            const name = series && series.name ? series.name : `Series ${idx + 1}`;
            legendNames.push(name);
            const points = Array.isArray(series && series.points) ? series.points : [];
            const color = colors[idx % (colors.length || 1)] || colors[0] || '#14b8a6';
            const data = points.map((p) => {
              const xIndex = labels.indexOf(p.bucket_x);
              const yIndex = verticalLabels.indexOf(p.bucket_y);
              if (xIndex === -1 || yIndex === -1) return null;
              const val = Number(p.value) || 0;
              maxValue = Math.max(maxValue, val);
              return [xIndex, yIndex, val];
            }).filter(Boolean);
            return {
              name,
              type: 'scatter',
              data,
              symbolSize: (val) => {
                const v = val && val[2] ? val[2] : 0;
                if (!maxValue) return 10;
                const size = 8 + (v / maxValue) * 24;
                return Math.max(6, size);
              },
              itemStyle: { color, opacity: 1 },
              hoverAnimation: false,
              emphasis: {
                disabled: true,
                focus: 'none',
                scale: false,
                blurScope: 'none',
                itemStyle: { opacity: 1 }
              },
              select: { disabled: true }
            };
          });

          if (!seriesData.length) {
            const fallbackColor = colors[0] || '#14b8a6';
            seriesData = [{
              name: legendNames[0] || 'Series 1',
              type: 'scatter',
              data: [],
              symbolSize: () => 10,
              itemStyle: { color: fallbackColor, opacity: 1 },
              hoverAnimation: false,
              emphasis: {
                disabled: true,
                focus: 'none',
                scale: false,
                blurScope: 'none',
                itemStyle: { opacity: 1 }
              },
              select: { disabled: true }
            }];
          }

          const option = {
            backgroundColor: 'transparent',
            legend: showLegend
              ? {
                  data: legendNames,
                  textStyle: { color: isDarkMode ? '#E2E8F0' : '#0F172A', fontFamily: chartFontFamily },
                  bottom: 0,
                  type: legendNames.length > 4 ? 'scroll' : 'plain'
                }
              : { show: false },
            grid: { top: 16, left: 56, right: 16, bottom: bottomPadding },
            tooltip: {
              trigger: 'item',
              appendToBody: true,
              formatter: (params) => {
                const valueArr = Array.isArray(params.value) && params.value.length >= 3
                  ? params.value
                  : (Array.isArray(params.data) && params.data.length >= 3 ? params.data : null);

                if (!valueArr) return '';

                const xIdx = Number.isFinite(valueArr[0]) ? valueArr[0] : null;
                const yIdx = Number.isFinite(valueArr[1]) ? valueArr[1] : null;
                const val = Number.isFinite(valueArr[2]) ? valueArr[2] : 0;
                const xLabel = (xIdx != null && labels[xIdx]) ? labels[xIdx] : (labels[0] || '');
                const yLabel = (yIdx != null && verticalLabels[yIdx]) ? verticalLabels[yIdx] : (verticalLabels[0] || '');

                if (!xLabel && !yLabel) return '';

                const seriesName = params.seriesName || '';
                const marker = params.marker || '';
                const lines = [`${xLabel} × ${yLabel}`];

                if (seriesName || marker) {
                  lines.push(`${marker}${seriesName}  <strong>${formatCompactNumber(val)}</strong>`);
                }

                return lines.join('<br/>');
              }
            },
            axisPointer: {
              show: true,
              type: 'line',
              lineStyle: { type: 'dashed', color: isDarkMode ? '#94a3b8' : '#0f172a' },
              link: [{ xAxisIndex: 'all' }, { yAxisIndex: 'all' }]
            },
            grid: { top: 16, left: 64, right: 16, bottom: bottomPadding },
            xAxis: {
              type: 'category',
              data: labels,
              splitLine: { show: true, lineStyle: { type: 'dashed', color: isDarkMode ? '#1f2937' : '#e2e8f0', opacity: isDarkMode ? 0.4 : 0.9 } },
              axisLabel: { color: isDarkMode ? '#CBD5F5' : '#475569', interval: 0, rotate: labels.length > 8 ? 30 : 0 }
            },
            yAxis: {
              type: 'category',
              data: verticalLabels,
              splitLine: { show: true, lineStyle: { type: 'dashed', color: isDarkMode ? '#1f2937' : '#e2e8f0', opacity: isDarkMode ? 0.4 : 0.9 } },
              axisLabel: { color: isDarkMode ? '#CBD5F5' : '#475569' }
            },
            series: seriesData
          };

          chart.setOption(option, true);
          try {
            chart.off('finished');
            chart.on('finished', () => {
              try { container.dataset.echartsReady = '1'; this._scheduleReadyMark(); } catch (_) {}
            });
          } catch (_) {}
          chart.resize();
          return;
        }

        seriesData = (Array.isArray(it.series) ? it.series : []).map((series, idx) => {
          const name = series && series.name ? series.name : `Series ${idx + 1}`;
          legendNames.push(name);
          const values = Array.isArray(series && series.values) ? series.values : [];
          const color = colors[idx % (colors.length || 1)] || colors[0] || '#14b8a6';
          const data = labels.map((label) => {
            const match = values.find((v) => v && v.bucket === label);
            return match && Number.isFinite(match.value) ? Number(match.value) : 0;
          });
          return {
            name,
            type: 'bar',
            emphasis: { focus: 'series' },
            itemStyle: { color },
            data
          };
        });

          const option = {
            backgroundColor: 'transparent',
            legend: showLegend
              ? {
                  data: legendNames,
                  textStyle: { color: isDarkMode ? '#E2E8F0' : '#0F172A', fontFamily: chartFontFamily },
                  bottom: 0,
                  type: legendNames.length > 4 ? 'scroll' : 'plain'
                }
              : { show: false },
            grid: { top: 16, left: 52, right: 16, bottom: bottomPadding },
            tooltip: {
              trigger: 'axis',
              axisPointer: {
                type: 'line',
                lineStyle: { color: isDarkMode ? '#CBD5F5' : '#94a3b8', width: 1.5, type: 'dashed' }
              },
              appendToBody: true,
              valueFormatter: (value) => formatCompactNumber(value)
            },
          xAxis: {
            type: 'category',
            data: labels,
            axisLabel: { color: isDarkMode ? '#CBD5F5' : '#475569', interval: 0, rotate: labels.length > 6 ? 30 : 0 }
          },
          yAxis: {
            type: 'value',
            min: 0,
            axisLabel: { formatter: (v) => formatCompactNumber(v), color: isDarkMode ? '#CBD5F5' : '#475569' },
            splitLine: { lineStyle: { color: isDarkMode ? '#1f2937' : '#e2e8f0', opacity: isDarkMode ? 0.35 : 1 } }
          },
          series: seriesData.length ? seriesData : [{
            name: 'Values',
            type: 'bar',
            itemStyle: { color: colors[0] || '#14b8a6' },
            data: labels.map(() => 0)
          }]
        };

        chart.setOption(option, true);
        try {
          chart.off('finished');
          chart.on('finished', () => {
            try { container.dataset.echartsReady = '1'; this._scheduleReadyMark(); } catch (_) {}
          });
        } catch (_) {}
        chart.resize();
      };
      setTimeout(ensureInit, 0);
    });

    this._seen.distribution = true;
    this._scheduleReadyMark();
    this._lastDistribution = this._deepClone(items);
  },

  _render_table(items) {
    if (!Array.isArray(items)) return;
    this._lastTable = this._deepClone(items);
    const seenAggridTables = new Set();

    items.forEach((it) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
      const body = item && item.querySelector('.grid-widget-body');
      if (!body) return;

      body.className = 'grid-widget-body flex-1 flex flex-col min-h-0';
      const tableId = this._tableKey(it.id);

      if (!it.rows || !it.rows.length || !it.columns || !it.columns.length) {
        this._destroy_aggrid_table(tableId);
        body.innerHTML = `<div class="h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 px-6 text-center">${this.escapeHtml(it.empty_message || 'No data available yet.')}</div>`;
        return;
      }

      body.innerHTML = this._build_aggrid_table_html(it);
      this._render_aggrid_table(body, it);
      if (tableId) seenAggridTables.add(tableId);
    });

    if (this._aggridTables) {
      Object.keys(this._aggridTables).forEach((id) => {
        if (!seenAggridTables.has(id)) {
          this._destroy_aggrid_table(id);
        }
      });
    }
  },

  _activate_tooltips_for_element(element) {
    if (!element || !Hooks || !Hooks.FastTooltip) return;
    const fastTooltip = Hooks.FastTooltip;
    if (typeof fastTooltip.initTooltips !== 'function') return;
    const context = {
      el: element,
      showTooltip: fastTooltip.showTooltip.bind(fastTooltip),
      hideTooltip: fastTooltip.hideTooltip.bind(fastTooltip)
    };
    requestAnimationFrame(() => {
      try {
        fastTooltip.initTooltips.call(context);
      } catch (_) {}
    });
  },


  _build_aggrid_table_html(payload) {
    const idAttr = payload && payload.id != null ? ` data-aggrid-id="${this.escapeHtml(String(payload.id))}"` : '';
    const rootId = payload && payload.id != null ? ` id="aggrid-table-${this.escapeHtml(String(payload.id))}"` : '';
    const theme = this._aggridThemeIsDark ? 'dark' : 'light';
    const themeClass = this._aggridThemeIsDark ? 'ag-theme-alpine-dark' : 'ag-theme-alpine';
    return `
      <div class="aggrid-table-shell flex-1 flex flex-col min-h-0" data-role="aggrid-table"${idAttr} data-theme="${theme}">
        <div class="flex-1 min-h-0 ${themeClass}" data-role="aggrid-table-root"${rootId}>
          <div class="h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 px-6 text-center">
            Loading AG Grid table...
          </div>
        </div>
      </div>
    `;
  },







  _render_aggrid_table(container, payload) {
    if (!payload) return;
    const root = container.querySelector('[data-role="aggrid-table-root"]');
    const tableId = this._tableKey(payload.id);
    if (!root || !tableId) return;

    if (!window.agGrid || typeof window.agGrid.Grid !== 'function') {
      ensureAgGridCommunity()
        .then(() => this._render_aggrid_table(container, payload))
        .catch((err) => console.error('[AGGrid] unable to load ag-grid-community', err));
      return;
    }

    if (root.clientWidth === 0 || root.clientHeight === 0) {
      if (!this._aggridResizeTimers) this._aggridResizeTimers = {};
      if (this._aggridResizeTimers[tableId]) clearTimeout(this._aggridResizeTimers[tableId]);
      this._aggridResizeTimers[tableId] = setTimeout(() => this._render_aggrid_table(container, payload), 60);
      return;
    }

    let entry = this._aggridTables && this._aggridTables[tableId];
    if (!entry || entry.root !== root || !entry.api) {
      this._destroy_aggrid_table(tableId);
      entry = this._create_aggrid_table(root);
      this._aggridTables[tableId] = entry;
    }

    const dataset = this._prepare_table_dataset(payload);
    entry.dataset = dataset;
    entry.payload = payload;
    entry.pathKey = dataset.pathKey;

    const schema = Array.isArray(dataset.schema) ? dataset.schema : [];
    const originalColumns = Array.isArray(payload.columns) ? payload.columns : [];
    const columnDefs = schema.map((col, idx) => {
      const isPathColumn = idx === 0;
      const sourceLabel = (
        isPathColumn
          ? (col.title || col.name || 'Path')
          : ((originalColumns[idx - 1] && originalColumns[idx - 1].label) || col.title || col.name || '')
      ).toString();
      const headerLines = sourceLabel
        .split(/<br\s*\/?>/i)
        .map((segment) => this._strip_html(segment))
        .map((line) => line.replace(/\s+/g, ' ').trim())
        .filter((line) => line !== '');
      const resolvedHeader = headerLines.length ? headerLines.join('\n') : this._strip_html(sourceLabel);
      const headerAlignment = idx === 0 ? 'left' : 'right';
      const baseDef = {
        field: col.name,
        headerName: resolvedHeader,
        headerTooltip: headerLines.join(' · ') || resolvedHeader,
        sortable: false,
        filter: false,
        resizable: false,
        suppressMenu: true,
        suppressMovable: true,
        minWidth: isPathColumn ? AGGRID_PATH_COL_MIN_WIDTH : 120,
        maxWidth: isPathColumn ? AGGRID_PATH_COL_MAX_WIDTH : undefined,
        cellClass: [
          col.align === 'right' ? 'ag-right-aligned-cell' : 'ag-left-aligned-cell',
          'aggrid-body-cell'
        ].join(' '),
        headerClass: [
          headerAlignment === 'right' ? 'ag-right-aligned-header' : 'ag-left-aligned-header',
          'aggrid-header-cell'
        ].join(' ')
      };
      baseDef.headerComponentParams = { lines: headerLines, align: headerAlignment };
      if (!isPathColumn) {
        baseDef.flex = 1;
      }
      if (isPathColumn) {
        baseDef.width = AGGRID_PATH_COL_MIN_WIDTH;
        baseDef.suppressSizeToFit = true;
        baseDef.resizable = true;
      }
      if (col.name === dataset.pathKey) {
        baseDef.cellRenderer = (params) => {
          if (params && params.data && params.data.__placeholder) {
            const empty = document.createElement('div');
            empty.className = 'aggrid-path-cell';
            empty.innerHTML = '&nbsp;';
            return empty;
          }
          const value = (params && params.value != null) ? params.value : '';
          const pathHtml = params && params.data ? params.data[TABLE_PATH_HTML_FIELD] : '';
          const wrapper = document.createElement('div');
          wrapper.className = 'aggrid-path-cell';
          if (pathHtml && typeof pathHtml === 'string') {
            wrapper.innerHTML = pathHtml;
          } else {
            wrapper.textContent = value == null ? '' : String(value);
          }
          return wrapper;
        };
        baseDef.cellClass += ' aggrid-path-cell-wrapper';
      }
      if (col.type === 'number') {
        baseDef.valueFormatter = (params) => {
          if (params && params.data && params.data.__placeholder) return '';
          const value = params && params.value;
          if (value === undefined || value === null || value === '') return '';
          const numeric = Number(value);
          if (!Number.isFinite(numeric)) return String(value);
          return numeric.toLocaleString(undefined, { maximumFractionDigits: 2 });
        };
        baseDef.type = 'numericColumn';
        baseDef.cellClass += ' aggrid-numeric-cell';
      }
      if (idx === 0) {
        baseDef.pinned = 'left';
        baseDef.lockPinned = true;
        baseDef.suppressMovable = true;
        baseDef.cellClass += ' aggrid-path-pinned';
      }
      return baseDef;
    });

    const filledRows = Array.isArray(dataset.rows) ? dataset.rows.map((row) => Object.assign({}, row)) : [];
    const rowHeight = entry.gridOptions && entry.gridOptions.rowHeight ? entry.gridOptions.rowHeight : 28;
    const headerHeight = entry.gridOptions && entry.gridOptions.headerHeight ? entry.gridOptions.headerHeight : 48;
    const containerHeight = container && container.clientHeight ? container.clientHeight : root.clientHeight;
    const bodyEl = container.closest('.grid-widget-body');
    const widgetEl = container.closest('.grid-stack-item');
    const bodyHeight = bodyEl ? bodyEl.clientHeight : containerHeight;
    const gridUnits = widgetEl ? parseInt(widgetEl.getAttribute('gs-h') || '0', 10) : 0;
    const estimatedWidgetHeight = gridUnits > 0 && this && this._cellHeight ? gridUnits * this._cellHeight : bodyHeight;
    const measuredHeight = Math.max(containerHeight || 0, bodyHeight || 0);
    const desiredHeight = measuredHeight > 0 ? measuredHeight : (estimatedWidgetHeight || 0);
    const availableHeight = Math.max(desiredHeight - headerHeight, 0);
    const estimatedRowsFromHeight = rowHeight > 0 ? Math.ceil(availableHeight / rowHeight) : 0;
    const minRows = Math.max(estimatedRowsFromHeight, 10);
    let fillerCount = 0;
    if (minRows > filledRows.length) {
      fillerCount = minRows - filledRows.length;
      for (let i = 0; i < fillerCount; i += 1) {
        const filler = { __placeholder: true };
        filler[dataset.pathKey] = '';
        filler[TABLE_PATH_HTML_FIELD] = '';
        schema.forEach((col) => {
          if (col && col.name) filler[col.name] = '';
        });
        filledRows.push(filler);
      }
    }

    const tableShell = container && container.querySelector('.aggrid-table-shell');
    if (tableShell) {
      if (fillerCount > 0) {
        tableShell.setAttribute('data-fillers', '1');
      } else {
        tableShell.removeAttribute('data-fillers');
      }
    }

    try {
      entry.gridOptions.api.setColumnDefs(columnDefs);
      entry.gridOptions.api.setRowData(filledRows);
      entry.gridOptions.api.refreshCells({ force: true });
      setTimeout(() => {
        this._auto_size_aggrid_path_column(entry, dataset.pathKey);
        try { entry.gridOptions.api.sizeColumnsToFit(); } catch (_) {}
        this._activate_tooltips_for_element(root);
      }, 0);
    } catch (err) {
      console.error('[AGGrid] failed to render grid', err);
    }
    this._apply_aggrid_theme_to_entry(entry);
  },

  _auto_size_aggrid_path_column(entry, pathKey) {
    if (!entry || !entry.columnApi || !pathKey) return;
    const column = entry.columnApi.getColumn(pathKey);
    if (!column) return;
    try {
      entry.columnApi.autoSizeColumns([pathKey], false);
    } catch (_) {}
    const colDef = column.getColDef ? column.getColDef() : null;
    const minWidth = (colDef && Number.isFinite(colDef.minWidth)) ? colDef.minWidth : AGGRID_PATH_COL_MIN_WIDTH;
    const maxWidth = (colDef && Number.isFinite(colDef.maxWidth)) ? colDef.maxWidth : AGGRID_PATH_COL_MAX_WIDTH;
    let width = null;
    try {
      width = column.getActualWidth ? column.getActualWidth() : null;
    } catch (_) {
      width = null;
    }
    if (!Number.isFinite(width)) return;
    const clamped = Math.max(minWidth || AGGRID_PATH_COL_MIN_WIDTH, Math.min(maxWidth || AGGRID_PATH_COL_MAX_WIDTH, width));
    if (clamped !== width) {
      try { entry.columnApi.setColumnWidth(column, clamped); } catch (_) {}
    }
  },

  _create_aggrid_table(root) {
    root.innerHTML = '';
    root.style.width = '100%';
    root.style.height = '100%';
    root.style.width = '100%';
    root.style.height = '100%';
    const agGrid = window.agGrid;
    const gridOptions = {
      columnDefs: [],
      rowData: [],
      suppressCellFocus: true,
      suppressMovableColumns: true,
      suppressRowClickSelection: true,
      rowSelection: 'single',
      animateRows: false,
      rowHeight: 28,
      headerHeight: 48,
      enableRangeSelection: true,
      enableCellTextSelection: true,
      getRowClass: (params) => (params && params.data && params.data.__placeholder ? 'aggrid-placeholder-row' : ''),
      defaultColDef: {
        sortable: false,
        filter: false,
        resizable: false,
        flex: 1,
        headerComponent: getAggridHeaderComponentClass()
      }
    };
    new agGrid.Grid(root, gridOptions);
    const entry = {
      gridOptions,
      api: gridOptions.api,
      columnApi: gridOptions.columnApi,
      root,
      shell: root.closest('[data-role="aggrid-table"]') || null
    };
    if (typeof ResizeObserver !== 'undefined') {
      entry.resizeObserver = new ResizeObserver(() => {
        const dataset = entry.dataset;
        const payload = entry.payload;
        const container = entry.shell;
        if (dataset && payload && container) {
          if (entry._resizeRendering) return;
          entry._resizeRendering = true;
          try {
            this._render_aggrid_table(container, payload);
          } catch (err) {
            console.error('[AGGrid] resize render error', err);
          } finally {
            entry._resizeRendering = false;
          }
        } else if (entry.api && typeof entry.api.sizeColumnsToFit === 'function') {
          try { entry.api.sizeColumnsToFit(); } catch (_) {}
        }
      });
      try { entry.resizeObserver.observe(root); } catch (_) {}
    }
    this._apply_aggrid_theme_to_entry(entry);
    return entry;
  },

  _destroy_aggrid_table(id) {
    if (!this._aggridTables || !id || !this._aggridTables[id]) return;
    const entry = this._aggridTables[id];
    if (entry && entry.resizeObserver) {
      try { entry.resizeObserver.disconnect(); } catch (_) {}
      entry.resizeObserver = null;
    }
    if (entry && entry.api && typeof entry.api.destroy === 'function') {
      try { entry.api.destroy(); } catch (_) {}
    }
    delete this._aggridTables[id];
    if (this._aggridResizeTimers && this._aggridResizeTimers[id]) {
      clearTimeout(this._aggridResizeTimers[id]);
      delete this._aggridResizeTimers[id];
    }
  },

  _prepare_table_dataset(payload) {
    const columns = Array.isArray(payload.columns) ? payload.columns : [];
    const headerLabels = ['Path'].concat(
      columns.map((col) => this._strip_html(col && col.label ? col.label : ''))
    );
    const normalizedHeaders = this._ensure_unique_labels(headerLabels);

    const rows = Array.isArray(payload.rows)
      ? payload.rows.map((row) => {
          const obj = {};
          normalizedHeaders.forEach((header, idx) => {
            if (idx === 0) {
              obj[header] = row.display_path || row.path || '';
              obj[TABLE_PATH_HTML_FIELD] = row.path_html || (row.display_path || row.path || '');
            } else {
              const values = Array.isArray(row.values) ? row.values : [];
              const value = values[idx - 1];
              obj[header] = value == null || value === '' ? 0 : value;
            }
          });
          return obj;
        })
      : [];
    const schema = normalizedHeaders.map((label, idx) => ({
      name: label,
      title: label,
      width: idx === 0 ? 240 : 120,
      align: idx === 0 ? 'left' : 'right',
      type: idx === 0 ? 'string' : 'number'
    }));

    const meta = Array.isArray(payload.rows)
      ? payload.rows.map((row) => ({
          row,
          segments: this._build_path_segments(row, payload)
        }))
      : [];

    return {
      rows,
      schema,
      meta,
      pathKey: normalizedHeaders[0] || 'Path'
    };
  },

  _build_path_segments(row, payload) {
    const rawPath = (row && (row.display_path || row.path)) ? String(row.display_path || row.path) : '';
    if (!rawPath) return null;
    const parts = rawPath.split('.');
    const allPaths = (Array.isArray(payload.color_paths) && payload.color_paths.length
      ? payload.color_paths
      : (payload.rows || []).map((r) => r.display_path || r.path || '')
    ).map((p) => String(p || ''));
    const palette = Array.isArray(payload.color_palette) && payload.color_palette.length
      ? payload.color_palette
      : (this.colors || ['#14b8a6']);
    const segments = [];
    const prefix = [];
    parts.forEach((component) => {
      const idx = this._path_color_index(component, prefix, allPaths);
      const color = this._color_from_palette(idx, palette);
      segments.push({ text: component, color });
      prefix.push(component);
    });
    return segments;
  },

  _path_color_index(component, prefixParts, allPaths) {
    const prefix = prefixParts.length ? `${prefixParts.join('.')}.` : '';
    const siblingSet = new Set();
    allPaths.forEach((path) => {
      if (!path || typeof path !== 'string') return;
      if (!prefix && path.indexOf('.') === -1 && prefixParts.length === 0) {
        siblingSet.add(path);
        return;
      }
      if (!path.startsWith(prefix)) return;
      const remainder = path.slice(prefix.length);
      if (!remainder) return;
      const next = remainder.split('.')[0];
      if (next) siblingSet.add(next);
    });
    const siblings = Array.from(siblingSet).sort();
    const idx = siblings.indexOf(component);
    return idx >= 0 ? idx : 0;
  },

  _color_from_palette(index, palette) {
    if (!Array.isArray(palette) || palette.length === 0) return '#14b8a6';
    const safeIndex = index % palette.length;
    return palette[safeIndex] || palette[0];
  },

  _strip_html(value) {
    if (!value || typeof value !== 'string') return '';
    const div = document.createElement('div');
    div.innerHTML = value;
    return div.textContent || div.innerText || '';
  },

  _ensure_unique_labels(labels) {
    const seen = {};
    return labels.map((label, idx) => {
      const base = label && label.trim() !== '' ? label : `Column ${idx + 1}`;
      const count = seen[base] || 0;
      seen[base] = count + 1;
      return count === 0 ? base : `${base} (${count + 1})`;
    });
  },

  _tableKey(id) {
    if (id === undefined || id === null) return null;
    return String(id);
  },

  _resizeAgGridTables() {
    if (!this._aggridTables) return;
    Object.values(this._aggridTables).forEach((entry) => {
      if (entry && entry.api && typeof entry.api.sizeColumnsToFit === 'function') {
        try { entry.api.sizeColumnsToFit(); } catch (_) {}
      }
    });
  },

  _apply_aggrid_theme(isDark) {
    this._aggridThemeIsDark = !!isDark;
    if (!this._aggridTables) return;
    Object.values(this._aggridTables).forEach((entry) => this._apply_aggrid_theme_to_entry(entry));
  },

  _apply_aggrid_theme_to_entry(entry) {
    if (!entry || !entry.root) return;
    const theme = this._aggridThemeIsDark ? 'dark' : 'light';
    if (entry.shell) {
      entry.shell.dataset.theme = theme;
    }
    if (entry.root.classList) {
      entry.root.classList.remove('ag-theme-alpine', 'ag-theme-alpine-dark');
      entry.root.classList.add(this._aggridThemeIsDark ? 'ag-theme-alpine-dark' : 'ag-theme-alpine');
    }
    setTimeout(() => {
      if (entry.api && typeof entry.api.redrawRows === 'function') {
        try { entry.api.redrawRows(); } catch (_) {}
      }
    }, 0);
  },

  _render_text(items) {
    if (!Array.isArray(items)) return;
    const cloned = this._deepClone(items);
    this._lastText = cloned;

    const activeIds = new Set(cloned.map((it) => String(it.id)));

    this.el.querySelectorAll('.grid-stack-item-content[data-text-widget="1"]').forEach((content) => {
      const parent = content.closest('.grid-stack-item');
      const id = parent && parent.getAttribute('gs-id');
      if (!activeIds.has(id)) {
        this._resetTextWidget(content);
      }
    });

    cloned.forEach((it) => {
      const id = String(it.id);
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${id}"]`);
      if (!item) return;

      const content = item.querySelector('.grid-stack-item-content');
      const body = item.querySelector('.grid-widget-body');
      if (!content || !body) return;

      content.dataset.textWidget = '1';
      content.dataset.widgetTitle = it.title || '';
      content.style.paddingTop = '';

      const bg = typeof it.background_color === 'string' ? it.background_color : '';
      const fg = typeof it.text_color === 'string' ? it.text_color : '';

      const colorId = (it.color_id || 'default').toLowerCase();
      const hasCustomColor = colorId !== 'default' && bg && this._isHexColor(bg);

      if (hasCustomColor) {
        content.style.backgroundColor = bg;
        content.style.color = fg || '';
        const isDark = this._isColorDark(bg);
        content.style.borderColor = isDark ? 'rgba(255,255,255,0.12)' : 'rgba(15,23,42,0.08)';
        content.dataset.customBg = '1';
      } else {
        content.style.backgroundColor = '';
        content.style.color = '';
        content.style.borderColor = '';
        delete content.dataset.customBg;
      }

      const header = content.querySelector('.grid-widget-header');
      if (header) {
        header.classList.add('text-widget-header');
        header.style.borderColor = 'transparent';
        header.style.marginBottom = '0';
        header.style.paddingBottom = '0';
        header.style.minHeight = '1.75rem';
      }

      const titleBar = content.querySelector('.grid-widget-title');
      if (titleBar) {
        const originalTitle = it.title || '';
        titleBar.dataset.originalTitle = originalTitle;
        titleBar.textContent = '\u00A0';
        titleBar.setAttribute('aria-hidden', 'true');
        titleBar.style.opacity = '0';
        titleBar.style.pointerEvents = 'none';
        titleBar.style.minHeight = '1.25rem';
        titleBar.style.display = 'block';
      }

      body.className = 'grid-widget-body flex-1 flex text-widget-body flex-col gap-2 px-4 pt-0 pb-4';
      body.dataset.textSubtype = it.subtype || 'header';
      body.style.justifyContent = 'center';
      body.style.alignItems = 'center';
      body.style.textAlign = 'center';
      body.style.overflowY = 'visible';
      body.style.paddingTop = '';
      body.style.paddingBottom = '';

      if ((it.subtype || 'header') === 'html') {
        body.style.justifyContent = 'flex-start';
        body.style.alignItems = 'stretch';
        body.style.textAlign = 'left';
        body.style.overflowY = 'auto';

        const raw = typeof it.payload === 'string' ? it.payload : '';
        const finalHtml = raw && raw.trim().length ? raw : '<div class="text-xs opacity-60 italic">No HTML content</div>';
        body.innerHTML = `<div class="text-widget-html w-full leading-relaxed">${finalHtml}</div>`;
      } else {
        const align = (it.alignment || 'center').toLowerCase();
        const alignItems = align === 'left' ? 'flex-start' : (align === 'right' ? 'flex-end' : 'center');
        const textAlign = align === 'left' ? 'left' : (align === 'right' ? 'right' : 'center');
        body.style.alignItems = alignItems;
        body.style.textAlign = textAlign;

        const sizeClass = (() => {
          switch (it.title_size) {
            case 'small': return 'text-2xl';
            case 'medium': return 'text-3xl';
            default: return 'text-4xl';
          }
        })();

        const title = this.escapeHtml(it.title || '');
        const subtitleRaw = typeof it.subtitle === 'string' ? it.subtitle.trim() : '';
        const subtitle = subtitleRaw ? `<div class="text-widget-subtitle text-base leading-relaxed opacity-80">${this.escapeHtml(subtitleRaw).replace(/\r?\n/g, '<br />')}</div>` : '';

        body.innerHTML = `<div class="text-widget-header-content w-full flex flex-col gap-2"><div class="text-widget-title font-semibold ${sizeClass} leading-tight">${title || '&nbsp;'}</div>${subtitle}</div>`;
      }
    });

    if (this._seen) this._seen.text = true;
    if (typeof this._scheduleReadyMark === 'function') this._scheduleReadyMark();
  },

  _render_list(items) {
    if (!Array.isArray(items)) return;
    const cloned = this._deepClone(items);
    this._lastList = cloned;

    const activeIds = new Set(cloned.map((it) => String(it.id)));

    this.el
      .querySelectorAll('.grid-stack-item-content[data-list-widget="1"]')
      .forEach((content) => {
        const parent = content.closest('.grid-stack-item');
        const id = parent && parent.getAttribute('gs-id');
        if (!activeIds.has(id)) {
          this._resetListWidget(content);
        }
      });

    cloned.forEach((dataset) => {
      if (!dataset) return;
      const id = String(dataset.id);
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${id}"]`);
      if (!item) return;

      const content = item.querySelector('.grid-stack-item-content');
      const body = item.querySelector('.grid-widget-body');
      if (!content || !body) return;

      content.dataset.listWidget = '1';
      this._render_list_body(body, dataset);
    });

    if (this._seen) this._seen.list = true;
    if (typeof this._scheduleReadyMark === 'function') this._scheduleReadyMark();
  },

  _resetTextWidget(content) {
    if (!content) return;
    delete content.dataset.textWidget;
    delete content.dataset.widgetTitle;
    content.style.paddingTop = '';
    content.style.backgroundColor = '';
    content.style.color = '';
    content.style.borderColor = '';
    delete content.dataset.customBg;

    const header = content.querySelector('.grid-widget-header');
    if (header) {
      header.classList.remove('text-widget-header');
      header.style.borderColor = '';
      header.style.marginBottom = '';
      header.style.paddingBottom = '';
      header.style.minHeight = '';
    }

    const titleBar = content.querySelector('.grid-widget-title');
    if (titleBar) {
      const originalTitle = titleBar.dataset.originalTitle;
      if (originalTitle !== undefined) {
        titleBar.textContent = originalTitle;
      }
      delete titleBar.dataset.originalTitle;
      titleBar.removeAttribute('aria-hidden');
      titleBar.style.opacity = '';
      titleBar.style.pointerEvents = '';
      titleBar.style.minHeight = '';
      titleBar.style.display = '';
    }

    const body = content.querySelector('.grid-widget-body');
    if (body) {
      delete body.dataset.textSubtype;
      body.className = 'grid-widget-body flex-1 flex items-center justify-center text-sm text-gray-500 dark:text-slate-400';
      body.style.textAlign = '';
      body.style.alignItems = '';
      body.style.justifyContent = '';
      body.style.overflowY = '';
      body.style.paddingTop = '';
      body.style.paddingBottom = '';
      body.innerHTML = 'Chart is coming soon';
    }
  },

  _resetListWidget(content) {
    if (!content) return;
    delete content.dataset.listWidget;
    const body = content.querySelector('.grid-widget-body');
    if (!body) return;
    body.className = 'grid-widget-body flex-1 flex flex-col min-h-0 gap-0';
    const empty = document.createElement('div');
    empty.className = 'flex-1 flex items-center justify-center text-sm text-gray-500 dark:text-slate-400 px-4 text-center';
    empty.textContent = 'No data available yet.';
    body.innerHTML = '';
    body.appendChild(empty);
  },

  _render_list_body(body, dataset) {
    if (!body) return;
    body.className = 'grid-widget-body flex-1 flex flex-col min-h-0 gap-0';
    const items = Array.isArray(dataset.items) ? dataset.items : [];
    if (!items.length) {
      const emptyMessage =
        typeof dataset.empty_message === 'string' && dataset.empty_message.trim() !== ''
          ? dataset.empty_message
          : 'No data available yet.';
      const empty = document.createElement('div');
      empty.className = 'flex-1 flex items-center justify-center text-sm text-gray-500 dark:text-slate-400 px-4 text-center';
      empty.textContent = emptyMessage;
      body.innerHTML = '';
      body.appendChild(empty);
      return;
    }

    const selectedPath = typeof dataset.selected_path === 'string' && dataset.selected_path.trim() !== '' ? dataset.selected_path.trim() : null;
    const rawSelectedKey = typeof dataset.selected_key === 'string' ? dataset.selected_key : '';
    const selectedKey = rawSelectedKey.trim() !== '' ? rawSelectedKey : null;
    const selectEvent = typeof dataset.select_event === 'string' && dataset.select_event.trim() !== '' ? dataset.select_event.trim() : null;
    const deselectEvent = typeof dataset.deselect_event === 'string' && dataset.deselect_event.trim() !== '' ? dataset.deselect_event.trim() : null;
    const interactive = Boolean(selectEvent);

    if (interactive) {
      this._currentListSelectionPath = selectedPath;
      this._currentListSelectionKey = selectedKey;
    } else {
      this._currentListSelectionPath = null;
      this._currentListSelectionKey = null;
    }

    const list = document.createElement('ul');
    list.className = 'flex-1 divide-y divide-gray-100/80 dark:divide-slate-500/60 overflow-auto list-none m-0 p-0';

    items.forEach((entry, index) => {
      if (!entry) return;
      const li = document.createElement('li');
      li.className = 'first:pt-0 last:pb-0';

      const wrapperTag = interactive ? 'button' : 'div';
      const wrapper = document.createElement(wrapperTag);
      if (interactive) {
        wrapper.type = 'button';
        wrapper.setAttribute('data-role', 'list-selectable');
      }

      const entryPath = typeof entry.path === 'string' ? entry.path : '';
      const rawLabel = typeof entry.label === 'string' ? entry.label : '';
      const trimmedLabel = rawLabel.trim();
      const labelText = trimmedLabel !== '' ? rawLabel : (entryPath || `Item ${index + 1}`);
      const payloadKey = trimmedLabel !== '' ? rawLabel : entryPath || labelText;
      const isSelected =
        (selectedPath && entryPath === selectedPath) ||
        (selectedKey && rawLabel === selectedKey);

      const baseClasses = [
        'flex',
        'items-center',
        'justify-between',
        'gap-2.5',
        'border',
        'border-transparent',
        'px-2.5',
        'py-1.5',
        'transition-colors',
        'w-full',
        'list-widget-row'
      ];

      if (isSelected && interactive) {
        baseClasses.push('bg-teal-50', 'dark:bg-teal-900/30', 'border-teal-100', 'dark:border-teal-800');
      }

      if (interactive) {
        baseClasses.push('cursor-pointer', 'focus-visible:outline-none', 'focus-visible:ring-2', 'focus-visible:ring-teal-500/60');
      }

      wrapper.className = baseClasses.join(' ');
      if (interactive) {
        wrapper.setAttribute('aria-pressed', isSelected ? 'true' : 'false');
      }

      const row = document.createElement('div');
      row.className = 'w-full flex items-center justify-between gap-2.5';

      const left = document.createElement('div');
      left.className = `flex items-center ${interactive ? 'gap-2.5' : 'gap-2'} min-w-0`;

      const color =
        typeof entry.color === 'string' && entry.color.trim() !== '' ? entry.color : '#14b8a6';

      if (interactive) {
        const indicator = this._buildListSelectionIcon(isSelected);
        left.appendChild(indicator);
      } else {
        left.appendChild(this._buildListColorChip(color));
      }

      const label = document.createElement('span');
      label.className = 'text-sm font-mono truncate';
      label.style.color = color;
      label.textContent = labelText;
      label.title = labelText;

      left.appendChild(label);

      const badge = document.createElement('span');
      badge.className = 'inline-flex items-center rounded-md border px-2 py-0.5 text-xs font-semibold';
      badge.style.color = color;
      const bgColor = this._colorWithAlpha(color, '15');
      const borderColor = this._colorWithAlpha(color, '40');
      if (bgColor) badge.style.backgroundColor = bgColor;
      if (borderColor) badge.style.borderColor = borderColor;
      const valueText =
        entry.formatted_value ||
        (typeof entry.value === 'number' ? String(entry.value) : '0');
      badge.textContent = valueText;

      row.appendChild(left);
      row.appendChild(badge);
      wrapper.appendChild(row);
      li.appendChild(wrapper);
      list.appendChild(li);

      if (interactive) {
        wrapper.addEventListener('click', (event) => {
          event.preventDefault();
          event.stopPropagation();
          const keyToSend = payloadKey;
          if (!keyToSend || !selectEvent) return;
          const currentlySelected =
            (this._currentListSelectionPath && entryPath === this._currentListSelectionPath) ||
            (this._currentListSelectionKey && keyToSend === this._currentListSelectionKey) ||
            isSelected;

          if (currentlySelected && deselectEvent) {
            this.pushEvent(deselectEvent, {});
            this._currentListSelectionKey = null;
            this._currentListSelectionPath = null;
          } else {
            this.pushEvent(selectEvent, { key: keyToSend });
            this._currentListSelectionKey = keyToSend;
            this._currentListSelectionPath = entryPath || null;
          }
        });
      }
    });

    body.innerHTML = '';
    body.appendChild(list);
  },

  _isColorDark(color) {
    if (!color || typeof color !== 'string') return false;
    const hexMatch = color.trim().match(/^#?([0-9a-f]{6})$/i);
    if (!hexMatch) return false;
    const hex = hexMatch[1];
    const r = parseInt(hex.slice(0, 2), 16);
    const g = parseInt(hex.slice(2, 4), 16);
    const b = parseInt(hex.slice(4, 6), 16);
    const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return Number.isFinite(luminance) ? luminance < 0.5 : false;
  },

  _isHexColor(color) {
    if (!color || typeof color !== 'string') return false;
    return /^#?[0-9a-f]{3}([0-9a-f]{3})?$/i.test(color.trim());
  },

  _colorWithAlpha(color, alphaHex) {
    if (!color || typeof color !== 'string') return '';
    const trimmed = color.trim();
    const match = trimmed.match(/^#([0-9a-f]{6})$/i);
    if (match) {
      return `${trimmed}${alphaHex}`;
    }
    return trimmed;
  },

  _buildListColorChip(color) {
    const span = document.createElement('span');
    span.className = 'inline-flex h-2.5 w-2.5 rounded-full flex-shrink-0';
    if (color && typeof color === 'string') {
      span.style.backgroundColor = color;
    }
    span.setAttribute('aria-hidden', 'true');
    return span;
  },

  _buildListSelectionIcon(selected) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke-width', '1.5');
    svg.setAttribute('stroke', 'currentColor');
    svg.classList.add('h-5', 'w-5', 'flex-shrink-0');
    svg.setAttribute('aria-hidden', 'true');

    if (selected) {
      svg.classList.add('text-teal-600');
    } else {
      svg.classList.add('text-gray-400', 'dark:text-slate-400');
    }

    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute('stroke-linecap', 'round');
    path.setAttribute('stroke-linejoin', 'round');
    path.setAttribute('d', 'M21 12a9 9 0 11-18 0 9 9 0 0118 0z');
    svg.appendChild(path);

    if (selected) {
      const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
      circle.setAttribute('cx', '12');
      circle.setAttribute('cy', '12');
      circle.setAttribute('r', '4');
      circle.setAttribute('fill', 'currentColor');
      svg.appendChild(circle);
    }

    return svg;
  },

  addGridItemEl(item) {
    const el = document.createElement('div');
    el.className = 'grid-stack-item';
    el.setAttribute('gs-w', item.w || 3);
    el.setAttribute('gs-h', item.h || 2);
    el.setAttribute('gs-x', item.x || 0);
    el.setAttribute('gs-y', item.y || 0);
    el.setAttribute('gs-id', item.id || (item.id = this.genId()));
    const content = document.createElement('div');
    const titleText = item.title || `Widget ${String(item.id || '').slice(0,6)}`;
    const widgetId = el.getAttribute('gs-id');
    const expandBtn = `
      <button type=\"button\" class=\"grid-widget-expand inline-flex items-center p-1 rounded group\" data-widget-id=\"${widgetId}\" title=\"Expand widget\">
        <svg xmlns=\"http://www.w3.org/2000/svg\" fill=\"none\" viewBox=\"0 0 24 24\" stroke-width=\"1.5\" stroke=\"currentColor\" class=\"h-4 w-4 text-gray-600 dark:text-slate-300 transition-colors group-hover:text-gray-800 dark:group-hover:text-slate-100\">
          <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15\" />
        </svg>
      </button>`;
    const editBtn = this.editable ? `
      <button type=\"button\" class=\"grid-widget-edit inline-flex items-center p-1 rounded group\" data-widget-id=\"${widgetId}\" title=\"Edit widget\"> 
        <svg xmlns=\"http://www.w3.org/2000/svg\" fill=\"none\" viewBox=\"0 0 24 24\" stroke-width=\"1.5\" stroke=\"currentColor\" class=\"h-4 w-4 text-gray-600 dark:text-slate-300 transition-colors group-hover:text-gray-800 dark:group-hover:text-slate-100\"> 
          <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z\" />
          <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M15 12a3 3 0 11-6 0 3 3 0 016 0z\" />
        </svg>
      </button>` : '';
    const actionButtons = `
      <div class=\"grid-widget-actions flex items-center gap-1 opacity-0 transition-opacity duration-150 group-hover:opacity-100 group-focus-within:opacity-100\">
        ${expandBtn}
        ${editBtn}
      </div>`;
    content.innerHTML = `
      <div class=\"grid-widget-header flex items-center justify-between pt-2 px-3 mb-2 pb-1 border-b border-gray-100 dark:border-slate-700/60\">\n        <div class=\"grid-widget-handle cursor-move flex-1 flex items-center gap-2 py-1 min-w-0\"><div class=\"grid-widget-title font-semibold truncate text-gray-900 dark:text-white\">${this.escapeHtml(titleText)}</div></div>\n        ${actionButtons}\n      </div>\n      <div class=\"grid-widget-body flex-1 flex items-center justify-center text-sm text-gray-500 dark:text-slate-400\">\n        Chart is coming soon\n      </div>`;
    el.appendChild(content);
    this.el.appendChild(el);
  },

  genId() { return Math.random().toString(36).slice(2); },

  addNewWidget() {
    // compute bottom-most occupied row so we don't reflow existing items
    let bottom = 0;
    this.el.querySelectorAll('.grid-stack-item').forEach((it) => {
      const y = parseInt(it.getAttribute('gs-y') || '0', 10);
      const h = parseInt(it.getAttribute('gs-h') || '1', 10);
      bottom = Math.max(bottom, y + h);
    });

    const id = this.genId();
    const w = 3, h = 2, x = 0, y = bottom;

    const el = this.grid.addWidget({ x, y, w, h, id, content: '' });
    const contentEl = el && el.querySelector('.grid-stack-item-content');
    if (contentEl) {
      contentEl.className = 'grid-stack-item-content bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-md shadow text-gray-700 dark:text-slate-300 flex flex-col group';
      contentEl.innerHTML = `
        <div class=\"grid-widget-header flex items-center justify-between pt-2 px-3 mb-2 pb-1 border-b border-gray-100 dark:border-slate-700/60\"> 
          <div class=\"grid-widget-handle cursor-move flex-1 flex items-center gap-2 py-1 min-w-0\"><div class=\"grid-widget-title font-semibold truncate text-gray-900 dark:text-white\">New Widget</div></div> 
          <div class=\"grid-widget-actions flex items-center gap-1 opacity-0 transition-opacity duration-150 group-hover:opacity-100 group-focus-within:opacity-100\">
            <button type=\"button\" class=\"grid-widget-expand inline-flex items-center p-1 rounded group\" data-widget-id=\"${id}\" title=\"Expand widget\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" fill=\"none\" viewBox=\"0 0 24 24\" stroke-width=\"1.5\" stroke=\"currentColor\" class=\"h-4 w-4 text-gray-600 dark:text-slate-300 transition-colors group-hover:text-gray-800 dark:group-hover:text-slate-100\">
                <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15\" />
              </svg>
            </button>
            <button type=\"button\" class=\"grid-widget-edit inline-flex items-center p-1 rounded group\" data-widget-id=\"${id}\" title=\"Edit widget\"> 
              <svg xmlns=\"http://www.w3.org/2000/svg\" fill=\"none\" viewBox=\"0 0 24 24\" stroke-width=\"1.5\" stroke=\"currentColor\" class=\"h-4 w-4 text-gray-600 dark:text-slate-300 transition-colors group-hover:text-gray-800 dark:group-hover:text-slate-100\"> 
                <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z\" /> 
                <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M15 12a3 3 0 11-6 0 3 3 0 016 0z\" /> 
              </svg> 
            </button> 
          </div>
        </div>
        <div class=\"grid-widget-body flex-1 flex items-center justify-center text-sm text-gray-500 dark:text-slate-400\"> 
          Chart is coming soon 
        </div>`;
    }
    this.saveLayout();
  },

  saveLayout() {
    if (!this.editable) return;
    const items = Array.from(this.el.querySelectorAll('.grid-stack-item')).map((el) => {
      const content = el.querySelector('.grid-stack-item-content');
      const titleEl = el.querySelector('.grid-widget-title');
      const storedTitle = (content && content.dataset.widgetTitle) || (titleEl && titleEl.dataset.originalTitle);
      const textTitle = (titleEl && titleEl.textContent ? titleEl.textContent.trim() : '') || '';
      const title = (storedTitle !== undefined && storedTitle !== null ? storedTitle : textTitle).trim();

      return {
        x: parseInt(el.getAttribute('gs-x') || '0', 10),
        y: parseInt(el.getAttribute('gs-y') || '0', 10),
        w: parseInt(el.getAttribute('gs-w') || '1', 10),
        h: parseInt(el.getAttribute('gs-h') || '1', 10),
        id: el.getAttribute('gs-id') || this.genId(),
        title,
      };
    });
    this.pushEvent('dashboard_grid_changed', { items });
  },

  syncServerRenderedItems() {
    if (!this.grid) return;
    const nodes = Array.from(this.el.querySelectorAll('.grid-stack-item'));
    nodes.forEach((node) => {
      if (!node.gridstackNode) {
        try { this.grid.makeWidget(node); } catch (_) {}
      }
    });
    if (typeof this.grid.batchUpdate === 'function') {
      this.grid.batchUpdate();
    }
    nodes.forEach((node) => {
      if (!node.gridstackNode) {
        try { this.grid.makeWidget(node); } catch (_) {}
      }
      const gsNode = node.gridstackNode;
      if (!gsNode) return;
      const target = {
        x: parseInt(node.getAttribute('gs-x') || gsNode.x || 0, 10),
        y: parseInt(node.getAttribute('gs-y') || gsNode.y || 0, 10),
        w: parseInt(node.getAttribute('gs-w') || gsNode.w || 1, 10),
        h: parseInt(node.getAttribute('gs-h') || gsNode.h || 1, 10)
      };
      try {
        this.grid.update(gsNode, target);
      } catch (_) {}
    });
    if (typeof this.grid.commit === 'function') {
      try { this.grid.commit(); } catch (_) {}
    }
  },

  registerWidget(type, id, payload = null) {
    if (!id) return;
    const normalizedId = String(id);
    const registry = this._widgetRegistry || (this._widgetRegistry = {
      kpiValues: {},
      kpiVisuals: {},
      timeseries: {},
      category: {},
      table: {},
      text: {},
      list: {},
      distribution: {}
    });
    if (!registry.distribution) registry.distribution = {};

    if (type === 'kpi') {
      const value = payload && payload.value ? Object.assign({}, payload.value, { id: payload.value.id || normalizedId }) : null;
      const visual = payload && payload.visual ? Object.assign({}, payload.visual, { id: payload.visual.id || normalizedId }) : null;
      if (value) {
        registry.kpiValues[normalizedId] = value;
      } else {
        delete registry.kpiValues[normalizedId];
      }
      if (visual) {
        registry.kpiVisuals[normalizedId] = visual;
      } else {
        delete registry.kpiVisuals[normalizedId];
      }
      this._render_kpi_values(this._sortedWidgetValues(registry.kpiValues));
      this._seen.kpi_values = true;
      this._scheduleReadyMark();
      this._render_kpi_visuals(this._sortedWidgetValues(registry.kpiVisuals));
      return;
    }

    if (type === 'timeseries') {
      if (payload) {
        registry.timeseries[normalizedId] = Object.assign({}, payload, { id: payload.id || normalizedId });
      } else {
        delete registry.timeseries[normalizedId];
      }
      this._render_timeseries(this._sortedWidgetValues(registry.timeseries));
      return;
    }

    if (type === 'category') {
      if (payload) {
        registry.category[normalizedId] = Object.assign({}, payload, { id: payload.id || normalizedId });
      } else {
        delete registry.category[normalizedId];
      }
      this._render_category(this._sortedWidgetValues(registry.category));
      return;
    }

    if (type === 'table') {
      if (payload) {
        registry.table[normalizedId] = Object.assign({}, payload, { id: payload.id || normalizedId });
      } else {
        delete registry.table[normalizedId];
      }
      this._render_table(this._sortedWidgetValues(registry.table));
      this._seen.table = true;
      this._scheduleReadyMark();
      return;
    }

    if (type === 'text') {
      if (payload) {
        registry.text[normalizedId] = Object.assign({}, payload, { id: payload.id || normalizedId });
      } else {
        delete registry.text[normalizedId];
      }
      this._render_text(this._sortedWidgetValues(registry.text));
      this._seen.text = true;
      this._scheduleReadyMark();
      return;
    }

    if (type === 'list') {
      if (payload) {
        registry.list[normalizedId] = Object.assign({}, payload, { id: payload.id || normalizedId });
      } else {
        delete registry.list[normalizedId];
      }
      this._render_list(this._sortedWidgetValues(registry.list));
      return;
    }

    if (type === 'distribution') {
      if (payload) {
        registry.distribution[normalizedId] = Object.assign({}, payload, { id: payload.id || normalizedId });
      } else {
        delete registry.distribution[normalizedId];
      }
      this._render_distribution(this._sortedWidgetValues(registry.distribution));
      return;
    }

    // Unknown type: ensure removal from all registries
    delete registry.kpiValues[normalizedId];
    delete registry.kpiVisuals[normalizedId];
    delete registry.timeseries[normalizedId];
    delete registry.category[normalizedId];
    delete registry.table[normalizedId];
    delete registry.text[normalizedId];
    delete registry.list[normalizedId];
    delete registry.distribution[normalizedId];
  },

  unregisterWidget(type, id) {
    if (!id) return;
    if (!type) {
      this.registerWidget('kpi', id, null);
      this.registerWidget('timeseries', id, null);
      this.registerWidget('category', id, null);
      this.registerWidget('table', id, null);
      this.registerWidget('text', id, null);
      this.registerWidget('list', id, null);
      this.registerWidget('distribution', id, null);
      return;
    }
    this.registerWidget(type, id, null);
  },

  _sortedWidgetValues(map) {
    return Object.values(map || {})
      .filter((item) => item && item.id !== undefined && item.id !== null)
      .sort((a, b) => {
        const idA = String(a.id);
        const idB = String(b.id);
        if (idA < idB) return -1;
        if (idA > idB) return 1;
        return 0;
      });
  },

  _applyThemeToCharts(isDarkMode) {
    const themeIsDark = typeof isDarkMode === 'boolean' ? isDarkMode : document.documentElement.classList.contains('dark');
    this._currentThemeIsDark = themeIsDark;
    const themeName = themeIsDark ? 'dark' : 'default';

    const kpiVisuals = Array.isArray(this._lastKpiVisuals) ? this._deepClone(this._lastKpiVisuals) : null;
    const timeseries = Array.isArray(this._lastTimeseries) ? this._deepClone(this._lastTimeseries) : null;
    const categories = Array.isArray(this._lastCategory) ? this._deepClone(this._lastCategory) : null;
    const distributions = Array.isArray(this._lastDistribution) ? this._deepClone(this._lastDistribution) : null;
    const tables = Array.isArray(this._lastTable) ? this._deepClone(this._lastTable) : null;
    const textWidgets = Array.isArray(this._lastText) ? this._deepClone(this._lastText) : null;
    const lists = Array.isArray(this._lastList) ? this._deepClone(this._lastList) : null;

    const updateTheme = (map) => {
      if (!map) return;
      Object.values(map).forEach((chart) => {
        try {
          if (chart && typeof chart.setTheme === 'function' && !chart.isDisposed()) {
            chart.setTheme(themeName);
          }
        } catch (_) {}
      });
    };

    updateTheme(this._sparklines);
    updateTheme(this._tsCharts);
    updateTheme(this._catCharts);
    updateTheme(this._distCharts);
    updateTheme(this._tableCache);
    this._apply_aggrid_theme(themeIsDark);

    if (this._sparkTimers) {
      Object.keys(this._sparkTimers).forEach((key) => {
        try { clearTimeout(this._sparkTimers[key]); } catch (_) {}
        delete this._sparkTimers[key];
      });
    }
    this._sparkTimers = {};

    if (this._seen) {
      this._seen.kpi_visual = false;
      this._seen.timeseries = false;
      this._seen.category = false;
      this._seen.table = false;
      this._seen.text = false;
      this._seen.list = false;
      this._seen.distribution = false;
    }

    const markPending = (selector) => {
      try {
        this.el.querySelectorAll(selector).forEach((node) => {
          if (node && node.dataset) node.dataset.echartsReady = '0';
        });
      } catch (_) {}
    };
    markPending('.kpi-visual');
    markPending('.ts-chart');
    markPending('.cat-chart');
    markPending('.distribution-chart');

    const rerender = () => {
      if (kpiVisuals && kpiVisuals.length) this._render_kpi_visuals(kpiVisuals);
      if (timeseries && timeseries.length) this._render_timeseries(timeseries);
      if (categories && categories.length) this._render_category(categories);
      if (distributions && distributions.length) this._render_distribution(distributions);
      if (Array.isArray(textWidgets)) this._render_text(textWidgets);
      if (Array.isArray(lists)) this._render_list(lists);
    };

    // Ensure DOM settles before re-rendering charts to avoid zero-size init
    requestAnimationFrame(() => setTimeout(rerender, 0));
  },

  _deepClone(value) {
    if (value == null) return value;
    if (typeof structuredClone === 'function') {
      try { return structuredClone(value); } catch (_) {}
    }
    try {
      return JSON.parse(JSON.stringify(value));
    } catch (_) {
      if (Array.isArray(value)) return value.slice();
      if (typeof value === 'object') return Object.assign({}, value);
      return value;
    }
  },

  escapeHtml(str) {
    return String(str || '').replace(/[&<>"']/g, (s) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[s]));
  },
}

Hooks.DashboardWidgetData = {
  mounted() {
    this.widgetId = this.el.dataset.widgetId || '';
    this.widgetType = (this.el.dataset.widgetType || '').toLowerCase() || 'kpi';
    this._retryTimer = null;
    this._lastKey = null;
    this._registeredType = null;
    this.register();
  },

  updated() {
    this.register();
  },

  reconnected() {
    // Force re-register so widgets with unchanged payloads (text/list) render after reconnects
    this._lastKey = null;
    this.register();
  },

  destroyed() {
    if (this._retryTimer) {
      clearTimeout(this._retryTimer);
      this._retryTimer = null;
    }
    const gridHook = findDashboardGridHook(this.el);
    if (gridHook && this.widgetId) {
      const cleanupType = this._registeredType || this.widgetType || null;
      gridHook.unregisterWidget(cleanupType, this.widgetId);
    }
  },

  register() {
    const rawType = (this.el.dataset.widgetType || '').toLowerCase();
    const nextType = rawType || this.widgetType || 'kpi';
    if (nextType !== this.widgetType) {
      this.widgetType = nextType;
    }

    const titleData = this.el.dataset.title || '';
    const dataStrings = [
      this.el.dataset.kpiValues || '',
      this.el.dataset.kpiVisual || '',
      this.el.dataset.timeseries || '',
      this.el.dataset.category || '',
      this.el.dataset.table || '',
      this.el.dataset.text || '',
      this.el.dataset.list || '',
      this.el.dataset.distribution || ''
    ];
    const key = [this.widgetType, this.widgetId, titleData].concat(dataStrings).join('||');
    if (key === this._lastKey) return;
    this._lastKey = key;

    if (this._retryTimer) {
      clearTimeout(this._retryTimer);
      this._retryTimer = null;
    }

    const attempt = () => {
      const gridHook = findDashboardGridHook(this.el);
      if (!gridHook) {
        this._retryTimer = setTimeout(attempt, 20);
        return;
      }

      const type = this.widgetType;
      const id = this.widgetId;
      let payload = null;

      if (this._registeredType && this._registeredType !== type && id) {
        gridHook.unregisterWidget(this._registeredType, id);
        this._registeredType = null;
      }

      if (type === 'kpi') {
        const value = parseJsonSafe(this.el.dataset.kpiValues || '');
        if (value && value.id == null) value.id = id;
        const visual = parseJsonSafe(this.el.dataset.kpiVisual || '');
        if (visual && visual.id == null) visual.id = id;
        payload = { value, visual };
      } else if (type === 'timeseries') {
        const data = parseJsonSafe(this.el.dataset.timeseries || '');
        if (data && data.id == null) data.id = id;
        payload = data;
      } else if (type === 'category') {
        const data = parseJsonSafe(this.el.dataset.category || '');
        if (data && data.id == null) data.id = id;
        payload = data;
      } else if (type === 'table') {
        const data = parseJsonSafe(this.el.dataset.table || '');
        if (data && data.id == null) data.id = id;
        payload = data;
      } else if (type === 'text') {
        const data = parseJsonSafe(this.el.dataset.text || '');
        if (data && data.id == null) data.id = id;
        payload = data;
      } else if (type === 'list') {
        const data = parseJsonSafe(this.el.dataset.list || '');
        if (data && data.id == null) data.id = id;
        payload = data;
      } else if (type === 'distribution') {
        const data = parseJsonSafe(this.el.dataset.distribution || '');
        if (data && data.id == null) data.id = id;
        payload = data;
      }

      gridHook.registerWidget(type || null, id, payload);
      this._registeredType = type || null;
      this.updateWidgetTitle(titleData, type);
    };

    attempt();
  },

  updateWidgetTitle(title, type) {
    if (!this.widgetId) return;
    if (!title || type === 'text') return;
    const trimmed = title.trim();
    if (trimmed === '') return;
    const gridHook = findDashboardGridHook(this.el);
    const root = gridHook && gridHook.el ? gridHook.el : document;
    const item =
      root && root.querySelector
        ? root.querySelector(`.grid-stack-item[gs-id="${this.widgetId}"]`)
        : null;
    if (!item) return;
    const titleEl = item.querySelector('.grid-widget-title');
    if (!titleEl) return;
    titleEl.textContent = trimmed;
    titleEl.dataset.originalTitle = trimmed;
    const content = item.querySelector('.grid-stack-item-content');
    if (content) {
      content.dataset.widgetTitle = trimmed;
    }
  }
};

Hooks.ExpandedWidgetView = {
  mounted() {
    this.chartTarget = this.el.querySelector('[data-role="chart"]');
    this.tableRoot = this.el.querySelector('[data-role="table-root"]');
    this.chart = null;
    this.chartElement = null;
    this.chartTheme = null;
    this.lastPayloadKey = null;
    this.retryTimer = null;
    this._sparklineTimer = null;
    this.colors = [];
    this.handleResize = () => {
      if (this.chart && typeof this.chart.resize === 'function') {
        try { this.chart.resize(); } catch (_) {}
      }
    };
    this.handleThemeChange = () => this.render(true);
    window.addEventListener('resize', this.handleResize);
    window.addEventListener('trifle:theme-changed', this.handleThemeChange);
    this.render();
  },

  updated() {
    this.render();
  },

  destroyed() {
    this.disposeChart();
    if (this.retryTimer) {
      clearTimeout(this.retryTimer);
      this.retryTimer = null;
    }
    window.removeEventListener('resize', this.handleResize);
    window.removeEventListener('trifle:theme-changed', this.handleThemeChange);
  },

  parseJsonString(str) {
    if (!str) return null;
    try { return JSON.parse(str); } catch (_) { return null; }
  },

  getTheme() {
    return document.documentElement.classList.contains('dark') ? 'dark' : 'light';
  },

  disposeChart() {
    if (this.chart && typeof this.chart.dispose === 'function') {
      try { this.chart.dispose(); } catch (_) {}
    }
    this.chart = null;
    this.chartElement = null;
    this.chartTheme = null;
    if (this.retryTimer) {
      clearTimeout(this.retryTimer);
      this.retryTimer = null;
    }
    if (this._sparklineTimer) {
      clearTimeout(this._sparklineTimer);
      this._sparklineTimer = null;
    }
  },

  ensureChart(opts = {}) {
    const container = this.chartTarget;
    if (!container) return null;
    if (container.clientWidth === 0 || container.clientHeight === 0) {
      if (this.retryTimer) clearTimeout(this.retryTimer);
      this.retryTimer = setTimeout(() => this.render(true), 140);
      return null;
    }
    const theme = this.getTheme();
    if (this.chart && (this.chartElement !== container || this.chartTheme !== theme)) {
      this.disposeChart();
    }
    if (!this.chart) {
      container.innerHTML = '';
      this.chart = echarts.init(container, theme === 'dark' ? 'dark' : undefined, withChartOpts(opts));
      this.chartTheme = theme;
      this.chartElement = container;
    }
    return this.chart;
  },

  render(force = false) {
    const type = (this.el.dataset.type || '').toLowerCase();
    const chartRaw = this.el.dataset.chart || '';
    const paletteRaw = this.el.dataset.colors || '';
    const visualRaw = this.el.dataset.visual || '';
    const textRaw = this.el.dataset.text || '';
    const key = [type, chartRaw, paletteRaw, visualRaw, textRaw].join('||');
    if (!force && key === this.lastPayloadKey) {
      if (this.chart && typeof this.chart.resize === 'function') {
        try { this.chart.resize(); } catch (_) {}
      }
      return;
    }
    this.lastPayloadKey = key;
    this.disposeChart();
    this.colors = this.parseJsonString(paletteRaw) || [];
    const chartData = this.parseJsonString(chartRaw);
    const visualData = this.parseJsonString(visualRaw);
    const textData = this.parseJsonString(textRaw);

    if (type === 'timeseries') {
      this.renderTimeseries(chartData);
      return;
    }

    if (type === 'category') {
      this.renderCategory(chartData);
      return;
    }

    if (type === 'distribution') {
      this.renderDistribution(chartData);
      return;
    }

    if (type === 'kpi') {
      this.renderKpi(chartData, visualData);
      return;
    }

    if (type === 'text') {
      this.renderText(textData);
      this.showTablePlaceholder('Series summary is not available for text widgets.');
      return;
    }

    this.showChartPlaceholder('Expanded view is currently available for chart widgets.');
    this.showTablePlaceholder('No additional data available.');
  },

  seriesColor(index) {
    if (Array.isArray(this.colors) && this.colors.length) {
      return this.colors[index % this.colors.length];
    }
    const fallback = ['#14b8a6', '#6366f1', '#f59e0b', '#ec4899', '#3b82f6', '#10b981', '#f97316', '#8b5cf6'];
    return fallback[index % fallback.length];
  },

  renderTimeseries(data) {
    if (!data || !Array.isArray(data.series) || data.series.length === 0) {
      this.showChartPlaceholder('No chart data available yet.');
      this.showTablePlaceholder('No series data available yet.');
      return;
    }

    const chart = this.ensureChart();
    if (!chart) return;

    const theme = this.getTheme();
    const isDarkMode = theme === 'dark';
    const chartType = String(data.chart_type || 'line').toLowerCase();
    const stacked = !!data.stacked;
    const normalized = !!data.normalized;
    const showLegend = !!data.legend;
    const bottomPadding = showLegend ? 56 : 28;
    const palette = Array.isArray(this.colors) ? this.colors : [];
    const chartFontFamily =
      'Inter var, Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
    const overlayLabelBackground = isDarkMode ? 'rgba(15, 23, 42, 0.85)' : 'rgba(255, 255, 255, 0.92)';
    const overlayLabelText = isDarkMode ? '#F8FAFC' : '#0F172A';

    const series = (data.series || []).map((s, idx) => {
      const base = {
        name: s.name || `Series ${idx + 1}`,
        type: chartType === 'area' ? 'line' : chartType,
        data: Array.isArray(s.data) ? s.data : [],
        showSymbol: false
      };
      if (stacked) base.stack = 'total';
      if (chartType === 'area') base.areaStyle = { opacity: 0.1 };
      if (palette.length) {
        const color = palette[idx % palette.length];
        base.itemStyle = { color };
      }
      return base;
    });

    const overlay = data.alert_overlay || null;
    const alertStrategy = String(data.alert_strategy || '').toLowerCase();
    const shouldApplyAlertAxis = !!overlay && (alertStrategy === 'threshold' || alertStrategy === 'range');
    if (overlay && series.length) {
      const primarySeries = series[0];
      const markAreas = [];
      const defaultSegmentColor = 'rgba(248,113,113,0.22)';
      const defaultBandColor = 'rgba(16,185,129,0.08)';
      const defaultLineColor = '#f87171';
      const defaultPointColor = '#f97316';
      const isoValue = (iso, ts) => {
        if (iso) return iso;
        if (typeof ts === 'number') {
          const dt = new Date(ts);
          if (!Number.isNaN(dt.getTime())) return dt.toISOString();
        }
        return null;
      };

      if (Array.isArray(overlay.segments)) {
        overlay.segments.forEach((segment, index) => {
          const startIso = isoValue(segment.from_iso, segment.from_ts);
          let endIso = isoValue(segment.to_iso, segment.to_ts);
          if (startIso && endIso && startIso === endIso) {
            const adjusted = new Date(startIso);
            if (!Number.isNaN(adjusted.getTime())) {
              adjusted.setMinutes(adjusted.getMinutes() + 1);
              endIso = adjusted.toISOString();
            }
          }
          if (startIso && endIso) {
            const itemStyle = segment.color ? { color: segment.color } : { color: defaultSegmentColor };
            const label = segment.label || `Alert window #${index + 1}`;
            markAreas.push([
              {
                name: label,
                xAxis: startIso,
                itemStyle,
                label: {
                  color: overlayLabelText,
                  fontFamily: chartFontFamily,
                  position: 'insideTop',
                  distance: 6,
                  overflow: 'break',
                  align: 'left',
                  backgroundColor: overlayLabelBackground,
                  padding: [2, 6],
                  borderRadius: 4
                },
                emphasis: { disabled: true }
              },
              { xAxis: endIso }
            ]);
          }
        });
      }

      if (Array.isArray(overlay.bands)) {
        overlay.bands.forEach((band) => {
          if (typeof band.min === 'number' && typeof band.max === 'number') {
            const itemStyle = band.color ? { color: band.color } : { color: defaultBandColor };
            const label = band.label || 'Target band';
            markAreas.push([
              {
                name: label,
                yAxis: band.min,
                xAxis: 'min',
                itemStyle,
                label: {
                  color: overlayLabelText,
                  fontFamily: chartFontFamily,
                  position: 'insideTop',
                  distance: 6,
                  overflow: 'break',
                  align: 'left',
                  backgroundColor: overlayLabelBackground,
                  padding: [2, 6],
                  borderRadius: 4
                },
                emphasis: { disabled: true }
              },
              { yAxis: band.max, xAxis: 'max' }
            ]);
          }
        });
      }

      if (markAreas.length) {
        primarySeries.markArea = { data: markAreas, silent: true, emphasis: { disabled: true } };
      }

      if (Array.isArray(overlay.reference_lines) && overlay.reference_lines.length) {
        primarySeries.markLine = {
          symbol: 'none',
          silent: true,
          animation: false,
          emphasis: { disabled: true },
          data: overlay.reference_lines
            .filter((line) => typeof line.value === 'number')
            .map((line) => ({
              yAxis: line.value,
              name: line.label || formatCompactNumber(line.value),
              lineStyle: {
                color: line.color || defaultLineColor,
                type: 'dashed',
                width: 1.2
              },
              label: {
                formatter: line.label || formatCompactNumber(line.value),
                color: overlayLabelText,
                fontFamily: chartFontFamily,
                position: 'insideEndTop',
                distance: 8,
                overflow: 'break',
                backgroundColor: overlayLabelBackground,
                padding: [2, 6],
                borderRadius: 4
              },
              emphasis: { disabled: true }
            }))
        };
      }

      if (Array.isArray(overlay.points)) {
        const markPoints = overlay.points
          .filter((point) => typeof point.value === 'number')
          .map((point, idx) => {
            const coordX = isoValue(point.at_iso, point.ts);
            if (!coordX) return null;
            const color = point.color || defaultPointColor;
            return {
              coord: [coordX, point.value],
              value: point.value,
              name: point.label || `Alert point #${idx + 1}`,
              itemStyle: { color },
              label: {
                color: overlayLabelText,
                formatter: point.label || formatCompactNumber(point.value),
                fontFamily: chartFontFamily,
                position: 'top',
                distance: 10,
                backgroundColor: overlayLabelBackground,
                padding: [2, 6],
                borderRadius: 4,
                overflow: 'truncate'
              }
            };
          })
          .filter(Boolean);

        if (markPoints.length) {
          primarySeries.markPoint = {
            symbol: 'circle',
            symbolSize: 16,
            animation: false,
            silent: true,
            emphasis: { disabled: true },
            data: markPoints
          };
        }
      }
      const baselineSeries = []
        .concat(Array.isArray(data.alert_baseline_series) ? data.alert_baseline_series : [])
        .concat(overlay && Array.isArray(overlay.baseline_series) ? overlay.baseline_series : []);
      const seenBaselineKeys = new Set();
      baselineSeries
        .filter((baseline) => {
          if (!baseline || !Array.isArray(baseline.data) || baseline.data.length === 0) return false;
          const key = baseline.name || `${baseline.color || 'baseline'}-${baseline.line_type || 'line'}`;
          if (seenBaselineKeys.has(key)) return false;
          seenBaselineKeys.add(key);
          return true;
        })
        .forEach((baseline) => {
          const baselineData = Array.isArray(baseline.data) ? baseline.data : [];
          if (!baselineData.length) return;
          const baselineColor = baseline.color || overlayLabelText;
        const lineType = baseline.line_type || 'dashed';
        const lineWidth = typeof baseline.width === 'number' ? baseline.width : 1.3;
        const lineOpacity = typeof baseline.opacity === 'number' ? baseline.opacity : 0.85;
        series.push({
          name: baseline.name || 'Detection baseline',
          type: 'line',
          data: baselineData,
          showSymbol: false,
          smooth: false,
          connectNulls: true,
          animation: false,
          lineStyle: {
            width: lineWidth,
            type: lineType,
            color: baselineColor,
            opacity: lineOpacity
          },
          itemStyle: { color: baselineColor, opacity: lineOpacity },
          emphasis: { focus: 'series' },
          tooltip: {
            valueFormatter: (v) => (v == null ? '-' : formatCompactNumber(v))
          },
          zlevel: 1,
          z: 25
        });
      });
    }

    const textColor = isDarkMode ? '#9CA3AF' : '#6B7280';
    const axisLineColor = isDarkMode ? '#374151' : '#E5E7EB';
    const gridLineColor = isDarkMode ? '#1F2937' : '#E5E7EB';
    const legendText = isDarkMode ? '#D1D5DB' : '#374151';

    const extractPointValue = (point) => {
      if (Array.isArray(point)) return Number(point[1]);
      if (point && typeof point === 'object') {
        if (Array.isArray(point.value)) return Number(point.value[1]);
        if ('value' in point) return Number(point.value);
      }
      if (Number.isFinite(point)) return Number(point);
      return null;
    };

    const updateBounds = (bounds, value) => {
      if (!Number.isFinite(value)) return;
      if (value < bounds.min) bounds.min = value;
      if (value > bounds.max) bounds.max = value;
    };

    const seriesBounds = { min: Infinity, max: -Infinity };
    series.forEach((s) => {
      (s.data || []).forEach((point) => updateBounds(seriesBounds, extractPointValue(point)));
    });

    let alertAxis = null;
    if (shouldApplyAlertAxis) {
      const overlayBounds = { min: Infinity, max: -Infinity };
      if (overlay) {
        if (Array.isArray(overlay.reference_lines)) {
          overlay.reference_lines.forEach((line) => updateBounds(overlayBounds, Number(line.value)));
        }
        if (Array.isArray(overlay.bands)) {
          overlay.bands.forEach((band) => {
            updateBounds(overlayBounds, Number(band.min));
            updateBounds(overlayBounds, Number(band.max));
          });
        }
        if (Array.isArray(overlay.points)) {
          overlay.points.forEach((point) => updateBounds(overlayBounds, Number(point.value)));
        }
      }
      const minCandidates = [seriesBounds.min, overlayBounds.min].filter(Number.isFinite);
      const maxCandidates = [seriesBounds.max, overlayBounds.max].filter(Number.isFinite);
      const positiveOnly = minCandidates.length === 0 || minCandidates.every((value) => value >= 0);
      let axisMinCandidate = minCandidates.length ? Math.min(...minCandidates) : (positiveOnly ? 0 : -1);
      let axisMaxCandidate = maxCandidates.length ? Math.max(...maxCandidates) : (axisMinCandidate > 0 ? axisMinCandidate : 1);
      if (Number.isFinite(axisMaxCandidate)) {
        if (!Number.isFinite(axisMinCandidate)) {
          axisMinCandidate = positiveOnly ? 0 : axisMaxCandidate;
        }
        alertAxis = { positiveOnly, axisMinCandidate, axisMaxCandidate };
      }
    }

    const yAxis = {
      type: 'value',
      min: 0,
      name: normalized ? (data.y_label || 'Percentage') : (data.y_label || ''),
      nameLocation: 'middle',
      nameGap: 44,
      nameTextStyle: { color: textColor, fontFamily: chartFontFamily },
      axisLine: { lineStyle: { color: axisLineColor } },
      axisLabel: {
        color: textColor,
        margin: 10,
        hideOverlap: true,
        fontFamily: chartFontFamily
      },
      splitLine: { lineStyle: { color: gridLineColor, opacity: isDarkMode ? 0.4 : 1 } }
    };

    if (normalized) {
      yAxis.axisLabel = Object.assign({}, yAxis.axisLabel, { formatter: (v) => `${v}%` });
      if (alertAxis) {
        const normalizedMax = Math.max(alertAxis.axisMaxCandidate, 100);
        const topPad = normalizedMax * 0.05 || 5;
        yAxis.min = 0;
        yAxis.max = normalizedMax + topPad;
      } else {
        yAxis.max = 100;
      }
    } else {
      yAxis.axisLabel = Object.assign({}, yAxis.axisLabel, {
        formatter: (value) => formatCompactNumber(value)
      });
      if (alertAxis) {
        let axisMin = alertAxis.positiveOnly ? 0 : alertAxis.axisMinCandidate;
        let axisMax = Math.max(alertAxis.axisMaxCandidate, axisMin + 1);
        if (!Number.isFinite(axisMin)) axisMin = 0;
        if (!Number.isFinite(axisMax)) axisMax = axisMin + 1;
        if (axisMax <= axisMin) axisMax = axisMin + Math.max(Math.abs(axisMin), 1);
        const span = axisMax - axisMin;
        const topPad = span * 0.12 || Math.max(Math.abs(axisMax), 1) * 0.12;
        const bottomPad = alertAxis.positiveOnly ? 0 : (span * 0.05 || topPad * 0.5);
        axisMax += topPad;
        axisMin -= bottomPad;
        if (alertAxis.positiveOnly && axisMin < 0) axisMin = 0;
        yAxis.min = axisMin;
        yAxis.max = axisMax;
      } else if (Number.isFinite(seriesBounds.min) && seriesBounds.min < 0) {
        const axisMin = seriesBounds.min;
        const rawMax = Number.isFinite(seriesBounds.max) ? seriesBounds.max : 0;
        let axisMax = rawMax;
        if (!Number.isFinite(axisMax) || axisMax <= axisMin) {
          axisMax = axisMin + Math.max(Math.abs(axisMin), 1);
        }
        const span = axisMax - axisMin;
        const pad = span * 0.1 || Math.max(Math.abs(axisMax), 1) * 0.1;
        yAxis.min = axisMin - pad * 0.4;
        yAxis.max = axisMax + pad;
      }
    }

    chart.setOption({
      backgroundColor: 'transparent',
      textStyle: { fontFamily: chartFontFamily },
      color: palette.length ? palette : undefined,
      grid: { top: 12, bottom: bottomPadding, left: 56, right: 24, containLabel: true },
      xAxis: {
        type: 'time',
        axisLine: { lineStyle: { color: axisLineColor } },
        axisLabel: {
          color: textColor,
          margin: 10,
          hideOverlap: true,
          fontFamily: chartFontFamily
        },
        splitLine: { show: false }
      },
      yAxis,
      legend: showLegend ? { type: 'scroll', bottom: 6, textStyle: { color: legendText, fontFamily: chartFontFamily } } : { show: false },
      tooltip: {
        trigger: 'axis',
        appendToBody: true,
        textStyle: { fontFamily: chartFontFamily },
        valueFormatter: (v) => {
          if (v == null) return '-';
          return normalized ? `${Number(v).toFixed(2)}%` : formatCompactNumber(v);
        }
      },
      series
    }, true);

    try { chart.resize(); } catch (_) {}
    this.renderTimeseriesTable(data);
  },

  renderKpi(data, visual) {
    if (!this.chartTarget) return;
    this.disposeChart();
    this.chartTarget.innerHTML = '';

    if (!data) {
      this.showChartPlaceholder('No KPI data available yet.');
      this.showTablePlaceholder('Series summary is only available when a sparkline is enabled.');
      return;
    }

    const wrapper = document.createElement('div');
    wrapper.className = 'h-full w-full flex flex-col gap-6 p-6';

    const widgetTitle = this.el.dataset.title;
    if (widgetTitle) {
      const titleEl = document.createElement('div');
      titleEl.className = 'text-sm font-medium uppercase tracking-wide text-slate-500 dark:text-slate-300';
      titleEl.textContent = widgetTitle;
      wrapper.appendChild(titleEl);
    }

    const headline = document.createElement('div');
    headline.className = 'text-5xl font-semibold text-slate-900 dark:text-white';
    headline.textContent = this.formatKpiMainValue(data);
    wrapper.appendChild(headline);

    const metaHtml = this.formatKpiMeta(data);
    if (metaHtml) {
      const meta = document.createElement('div');
      meta.className = 'text-base text-slate-600 dark:text-slate-300';
      meta.innerHTML = metaHtml;
      wrapper.appendChild(meta);
    }

    this.chartTarget.appendChild(wrapper);

    let seriesEntries = [];
    const baseSeriesName = (data.path && String(data.path)) || this.el.dataset.title || 'Series';

    if (visual && visual.type === 'sparkline' && Array.isArray(visual.data) && visual.data.length) {
      const chartWrapper = document.createElement('div');
      chartWrapper.className =
        'flex-1 min-h-[240px] rounded-lg border border-gray-200 dark:border-slate-700/80 bg-white dark:bg-slate-900/40 p-4';
      const chartDiv = document.createElement('div');
      chartDiv.className = 'h-full w-full';
      chartWrapper.appendChild(chartDiv);
      wrapper.appendChild(chartWrapper);

      const theme = this.getTheme();
      const lineColor = this.seriesColor(0);
      const initSparkline = () => {
        if (chartDiv.clientWidth === 0 || chartDiv.clientHeight === 0) {
          if (this._sparklineTimer) clearTimeout(this._sparklineTimer);
          this._sparklineTimer = setTimeout(initSparkline, 80);
          return;
        }

        const chart = echarts.init(chartDiv, theme === 'dark' ? 'dark' : undefined, withChartOpts({ height: 240 }));
        this.chart = chart;
        this.chartElement = chartDiv;
        this.chartTheme = theme;

        chart.setOption({
          backgroundColor: 'transparent',
          grid: { top: 16, bottom: 16, left: 32, right: 32 },
          xAxis: { type: 'time', show: false },
          yAxis: { type: 'value', show: false },
          tooltip: {
            trigger: 'axis',
            appendToBody: true,
            valueFormatter: (v) => (v == null ? '-' : formatCompactNumber(v))
          },
          series: [{
            type: 'line',
            data: visual.data,
            smooth: true,
            showSymbol: false,
            lineStyle: { width: 2, color: lineColor },
            areaStyle: { color: lineColor, opacity: 0.18 }
          }]
        }, true);

        try { chart.resize(); } catch (_) {}
        if (this._sparklineTimer) {
          clearTimeout(this._sparklineTimer);
          this._sparklineTimer = null;
        }
      };

      initSparkline();

      seriesEntries = [{
        name: baseSeriesName,
        data: visual.data,
        color: lineColor
      }];
    } else if (visual && visual.type === 'progress') {
      const container = document.createElement('div');
      container.className =
        'flex-1 min-h-[180px] rounded-lg border border-gray-200 dark:border-slate-700/80 bg-white dark:bg-slate-900/40 p-6 flex flex-col justify-center gap-3';
      const label = document.createElement('div');
      label.className = 'text-sm text-slate-600 dark:text-slate-300';
      label.textContent = 'Progress';
      container.appendChild(label);

      const barOuter = document.createElement('div');
      barOuter.className = 'w-full h-4 rounded-full bg-gray-200 dark:bg-slate-700';
      const barInner = document.createElement('div');
      const progressCurrent = Number(visual.current);
      const target = Number(visual.target);
      const axisMax = Math.max(target || 0, progressCurrent || 0, 1);
      const ratio =
        Number.isFinite(progressCurrent) && axisMax !== 0 ? Math.max(0, Math.min(1, progressCurrent / axisMax)) : 0;
      barInner.className = 'h-4 rounded-full';
      barInner.style.width = `${ratio * 100}%`;
      barInner.style.background = this.getProgressColor(visual);
      barOuter.appendChild(barInner);
      container.appendChild(barOuter);

      wrapper.appendChild(container);

      if (Number.isFinite(progressCurrent)) {
        seriesEntries = [{
          name: baseSeriesName,
          data: [[Date.now(), progressCurrent]],
          color: this.seriesColor(0)
        }];
      }
    }

    if (!seriesEntries.length) {
      const fallbackValue =
        Number.isFinite(Number(data.value)) ? Number(data.value) :
        Number.isFinite(Number(data.current)) ? Number(data.current) :
        Number.isFinite(Number(data.previous)) ? Number(data.previous) :
        null;

      if (fallbackValue != null && Number.isFinite(fallbackValue)) {
        seriesEntries = [{
          name: baseSeriesName,
          data: [[Date.now(), fallbackValue]],
          color: this.seriesColor(0)
        }];
      }
    }

    if (seriesEntries.length) {
      this.renderSeriesSummary(seriesEntries, 'No series data available yet.');
    } else {
      this.showTablePlaceholder('No series data available yet.');
    }
  },

  renderText(data) {
    if (!this.chartTarget) return;
    this.disposeChart();
    this.chartTarget.innerHTML = '';

    if (!data) {
      this.showChartPlaceholder('No content available yet.');
      return;
    }

    if ((data.subtype || '').toLowerCase() === 'html' && data.payload) {
      const html = document.createElement('div');
      html.className = 'w-full h-full overflow-auto text-left text-slate-900 dark:text-slate-100 p-6';
      html.innerHTML = data.payload;
      this.chartTarget.appendChild(html);
      return;
    }

    const wrapper = document.createElement('div');
    wrapper.className = 'w-full h-full flex flex-col gap-4 justify-center items-center text-center p-8';

    if (data.title) {
      const title = document.createElement('div');
      title.className = 'text-4xl font-semibold text-slate-900 dark:text-slate-50';
      title.textContent = data.title;
      wrapper.appendChild(title);
    }

    if (data.subtitle) {
      const subtitle = document.createElement('div');
      subtitle.className = 'text-lg text-slate-600 dark:text-slate-300 max-w-3xl whitespace-pre-line';
      subtitle.textContent = data.subtitle;
      wrapper.appendChild(subtitle);
    }

    this.chartTarget.appendChild(wrapper);
  },

  renderTimeseriesTable(data) {
    if (!this.tableRoot) return;
    const entries = Array.isArray(data?.series)
      ? data.series.map((series, idx) => ({
          name: series.name || `Series ${idx + 1}`,
          data: series.data || [],
          color: this.seriesColor(idx)
        }))
      : [];

    this.renderSeriesSummary(entries, 'No series data available yet.');
  },

  renderSeriesSummary(seriesEntries, emptyMessage) {
    if (!this.tableRoot) return;
    if (!Array.isArray(seriesEntries) || seriesEntries.length === 0) {
      this.showTablePlaceholder(emptyMessage);
      return;
    }

    const escapeHtml = (str) => String(str || '').replace(/[&<>"']/g, (s) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[s]));
    const rows = seriesEntries.map((entry, idx) => {
      const color = entry.color || this.seriesColor(idx);
      const values = this.extractNumericValues(entry.data);
      const stats = this.computeSeriesStats(values);
      const name = escapeHtml(entry.name || `Series ${idx + 1}`);
      const formatRaw = (value) => {
        if (!Number.isFinite(value)) return '';
        try { return new Intl.NumberFormat(undefined, { maximumFractionDigits: 6 }).format(value); }
        catch (_) { return String(value); }
      };
      const formatStat = (value) => Number.isFinite(value) ? formatCompactNumber(value) : '—';

      return {
        name,
        color,
        min: { display: formatStat(stats.min), raw: escapeHtml(formatRaw(stats.min)) },
        max: { display: formatStat(stats.max), raw: escapeHtml(formatRaw(stats.max)) },
        mean: { display: formatStat(stats.mean), raw: escapeHtml(formatRaw(stats.mean)) },
        sum: { display: formatStat(stats.sum), raw: escapeHtml(formatRaw(stats.sum)) }
      };
    });

    const bodyHtml = rows.map((row) => `
      <tr>
        <td class="py-2 pr-4 pl-5 text-sm whitespace-nowrap text-gray-600 dark:text-slate-300">
          <div class="flex items-center gap-3">
            <span class="inline-flex h-2.5 w-2.5 rounded-full" style="background-color: ${row.color};"></span>
            <span class="font-medium" style="color: ${row.color};">${row.name}</span>
          </div>
        </td>
        <td class="px-5 py-2 text-sm whitespace-nowrap text-gray-500 dark:text-slate-200" data-tooltip="${row.min.raw}">${row.min.display}</td>
        <td class="px-5 py-2 text-sm whitespace-nowrap text-gray-500 dark:text-slate-200" data-tooltip="${row.max.raw}">${row.max.display}</td>
        <td class="px-5 py-2 text-sm whitespace-nowrap text-gray-500 dark:text-slate-200" data-tooltip="${row.mean.raw}">${row.mean.display}</td>
        <td class="py-2 pr-5 pl-5 text-sm whitespace-nowrap text-gray-500 dark:text-slate-200" data-tooltip="${row.sum.raw}">${row.sum.display}</td>
      </tr>
    `).join('');

    this.tableRoot.innerHTML = `
      <div class="h-full overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-300 dark:divide-slate-700">
          <thead class="bg-white dark:bg-slate-900/60">
            <tr>
              <th scope="col" class="py-3.5 pr-4 pl-5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Path</th>
              <th scope="col" class="px-5 py-3.5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Min</th>
              <th scope="col" class="px-5 py-3.5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Max</th>
              <th scope="col" class="px-5 py-3.5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Mean</th>
              <th scope="col" class="py-3.5 pr-5 pl-5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Sum</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 bg-white dark:divide-slate-700 dark:bg-slate-900/60">
            ${bodyHtml}
          </tbody>
        </table>
      </div>
    `;

    this.activateFastTooltips();
  },

  extractNumericValues(seriesData) {
    if (!Array.isArray(seriesData)) return [];
    return seriesData
      .map((point) => {
        if (Array.isArray(point)) return Number(point[1]);
        if (point && typeof point === 'object') {
          if (Array.isArray(point.value)) return Number(point.value[1]);
          if ('value' in point) return Number(point.value);
        }
        return Number(point);
      })
      .filter((value) => Number.isFinite(value));
  },

  computeSeriesStats(values) {
    if (!Array.isArray(values) || values.length === 0) {
      return { min: null, max: null, mean: null, sum: null };
    }
    const sum = values.reduce((acc, value) => acc + value, 0);
    const min = Math.min(...values);
    const max = Math.max(...values);
    const mean = sum / values.length;
    return { min, max, mean, sum };
  },

  formatKpiMainValue(data) {
    const subtype = String(data.subtype || 'number').toLowerCase();
    const formatMaybe = (value) => (Number.isFinite(value) ? formatCompactNumber(value) : '—');

    switch (subtype) {
      case 'split':
        return formatMaybe(Number(data.current));
      case 'goal':
        return formatMaybe(Number(data.value));
      default:
        return formatMaybe(Number(data.value));
    }
  },

  formatKpiMeta(data) {
    const subtype = String(data.subtype || 'number').toLowerCase();
    const formatMaybe = (value) => (Number.isFinite(value) ? formatCompactNumber(value) : '—');

    if (subtype === 'split') {
      const current = Number(data.current);
      const previous = Number(data.previous);
      const diff = Number.isFinite(current) && Number.isFinite(previous) ? current - previous : null;
      const diffPct =
        Number.isFinite(current) && Number.isFinite(previous) && previous !== 0
          ? ((current - previous) / Math.abs(previous)) * 100
          : null;

      let diffFragment = '';
      if (data.show_diff && diffPct != null) {
        const formatted = `${diffPct >= 0 ? '+' : ''}${diffPct.toFixed(1)}%`;
        diffFragment = ` · <span class="${diff >= 0 ? 'text-emerald-500' : 'text-rose-500'}">${formatted}</span>`;
      }

      return `Current: <strong>${formatMaybe(current)}</strong> · Previous: <span class="opacity-80">${formatMaybe(previous)}</span>${diffFragment}`;
    }

    if (subtype === 'goal') {
      const value = Number(data.value);
      const target = Number(data.target);
      const ratio =
        Number.isFinite(value) && Number.isFinite(target) && target !== 0 ? (value / target) * 100 : null;
      const ratioText = ratio != null ? `${ratio.toFixed(1)}%` : '—';

      return `Target: <span class="opacity-80">${formatMaybe(target)}</span> · Progress: <strong>${ratioText}</strong>`;
    }

    return '';
  },

  getProgressColor(visual) {
    if (!visual) return '#14b8a6';
    const ratio = Number.isFinite(Number(visual.ratio)) ? Number(visual.ratio) : null;
    if (ratio == null) return '#14b8a6';
    if (visual.invert) {
      return ratio <= 1 ? '#14b8a6' : '#ef4444';
    }
    return ratio >= 1 ? '#22c55e' : '#14b8a6';
  },

  renderCategory(data) {
    if (!data || !Array.isArray(data.data) || data.data.length === 0) {
      this.showChartPlaceholder('No category data available yet.');
      this.showTablePlaceholder('No categories available yet.');
      return;
    }
    const chart = this.ensureChart();
    if (!chart) return;

    const theme = this.getTheme();
    const isDarkMode = theme === 'dark';
    const type = String(data.chart_type || 'bar').toLowerCase();

    let option;
    if (type === 'pie' || type === 'donut') {
      const labelColor = isDarkMode ? '#E2E8F0' : '#1F2937';
      const labelLineColor = isDarkMode ? '#475569' : '#94A3B8';
      option = {
        backgroundColor: 'transparent',
        tooltip: {
          trigger: 'item',
          appendToBody: true,
          textStyle: { color: isDarkMode ? '#F8FAFC' : '#1F2937' },
          backgroundColor: isDarkMode ? '#111827' : '#FFFFFF',
          borderColor: isDarkMode ? '#334155' : '#E5E7EB'
        },
        color: this.colors.length ? this.colors : undefined,
        series: [{
          type: 'pie',
          radius: type === 'donut' ? ['50%', '72%'] : '70%',
          data: data.data,
          label: { color: labelColor },
          labelLine: { lineStyle: { color: labelLineColor } },
          itemStyle: {
            color: (params) => this.seriesColor(params.dataIndex)
          }
        }]
      };
    } else {
      option = {
        backgroundColor: 'transparent',
        grid: { top: 20, bottom: 40, left: 80, right: 36 },
        xAxis: { type: 'category', data: data.data.map((d) => d.name) },
        yAxis: {
          type: 'value',
          min: 0,
          axisLabel: { formatter: (v) => formatCompactNumber(v) }
        },
        tooltip: { trigger: 'axis', appendToBody: true },
        series: [{
          type: 'bar',
          data: data.data.map((d) => d.value),
          itemStyle: {
            color: (params) => this.seriesColor(params.dataIndex)
          }
        }]
      };
    }

    chart.setOption(option, true);
    try { chart.resize(); } catch (_) {}

    this.renderCategoryTable(data);
  },
  renderDistribution(data) {
    const is3d = String(data?.mode || '2d').toLowerCase() === '3d';
    const labels = Array.isArray(data?.bucket_labels) ? data.bucket_labels : [];
    const verticalLabelsRaw = Array.isArray(data?.vertical_bucket_labels) ? data.vertical_bucket_labels : [];
    const series = Array.isArray(data?.series) ? data.series : [];
    const legendFlag = data?.legend;
    const showLegendDefault = series.length > 1;
    const showLegend = legendFlag === undefined ? showLegendDefault : !!legendFlag;
    const bottomPadding = showLegend ? 56 : 24;
    const chartFontFamily =
      'Inter var, Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';

    let verticalLabels = verticalLabelsRaw;
    if (is3d && (!verticalLabels || verticalLabels.length === 0)) {
      const derived = new Set();
      series.forEach((s) => {
        (Array.isArray(s?.points) ? s.points : []).forEach((p) => {
          if (p && p.bucket_y != null && p.bucket_y !== '') derived.add(String(p.bucket_y));
        });
      });
      verticalLabels = Array.from(derived);
    }

    if (
      !Array.isArray(labels) ||
      labels.length === 0 ||
      !Array.isArray(series) ||
      series.length === 0 ||
      (is3d && (!verticalLabels || verticalLabels.length === 0))
    ) {
      this.showChartPlaceholder('No distribution data available yet.');
      this.renderDistributionTable(data);
      return;
    }

    const chart = this.ensureChart({ height: 480 });
    if (!chart) {
      this.renderDistributionTable(data);
      return;
    }

    const theme = this.getTheme();
    const isDarkMode = theme === 'dark';
    const colors = Array.isArray(this.colors) && this.colors.length ? this.colors : null;

    if (is3d) {
      let maxValue = 0;
      const legendNames = [];
      let seriesData = series.map((seriesItem, idx) => {
        const name = seriesItem?.name || `Series ${idx + 1}`;
        legendNames.push(name);
        const points = Array.isArray(seriesItem?.points) ? seriesItem.points : [];
        const color = colors ? colors[idx % colors.length] : this.seriesColor(idx);
        const dataPoints = points
          .map((p) => {
            if (!p) return null;
            const xIdx = labels.indexOf(p.bucket_x);
            const yIdx = verticalLabels.indexOf(p.bucket_y);
            if (xIdx === -1 || yIdx === -1) return null;
            const val = Number(p.value) || 0;
            maxValue = Math.max(maxValue, val);
            return [xIdx, yIdx, val];
          })
          .filter(Boolean);

        return {
          name,
          type: 'scatter',
          data: dataPoints,
          symbolSize: (val) => {
            const v = val && val[2] ? val[2] : 0;
            if (!maxValue) return 10;
            const size = 8 + (v / maxValue) * 24;
            return Math.max(6, size);
          },
          itemStyle: { color, opacity: 1 },
          hoverAnimation: false,
          emphasis: {
            disabled: true,
            focus: 'none',
            scale: false,
            blurScope: 'none',
            itemStyle: { opacity: 1 }
          },
          select: { disabled: true }
        };
      });

      seriesData = seriesData.filter((s) => Array.isArray(s.data) && s.data.length);

      if (!seriesData.length) {
        this.showChartPlaceholder('No distribution data available yet.');
        this.renderDistributionTable(data);
        return;
      }

      const option = {
        backgroundColor: 'transparent',
        legend: showLegend
          ? {
              data: legendNames,
              textStyle: { color: isDarkMode ? '#E2E8F0' : '#0F172A', fontFamily: chartFontFamily },
              bottom: 0,
              type: legendNames.length > 4 ? 'scroll' : 'plain'
            }
          : { show: false },
        grid: { top: 16, left: 64, right: 16, bottom: bottomPadding },
        tooltip: {
          trigger: 'item',
          appendToBody: true,
          formatter: (params) => {
            const valueArr =
              Array.isArray(params.value) && params.value.length >= 3
                ? params.value
                : Array.isArray(params.data) && params.data.length >= 3
                  ? params.data
                  : null;

            if (!valueArr) return '';

            const xIdx = Number.isFinite(valueArr[0]) ? valueArr[0] : null;
            const yIdx = Number.isFinite(valueArr[1]) ? valueArr[1] : null;
            const val = Number.isFinite(valueArr[2]) ? valueArr[2] : 0;
            const xLabel = xIdx != null && labels[xIdx] ? labels[xIdx] : labels[0] || '';
            const yLabel = yIdx != null && verticalLabels[yIdx] ? verticalLabels[yIdx] : verticalLabels[0] || '';

            if (!xLabel && !yLabel) return '';

            const seriesName = params.seriesName || '';
            const marker = params.marker || '';
            const lines = [`${xLabel} × ${yLabel}`];

            if (seriesName || marker) {
              lines.push(`${marker}${seriesName}  <strong>${formatCompactNumber(val)}</strong>`);
            }

            return lines.join('<br/>');
          }
        },
        axisPointer: {
          show: true,
          type: 'line',
          lineStyle: { type: 'dashed', color: isDarkMode ? '#94a3b8' : '#0f172a' },
          link: [{ xAxisIndex: 'all' }, { yAxisIndex: 'all' }]
        },
        xAxis: {
          type: 'category',
          data: labels,
          splitLine: {
            show: true,
            lineStyle: { type: 'dashed', color: isDarkMode ? '#1f2937' : '#e2e8f0', opacity: isDarkMode ? 0.4 : 0.9 }
          },
          axisLabel: { color: isDarkMode ? '#CBD5F5' : '#475569', interval: 0, rotate: labels.length > 8 ? 30 : 0 }
        },
        yAxis: {
          type: 'category',
          data: verticalLabels,
          splitLine: {
            show: true,
            lineStyle: { type: 'dashed', color: isDarkMode ? '#1f2937' : '#e2e8f0', opacity: isDarkMode ? 0.4 : 0.9 }
          },
          axisLabel: { color: isDarkMode ? '#CBD5F5' : '#475569' }
        },
        series: seriesData
      };

      chart.setOption(option, true);
      try { chart.resize(); } catch (_) {}
      this.renderDistributionTable(data);
      return;
    }

    const legendNames = [];
    const seriesData = series.map((seriesItem, idx) => {
      const name = seriesItem?.name || `Series ${idx + 1}`;
      legendNames.push(name);
      const values = Array.isArray(seriesItem?.values) ? seriesItem.values : [];
      const color = colors ? colors[idx % colors.length] : this.seriesColor(idx);
      const dataPoints = labels.map((label) => {
        const match = values.find((v) => v && (v.bucket === label || v.bucket_x === label));
        const val = match && Number.isFinite(Number(match.value)) ? Number(match.value) : 0;
        return val;
      });
      return {
        name,
        type: 'bar',
        emphasis: { focus: 'series' },
        itemStyle: { color },
        data: dataPoints
      };
    });

    const option = {
      backgroundColor: 'transparent',
      legend: showLegend
        ? {
            data: legendNames,
            textStyle: { color: isDarkMode ? '#E2E8F0' : '#0F172A', fontFamily: chartFontFamily },
            bottom: 0,
            type: legendNames.length > 4 ? 'scroll' : 'plain'
          }
        : { show: false },
      grid: { top: 16, left: 52, right: 16, bottom: bottomPadding, containLabel: true },
      tooltip: {
        trigger: 'axis',
        axisPointer: {
          type: 'line',
          lineStyle: { color: isDarkMode ? '#CBD5F5' : '#94a3b8', width: 1.5, type: 'dashed' }
        },
        appendToBody: true,
        valueFormatter: (v) => (v == null ? '-' : formatCompactNumber(v))
      },
      xAxis: {
        type: 'category',
        data: labels,
        axisLabel: { color: isDarkMode ? '#CBD5F5' : '#475569', interval: 0, rotate: labels.length > 6 ? 30 : 0 }
      },
      yAxis: {
        type: 'value',
        min: 0,
        axisLabel: { formatter: (value) => formatCompactNumber(value), color: isDarkMode ? '#CBD5F5' : '#475569' },
        splitLine: { lineStyle: { color: isDarkMode ? '#1f2937' : '#e2e8f0', opacity: isDarkMode ? 0.35 : 1 } }
      },
      series: seriesData
    };

    chart.setOption(option, true);
    try { chart.resize(); } catch (_) {}
    this.renderDistributionTable(data);
  },

  renderDistributionTable(data) {
    if (!this.tableRoot) return;
    const is3d = String(data?.mode || '2d').toLowerCase() === '3d';
    const series = Array.isArray(data?.series) ? data.series : [];
    const rows = [];

    series.forEach((seriesItem, idx) => {
      const name = seriesItem?.name || `Series ${idx + 1}`;
      const color = this.seriesColor(idx);

      if (is3d) {
        const points = Array.isArray(seriesItem?.points) ? seriesItem.points : [];
        points.forEach((p) => {
          if (!p) return;
          const value = Number(p.value);
          if (!Number.isFinite(value)) return;
          rows.push({
            series: name,
            color,
            bucket_x: p.bucket_x || '',
            bucket_y: p.bucket_y || '',
            value
          });
        });
      } else {
        const values = Array.isArray(seriesItem?.values) ? seriesItem.values : [];
        values.forEach((v) => {
          if (!v) return;
          const value = Number(v.value);
          if (!Number.isFinite(value)) return;
          rows.push({
            series: name,
            color,
            bucket_x: v.bucket || v.bucket_x || '',
            bucket_y: '',
            value
          });
        });
      }
    });

    if (!rows.length) {
      this.showTablePlaceholder('No distribution data available yet.');
      return;
    }

    rows.sort((a, b) => Number(b.value || 0) - Number(a.value || 0));

    const hasSeries = series.length > 1;
    const hasVertical = is3d && rows.some((row) => row.bucket_y);

    const escapeHtml = (str) =>
      String(str || '').replace(/[&<>"']/g, (s) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[s]));
    const formatRaw = (value) => {
      if (!Number.isFinite(value)) return '';
      try {
        return new Intl.NumberFormat(undefined, { maximumFractionDigits: 6 }).format(value);
      } catch (_) {
        return String(value);
      }
    };

    const headerCells = [];
    if (hasSeries) {
      headerCells.push(
        '<th scope="col" class="py-3.5 pr-4 pl-5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Series</th>'
      );
    }
    headerCells.push(
      '<th scope="col" class="px-5 py-3.5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Horizontal Bucket</th>'
    );
    if (hasVertical) {
      headerCells.push(
        '<th scope="col" class="px-5 py-3.5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Vertical Bucket</th>'
      );
    }
    headerCells.push(
      '<th scope="col" class="py-3.5 pr-5 pl-5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Value</th>'
    );

    const bodyRows = rows
      .map((row) => {
        const bucketX = escapeHtml(row.bucket_x || '');
        const bucketY = escapeHtml(row.bucket_y || '');
        const formattedValue = Number.isFinite(row.value) ? formatCompactNumber(row.value) : '—';
        const raw = escapeHtml(formatRaw(row.value));

        const seriesCell = hasSeries
          ? `
            <td class="py-2 pr-4 pl-5 text-sm whitespace-nowrap text-gray-600 dark:text-slate-300">
              <div class="flex items-center gap-3">
                <span class="inline-flex h-2.5 w-2.5 rounded-full" style="background-color: ${row.color};"></span>
                <span class="font-medium" style="color: ${row.color};">${escapeHtml(row.series)}</span>
              </div>
            </td>
          `
          : '';

        const verticalCell = hasVertical
          ? `<td class="px-5 py-2 text-sm whitespace-nowrap text-gray-600 dark:text-slate-200 font-mono">${bucketY || 'total'}</td>`
          : '';

        return `
          <tr>
            ${seriesCell}
            <td class="px-5 py-2 text-sm whitespace-nowrap text-gray-600 dark:text-slate-200 font-mono">${bucketX || 'total'}</td>
            ${verticalCell}
            <td class="py-2 pr-5 pl-5 text-sm whitespace-nowrap text-gray-500 dark:text-slate-200" data-tooltip="${raw}">${formattedValue}</td>
          </tr>
        `;
      })
      .join('');

    this.tableRoot.innerHTML = `
      <div class="h-full overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-300 dark:divide-slate-700">
          <thead class="bg-white dark:bg-slate-900/60">
            <tr>
              ${headerCells.join('')}
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 bg-white dark:divide-slate-700 dark:bg-slate-900/60">
            ${bodyRows}
          </tbody>
        </table>
      </div>
    `;

    this.activateFastTooltips();
  },

  showChartPlaceholder(message) {
    if (!this.chartTarget) return;
    this.disposeChart();
    this.chartTarget.innerHTML = '';
    const placeholder = document.createElement('div');
    placeholder.className = 'w-full h-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 text-center px-6';
    placeholder.textContent = message;
    this.chartTarget.appendChild(placeholder);
  },

  showTablePlaceholder(message) {
    if (!this.tableRoot) return;
    this.tableRoot.innerHTML = `
      <div class="h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 px-6 text-center">
        ${message}
      </div>
    `;
  },

  renderCategoryTable(data) {
    if (!this.tableRoot) return;
    const items = Array.isArray(data?.data) ? data.data : [];
    if (!items.length) {
      this.showTablePlaceholder('No categories available yet.');
      return;
    }

    const escapeHtml = (str) => String(str || '').replace(/[&<>"']/g, (s) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[s]));
    const formatRaw = (value) => {
      if (!Number.isFinite(value)) return '';
      try {
        return new Intl.NumberFormat(undefined, { maximumFractionDigits: 6 }).format(value);
      } catch (_) {
        return String(value);
      }
    };

    const rows = items.map((item, idx) => {
      const name = escapeHtml(String(item.name ?? `Item ${idx + 1}`));
      const value = Number(item.value);
      const color = this.seriesColor(idx);
      const formatted = Number.isFinite(value) ? formatCompactNumber(value) : '—';
      const raw = escapeHtml(formatRaw(value));

      return `
        <tr>
          <td class="py-2 pr-4 pl-5 text-sm whitespace-nowrap text-gray-600 dark:text-slate-300">
            <div class="flex items-center gap-3">
              <span class="inline-flex h-2.5 w-2.5 rounded-full" style="background-color: ${color};"></span>
              <span class="font-medium" style="color: ${color};">${name}</span>
            </div>
          </td>
          <td class="px-5 py-2 text-sm whitespace-nowrap text-gray-500 dark:text-slate-200" data-tooltip="${raw}">${formatted}</td>
        </tr>
      `;
    }).join('');

    this.tableRoot.innerHTML = `
      <div class="h-full overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-300 dark:divide-slate-700">
          <thead class="bg-white dark:bg-slate-900/60">
            <tr>
              <th scope="col" class="py-3.5 pr-4 pl-5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Category</th>
              <th scope="col" class="px-5 py-3.5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Value</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 bg-white dark:divide-slate-700 dark:bg-slate-900/60">
            ${rows}
          </tbody>
        </table>
      </div>
    `;

    this.activateFastTooltips();
  },

  activateFastTooltips() {
    if (!this.tableRoot) return;
    const fastTooltip = Hooks.FastTooltip;
    if (!fastTooltip || typeof fastTooltip.initTooltips !== 'function') return;
    const context = {
      el: this.tableRoot,
      showTooltip: fastTooltip.showTooltip.bind(fastTooltip),
      hideTooltip: fastTooltip.hideTooltip.bind(fastTooltip)
    };
    requestAnimationFrame(() => {
      try {
        fastTooltip.initTooltips.call(context);
      } catch (_) {}
    });
  }
};

Hooks.ExpandedAgGridTable = {
  mounted() {
    this.grid = null;
    this.gridOptions = null;
    this.lastPayload = null;
    this.handleThemeChange = () => this.applyTheme();
    window.addEventListener('trifle:theme-changed', this.handleThemeChange);
    this.render();
    setTimeout(() => this.render(), 150);
  },

  updated() {
    this.render();
  },

  destroyed() {
    window.removeEventListener('trifle:theme-changed', this.handleThemeChange);
    this.destroyGrid();
  },

  render() {
    const payloadString = this.el.dataset.table || '';
    if (!payloadString) {
      this.showEmpty();
      return;
    }
    if (payloadString === this.lastPayload && this.grid) {
      this.applyTheme();
      return;
    }
    this.lastPayload = payloadString;
    const payload = parseJsonSafe(payloadString);
    if (!payload) {
      this.showEmpty();
      return;
    }
    const rows = Array.isArray(payload.rows) ? payload.rows : [];
    if (rows.length === 0) {
      this.destroyGrid();
      this.showEmpty(payload.empty_message);
      return;
    }
    ensureAgGridCommunity()
      .then(() => this.renderGrid(payload))
      .catch((err) => {
        console.error('[ExpandedAgGridTable] Failed to load ag-grid-community', err);
        this.showEmpty('Unable to load table data.');
      });
  },

  renderGrid(payload) {
    const root = this.el.querySelector('[data-role="aggrid-table-root"]');
    if (!root) return;
    this.applyTheme();
    const shell = this.el;
    const shellHeight = shell && shell.clientHeight > 0 ? shell.clientHeight : (shell && shell.parentElement ? shell.parentElement.clientHeight : 0);
    const fallbackHeight = shellHeight > 0 ? shellHeight : 520;
    root.style.width = '100%';
    root.style.height = `${fallbackHeight}px`;
    root.style.minHeight = '400px';
    root.style.flex = '1 1 auto';
    const tableId = this.normalizeId(payload && payload.id);
    this.tableId = tableId;
    if (!this.grid || this.grid.root !== root || !this.grid.api) {
      this.destroyGrid();
      this.createGrid(root);
    }

    const columnDefs = this.buildColumns(payload);
    const rowData = this.buildRows(payload);

    try {
      this.grid.api.setColumnDefs(columnDefs);
      this.grid.api.setRowData(rowData);
      requestAnimationFrame(() => {
        try {
          this.autoSizePathColumn();
        } catch (_) {}
        try {
          this.grid.api.sizeColumnsToFit();
        } catch (_) {}
      });
    } catch (err) {
      console.error('[ExpandedAgGridTable] Failed to render grid', err);
      this.showEmpty('Unable to render table.');
    }
  },

  createGrid(root) {
    const agGrid = window.agGrid;
    if (!agGrid || typeof agGrid.Grid !== 'function') return;
    root.innerHTML = '';
    const gridOptions = {
      columnDefs: [],
      rowData: [],
      suppressCellFocus: true,
      suppressMovableColumns: true,
      suppressRowClickSelection: true,
      rowSelection: 'single',
      animateRows: false,
      rowHeight: 28,
      headerHeight: 48,
      enableRangeSelection: true,
      enableCellTextSelection: true,
      defaultColDef: {
        sortable: false,
        filter: false,
        resizable: false,
        flex: 1,
        headerComponent: getAggridHeaderComponentClass()
      }
    };
    new agGrid.Grid(root, gridOptions);
    this.grid = {
      api: gridOptions.api,
      columnApi: gridOptions.columnApi,
      root
    };
  },

  destroyGrid() {
    if (this.grid && this.grid.api && typeof this.grid.api.destroy === 'function') {
      try {
        this.grid.api.destroy();
      } catch (_) {}
    }
    this.grid = null;
  },

  showEmpty(message) {
    const root = this.el.querySelector('[data-role="aggrid-table-root"]');
    if (!root) return;
    this.destroyGrid();
    root.classList.remove('ag-theme-alpine', 'ag-theme-alpine-dark');
    root.innerHTML = `
      <div class="h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 px-6 text-center">
        ${this.escapeHtml(message || 'No data available yet.')}
      </div>
    `;
  },

  applyTheme() {
    const root = this.el.querySelector('[data-role="aggrid-table-root"]');
    if (!root) return;
    const isDark = document.documentElement.classList.contains('dark');
    this.el.dataset.theme = isDark ? 'dark' : 'light';
    root.classList.remove('ag-theme-alpine', 'ag-theme-alpine-dark');
    root.classList.add(isDark ? 'ag-theme-alpine-dark' : 'ag-theme-alpine');
    if (this.grid && this.grid.api) {
      try {
        this.grid.api.refreshCells({ force: true });
        this.grid.api.redrawRows();
      } catch (_) {}
      requestAnimationFrame(() => {
        try {
          this.grid.api.sizeColumnsToFit();
        } catch (_) {}
      });
    }
  },

  buildColumns(payload) {
    const columns = Array.isArray(payload.columns) ? payload.columns : [];
    const defs = [
      {
        field: 'path',
        headerName: 'Path',
        pinned: 'left',
        lockPinned: true,
        suppressMovable: true,
        minWidth: AGGRID_PATH_COL_MIN_WIDTH,
        maxWidth: AGGRID_PATH_COL_MAX_WIDTH,
        width: AGGRID_PATH_COL_MIN_WIDTH,
        suppressSizeToFit: true,
        resizable: true,
        cellRenderer: (params) => {
          const wrapper = document.createElement('div');
          wrapper.className = 'aggrid-path-cell';
          const html = params && params.data ? params.data.__pathHtml : '';
          if (html && typeof html === 'string') {
            wrapper.innerHTML = html;
          } else {
            wrapper.textContent =
              params && params.value != null ? String(params.value) : (params && params.data && params.data.path) || '';
          }
          return wrapper;
        },
        cellClass: 'aggrid-path-cell-wrapper aggrid-body-cell ag-left-aligned-cell',
        headerClass: 'aggrid-header-cell ag-left-aligned-header',
        headerComponentParams: { lines: ['Path'], align: 'left' }
      }
    ];

    columns.forEach((column, idx) => {
      const label = this.stripHtml(column && column.label ? column.label : `Column ${idx + 1}`);
      defs.push({
        field: `col_${idx}`,
        headerName: label,
        headerTooltip: label,
        type: 'numericColumn',
        minWidth: 120,
        flex: 1,
        valueFormatter: (params) => {
          if (!params || params.value === null || params.value === undefined || params.value === '') return '';
          const numeric = Number(params.value);
          if (!Number.isFinite(numeric)) return String(params.value);
          return numeric.toLocaleString(undefined, { maximumFractionDigits: 2 });
        },
        cellClass: 'aggrid-numeric-cell aggrid-body-cell ag-right-aligned-cell',
        headerClass: 'aggrid-header-cell ag-right-aligned-header',
        headerComponentParams: { lines: [label], align: 'right' }
      });
    });

    return defs;
  },

  buildRows(payload) {
    const columns = Array.isArray(payload.columns) ? payload.columns : [];
    const rows = Array.isArray(payload.rows) ? payload.rows : [];
    return rows.map((row) => {
      const data = {
        path: row && (row.display_path || row.path || ''),
        __pathHtml: row && row.path_html ? row.path_html : ''
      };
      const values = Array.isArray(row && row.values) ? row.values : [];
      columns.forEach((_, idx) => {
        data[`col_${idx}`] = values[idx] != null ? values[idx] : '';
      });
      return data;
    });
  },

  stripHtml(input) {
    if (!input || typeof input !== 'string') return '';
    return input.replace(/<[^>]*>/g, '').trim();
  },

  escapeHtml(text) {
    if (text == null) return '';
    return String(text)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  },

  normalizeId(id) {
    if (id == null) return null;
    if (typeof id === 'string') return id;
    if (typeof id === 'number') return String(id);
    if (typeof id === 'object' && 'toString' in id) return String(id);
    return null;
  },

  autoSizePathColumn() {
    if (!this.grid || !this.grid.columnApi) return;
    const column = this.grid.columnApi.getColumn('path');
    if (!column) return;
    try {
      this.grid.columnApi.autoSizeColumns(['path'], false);
    } catch (_) {}
    const colDef = column.getColDef ? column.getColDef() : null;
    const minWidth = (colDef && Number.isFinite(colDef.minWidth)) ? colDef.minWidth : AGGRID_PATH_COL_MIN_WIDTH;
    const maxWidth = (colDef && Number.isFinite(colDef.maxWidth)) ? colDef.maxWidth : AGGRID_PATH_COL_MAX_WIDTH;
    let width = null;
    try {
      width = column.getActualWidth ? column.getActualWidth() : null;
    } catch (_) {
      width = null;
    }
    if (!Number.isFinite(width)) return;
    const clamped = Math.max(minWidth || AGGRID_PATH_COL_MIN_WIDTH, Math.min(maxWidth || AGGRID_PATH_COL_MAX_WIDTH, width));
    if (clamped !== width) {
      try { this.grid.columnApi.setColumnWidth(column, clamped); } catch (_) {}
    }
  }
};
// Generic file download handler via pushEvent
Hooks.FileDownload = {
  mounted() {
    this.handleEvent('file_download', ({ content, content_base64, base64, filename, type }) => {
      try {
        let blob;
        if (base64 || content_base64) {
          const b64 = content_base64 || content || '';
          const bytes = this._b64ToUint8Array(b64);
          blob = new Blob([bytes], { type: type || 'application/octet-stream' });
        } else {
          blob = new Blob([content || ''], { type: type || 'application/octet-stream' });
        }
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename || 'download';
        document.body.appendChild(a);
        a.click();
        setTimeout(() => {
          URL.revokeObjectURL(url);
          document.body.removeChild(a);
        }, 0);
        // Notify any listeners that a download was initiated
        window.dispatchEvent(new CustomEvent('download:complete'));
      } catch (e) {
        console.error('File download failed', e);
      }
    });

    this.handleEvent('file_download_url', ({ url, filename, target }) => {
      try {
        if (!url) throw new Error('Missing url');
        // Prefer hidden iframe to avoid interfering with LiveView navigation
        const iframe = document.createElement('iframe');
        iframe.style.display = 'none';
        iframe.src = url;
        iframe.addEventListener('load', () => {
          window.dispatchEvent(new CustomEvent('download:complete'));
        });
        document.body.appendChild(iframe);
        // Safety cleanup
        setTimeout(() => { try { document.body.removeChild(iframe); } catch (_) {} }, 60000);
        // Note: Avoid forcing navigation to keep LiveView intact
      } catch (e) {
        console.error('File download url failed', e);
      }
    });

    this.handleEvent('export_dashboard_pdf', ({ title, timeframe, granularity }) => {
      try {
        const root = document.documentElement;
        const wasDark = root.classList.contains('dark');
        if (wasDark) root.classList.remove('dark');

        const header = document.createElement('div');
        header.id = 'dashboard-print-header';
        header.style.background = '#ffffff';
        header.style.color = '#0f172a';
        header.style.padding = '16px 24px';
        header.style.borderBottom = '1px solid #e5e7eb';
        header.style.fontFamily = 'ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, Helvetica Neue, Arial';
        header.innerHTML = `
          <div style="max-width: 1024px; margin: 0 auto;">
            <div style="font-size: 18px; font-weight: 600;">${this.escapeHtml(title || 'Dashboard')}</div>
            <div style="margin-top: 6px; font-size: 12px; color: #475569;">
              ${timeframe ? this.escapeHtml(timeframe) + ' • ' : ''}Granularity: ${this.escapeHtml(granularity || '')}
            </div>
          </div>
        `;
        document.body.prepend(header);

        const cleanup = () => {
          try { header.remove(); } catch (_) {}
          if (wasDark) root.classList.add('dark');
          window.removeEventListener('afterprint', cleanup);
        };
        window.addEventListener('afterprint', cleanup);
        setTimeout(() => window.print(), 50);
      } catch (e) {
        console.error('PDF export failed', e);
      }
    });
  },

  escapeHtml(str) { return String(str || '').replace(/[&<>"']/g, (s) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[s])); },

  _b64ToUint8Array(b64) {
    const binary = atob(b64);
    const len = binary.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }
};

// Download menu: close on click, show loading state until iframe loads
Hooks.DownloadMenu = {
  mounted() {
    this.loading = false;
    this.setElements();
    const datasetLabel = (this.el.dataset && this.el.dataset.defaultLabel) || '';
    this.originalLabel = datasetLabel || (this.label ? this.label.textContent : '');
    this.loadingLabel = (this.el.dataset && this.el.dataset.loadingLabel) || 'Exporting…';
    this.iframe = document.querySelector('iframe[name="download_iframe"]');
    this.hrefSignature = this.computeHrefSignature();

    this.bindAnchors();
    this.bindIframe();

    this.handleEvent('monitor_widget_export_params', ({ params }) => {
      this.updateExportLinks(params || {});
    });

    // Global completion signal (for blob-based downloads or alternate flows)
    this._onDownloadComplete = () => this.stopLoading();
    window.addEventListener('download:complete', this._onDownloadComplete);
  },

  updated() {
    // Rebind anchors when dropdown content re-renders and reselect elements that may have been replaced
    this.setElements();
    const datasetLabel = (this.el.dataset && this.el.dataset.defaultLabel) || '';
    if (datasetLabel) {
      this.originalLabel = datasetLabel;
    } else if (!this.originalLabel && this.label) {
      this.originalLabel = this.label.textContent;
    }

    const newSignature = this.computeHrefSignature();
    if (newSignature !== this.hrefSignature) {
      this.hrefSignature = newSignature;
      if (!this.loading) {
        this.stopLoading(true);
      }
    }

    this.bindAnchors();
    // Rebind iframe in case it was re-rendered
    const newIframe = document.querySelector('iframe[name="download_iframe"]');
    if (newIframe !== this.iframe) {
      this.iframe = newIframe;
      this._iframeBound = false;
      this.bindIframe();
    }
    // If still loading, re-apply loading UI state after LV patch
    if (this.loading) this.applyLoadingState();
  },

  updateExportLinks(params) {
    if (!params || typeof params !== 'object') return;
    const managedKeys = ['timeframe', 'granularity', 'from', 'to', 'segments', 'key'];
    this.el.querySelectorAll('a[data-export-link]').forEach((a) => {
      const href = a.getAttribute('href');
      if (!href) return;
      try {
        const url = new URL(href, window.location.origin);
        managedKeys.forEach((key) => {
          const value = params[key];
          if (value == null || value === '') {
            url.searchParams.delete(key);
          }
        });
        Object.entries(params).forEach(([key, value]) => {
          if (value == null || value === '') {
            url.searchParams.delete(key);
          } else {
            url.searchParams.set(key, value);
          }
        });
        url.searchParams.delete('download_token');
        a.setAttribute('href', url.toString());
      } catch (_) {
        // Ignore malformed hrefs
      }
    });
    this.hrefSignature = this.computeHrefSignature();
  },

  computeHrefSignature() {
    return Array.from(this.el.querySelectorAll('a[data-export-link]'))
      .map((a) => a.getAttribute('href') || '')
      .join('|');
  },

  bindAnchors() {
    if (this._bound) {
      return;
    }
    this._bound = true;
    this._onClickCapture = (e) => {
      const a = e.target.closest('a[data-export-link]');
      const btn = e.target.closest('button[data-export-trigger]');
      if (!this.el.contains(e.target)) return; // Only handle clicks within this menu
      if (a) {
        this.startLoading();
        setTimeout(() => this.pushEvent('hide_export_dropdown', {}), 0);
        return;
      }
      if (!btn) return;
      // Separate loading instance for button-triggered exports
      this.loading = true;
      this.applyLoadingState();
      // Generate token so iframe poller knows when to reset for button-trigger downloads
      const token = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      this._downloadToken = token;
      try { window.__downloadToken = token; } catch (_) {}
      this.pushEvent('hide_export_dropdown', {});
      // Start polling for the cookie to flip back UI when done
      this.startCookiePolling();
    };
    // Use capture phase to run before LiveView's phx-click-away handler
    document.addEventListener('click', this._onClickCapture, true);
  },

  bindIframe() {
    if (!this.iframe || this._iframeBound) return;
    this._iframeBound = true;
    this.iframe.addEventListener('load', () => {
      // Any load in the download iframe marks completion
      this.stopLoading();
    });
  },

  startLoading() {
    if (this.loading) return;
    this.loading = true;
    this.applyLoadingState();
  },

  stopLoading(force = false) {
    if (!this.loading && !force) return;
    this.loading = false;
    this.stopCookiePolling();
    if (this.button) {
      this.button.removeAttribute('data-loading');
      this.button.removeAttribute('aria-busy');
      this.button.classList.remove('opacity-70', 'cursor-wait');
      this.button.disabled = false;
    }
    const datasetLabel = (this.el.dataset && this.el.dataset.defaultLabel) || '';
    if (this.icon) this.icon.classList.remove('hidden');
    if (this.spinner) this.spinner.classList.add('hidden');
    if (this.label) this.label.textContent = this.originalLabel || datasetLabel || 'Download';
  },

  applyLoadingState() {
    if (this.button) {
      this.button.setAttribute('aria-busy', 'true');
      this.button.setAttribute('data-loading', 'true');
      this.button.classList.add('opacity-70', 'cursor-wait');
      this.button.disabled = true;
    }
    if (this.icon) this.icon.classList.add('hidden');
    if (this.spinner) this.spinner.classList.remove('hidden');
    if (this.label) this.label.textContent = this.loadingLabel;
  },

  startCookiePolling() {
    this.stopCookiePolling();
    const token = this._downloadToken;
    if (!token) return;
    const deadline = Date.now() + 60000; // 60s timeout
    this._cookieTimer = setInterval(() => {
      try {
        const cookieEntry = document.cookie.split('; ').find((c) => c.startsWith('download_token='));
        if (cookieEntry) {
          const val = decodeURIComponent(cookieEntry.split('=')[1] || '');
          const expected = token || (window.__downloadToken || '');
          if (!expected || val === expected) {
            // Clear cookie and stop loading
            document.cookie = 'download_token=; Max-Age=0; path=/';
            this.stopLoading();
          }
        }
        if (Date.now() > deadline) {
          // Fallback timeout
          this.stopLoading();
        }
      } catch (_) {
        // ignore
      }
    }, 500);
  },

  stopCookiePolling() {
    if (this._cookieTimer) {
      clearInterval(this._cookieTimer);
      this._cookieTimer = null;
    }
  },

  setElements() {
    this.button = this.el.querySelector('[data-role="download-button"]');
    this.label = this.el.querySelector('[data-role="download-text"]');
    this.icon = this.el.querySelector('[data-role="download-icon"]');
    this.spinner = this.el.querySelector('[data-role="download-spinner"]');
  },

  destroyed() {
    if (this._onClickCapture) {
      document.removeEventListener('pointerdown', this._onClickCapture, true);
      document.removeEventListener('click', this._onClickCapture, true);
    }
    if (this._onDownloadComplete) {
      window.removeEventListener('download:complete', this._onDownloadComplete);
    }
    this.stopCookiePolling();
  }
}

// Widget export dropdown helpers (non-LiveView toggled)
window.TrifleDownloads = window.TrifleDownloads || {};
(function (scope) {
  const HIDDEN_CLASS = 'hidden';

  const queryDropdown = (menu) => (menu ? menu.querySelector('[data-widget-dropdown]') : null);
  const queryButton = (menu) => (menu ? menu.querySelector('[data-role="download-button"]') : null);

  scope.closeWidgetMenu = function closeWidgetMenu(menu) {
    if (!menu) return;
    const dropdown = queryDropdown(menu);
    if (dropdown) {
      dropdown.classList.add(HIDDEN_CLASS);
      dropdown.setAttribute('aria-hidden', 'true');
    }
    const button = queryButton(menu);
    if (button) button.setAttribute('aria-expanded', 'false');
    menu.dataset.open = 'false';
  };

  scope.closeAllWidgetMenus = function closeAllWidgetMenus(exceptMenu) {
    document
      .querySelectorAll('[data-widget-download-menu][data-open="true"]')
      .forEach((menu) => {
        if (exceptMenu && menu === exceptMenu) return;
        scope.closeWidgetMenu(menu);
      });
  };

  scope.toggleWidgetMenu = function toggleWidgetMenu(button) {
    if (!button) return;
    const menu = button.closest('[data-widget-download-menu]');
    if (!menu) return;
    const dropdown = queryDropdown(menu);
    if (!dropdown) return;
    const isOpen = menu.dataset.open === 'true';
    if (isOpen) {
      scope.closeWidgetMenu(menu);
      return;
    }
    scope.closeAllWidgetMenus(menu);
    dropdown.classList.remove(HIDDEN_CLASS);
    dropdown.setAttribute('aria-hidden', 'false');
    menu.dataset.open = 'true';
    button.setAttribute('aria-expanded', 'true');
  };

  scope.handleWidgetExportClick = function handleWidgetExportClick(link) {
    if (!link) return;
    const menu = link.closest('[data-widget-download-menu]');
    if (menu) {
      const dropdown = queryDropdown(menu);
      if (dropdown) {
        dropdown.classList.add(HIDDEN_CLASS);
        dropdown.setAttribute('aria-hidden', 'true');
      }
      menu.dataset.open = 'false';
      const button = queryButton(menu);
      if (button) {
        button.setAttribute('aria-expanded', 'false');
      }
    }
    try {
      const url = new URL(link.getAttribute('href') || '', window.location.origin);
      if (!url.searchParams.get('download_token')) {
        const token = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
        window.__downloadToken = token;
        url.searchParams.set('download_token', token);
        link.href = url.toString();
      }
    } catch (_) {
      // ignore malformed URLs
    }
  };

  document.addEventListener('click', (event) => {
    if (event.defaultPrevented) return;
    const menu = event.target.closest('[data-widget-download-menu]');
    if (!menu) {
      scope.closeAllWidgetMenus();
    }
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      scope.closeAllWidgetMenus();
    }
  });
})(window.TrifleDownloads);

Hooks.PathAutocomplete = {
  mounted() {
    this.input = this.el.querySelector('[data-role="path-input"]');
    this.suggestionBox = this.el.querySelector('[data-role="suggestions"]');
    this.matches = [];
    this.activeIndex = -1;
    this.visible = false;
    this.suppressNextFilter = false;

    this.loadOptions();

    if (!this.input || !this.suggestionBox) return;

    this.handleInput = () => this.filterSuggestions();
    this.handleFocus = () => this.openSuggestions();
    this.handleBlur = () => {
      this._blurTimer = setTimeout(() => this.hideSuggestions(), 100);
    };
    this.handleKeydown = (event) => this.onKeydown(event);

    this.input.addEventListener('input', this.handleInput);
    this.input.addEventListener('focus', this.handleFocus);
    this.input.addEventListener('blur', this.handleBlur);
    this.input.addEventListener('keydown', this.handleKeydown);

    // Show initial matches if input already has a value
    if (document.activeElement === this.input) {
      this.filterSuggestions();
    }
  },

  updated() {
    const previous = JSON.stringify(this.options || []);
    this.loadOptions();
    if (JSON.stringify(this.options) !== previous) {
      this.filterSuggestions();
    }
  },

  destroyed() {
    if (!this.input) return;
    this.input.removeEventListener('input', this.handleInput);
    this.input.removeEventListener('focus', this.handleFocus);
    this.input.removeEventListener('blur', this.handleBlur);
    this.input.removeEventListener('keydown', this.handleKeydown);
    if (this._blurTimer) clearTimeout(this._blurTimer);
  },

  loadOptions() {
    const raw = this.el.dataset.paths || '[]';
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (_) {
      parsed = [];
    }

    if (!Array.isArray(parsed)) parsed = [];

    this.options = parsed
      .map((item) => {
        if (typeof item === 'string') {
          return { value: item, label: item };
        }

        if (item && typeof item.value === 'string') {
          return {
            value: item.value,
            label: typeof item.label === 'string' ? item.label : item.value
          };
        }

        return null;
      })
      .filter(Boolean);
  },

  filterSuggestions() {
    if (this.suppressNextFilter) {
      this.suppressNextFilter = false;
      return;
    }

    if (!this.input) return;

    const hasFocus = document.activeElement === this.input;
    if (!hasFocus) {
      this.hideSuggestions();
      return;
    }

    const query = (this.input.value || '').trim().toLowerCase();

    let candidates = this.options;
    if (query) {
      candidates = this.options.filter((item) =>
        item.value.toLowerCase().includes(query)
      );
    }

    const limited = candidates.slice(0, 15);
    if (limited.length === 0) {
      this.hideSuggestions();
      return;
    }

    this.renderSuggestions(limited);
  },

  renderSuggestions(items) {
    if (!this.suggestionBox) return;

    this.matches = items;
    this.activeIndex = -1;

    const fragment = document.createDocumentFragment();

    items.forEach((item, index) => {
      const option = document.createElement('button');
      option.type = 'button';
      option.className = 'w-full px-3 py-2 text-left text-sm leading-tight text-slate-700 hover:bg-teal-50 focus:outline-none dark:text-slate-200 dark:hover:bg-slate-700';
      option.setAttribute('role', 'option');
      option.dataset.index = index;
      option.dataset.value = item.value;
      option.innerHTML = item.label;

      option.addEventListener('mousedown', (event) => {
        event.preventDefault();
        this.selectOption(index);
      });

      fragment.appendChild(option);
    });

    this.suggestionBox.innerHTML = '';
    this.suggestionBox.appendChild(fragment);
    this.suggestionBox.classList.remove('hidden');
    this.visible = true;
  },

  openSuggestions() {
    if (this._blurTimer) clearTimeout(this._blurTimer);
    this.filterSuggestions();
  },

  hideSuggestions() {
    if (!this.suggestionBox) return;
    this.suggestionBox.classList.add('hidden');
    this.suggestionBox.innerHTML = '';
    this.visible = false;
    this.matches = [];
    this.activeIndex = -1;
  },

  onKeydown(event) {
    if (!this.visible && (event.key === 'ArrowDown' || event.key === 'ArrowUp')) {
      this.filterSuggestions();
    }

    if (!this.visible) return;

    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault();
        this.moveActive(1);
        break;
      case 'ArrowUp':
        event.preventDefault();
        this.moveActive(-1);
        break;
      case 'Enter':
        if (this.activeIndex >= 0) {
          event.preventDefault();
          this.selectOption(this.activeIndex);
        }
        break;
      case 'Escape':
        this.hideSuggestions();
        break;
      default:
        break;
    }
  },

  moveActive(delta) {
    if (this.matches.length === 0 || !this.suggestionBox) return;

    const nextIndex = (this.activeIndex + delta + this.matches.length) % this.matches.length;
    this.setActive(nextIndex);
  },

  setActive(index) {
    if (!this.suggestionBox) return;

    const buttons = Array.from(this.suggestionBox.querySelectorAll('button[data-index]'));
    buttons.forEach((btn) => {
      btn.classList.remove('bg-teal-100', 'dark:bg-slate-600');
    });

    const active = buttons[index];
    if (active) {
      active.classList.add('bg-teal-100', 'dark:bg-slate-600');
      active.scrollIntoView({ block: 'nearest' });
      this.activeIndex = index;
    }
  },

  selectOption(index) {
    const item = this.matches[index];
    if (!item || !this.input) return;

    this.input.value = item.value;
    this.suppressNextFilter = true;
    this.hideSuggestions();

    const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
    if (nativeInputValueSetter) {
      nativeInputValueSetter.call(this.input, item.value);
    }

    this.input.dispatchEvent(new Event('input', { bubbles: true }));
    this.input.dispatchEvent(new Event('change', { bubbles: true }));
  }
}

Hooks.TimeseriesPaths = {
  mounted() {
    this.widgetId = this.el.dataset.widgetId;

    this.handleClick = (event) => {
      const button = event.target.closest('[data-action]');
      if (!button) return;

      const action = button.dataset.action;
      if (!action) return;

      event.preventDefault();

      const paths = this.readPaths();

      if (action === 'add') {
        paths.push('');
      } else if (action === 'remove') {
        const index = parseInt(button.dataset.index || '-1', 10);
        if (!Number.isNaN(index)) {
          paths.splice(index, 1);
        }
        if (paths.length === 0) {
          paths.push('');
        }
      } else {
        return;
      }

      this.pushEvent('timeseries_paths_update', {
        widget_id: this.widgetId,
        paths
      });
    };

    this.el.addEventListener('click', this.handleClick);
  },

  updated() {
    this.widgetId = this.el.dataset.widgetId;
  },

  destroyed() {
    if (this.handleClick) {
      this.el.removeEventListener('click', this.handleClick);
    }
  },

  readPaths() {
    return Array.from(this.el.querySelectorAll('input[name="ts_paths[]"]')).map((input) =>
      input.value || ''
    );
  }
}

Hooks.CategoryPaths = {
  mounted() {
    this.widgetId = this.el.dataset.widgetId;
    this.inputName = this.el.dataset.pathInputName || 'cat_paths[]';
    this.eventName = this.el.dataset.eventName || 'category_paths_update';

    this.handleClick = (event) => {
      const button = event.target.closest('[data-action]');
      if (!button) return;

      const action = button.dataset.action;
      if (!action) return;

      event.preventDefault();

      const paths = this.readPaths();

      if (action === 'add') {
        paths.push('');
      } else if (action === 'remove') {
        const index = parseInt(button.dataset.index || '-1', 10);
        if (!Number.isNaN(index)) {
          paths.splice(index, 1);
        }
        if (paths.length === 0) paths.push('');
      } else {
        return;
      }

      this.pushEvent(this.eventName, {
        widget_id: this.widgetId,
        paths
      });
    };

    this.el.addEventListener('click', this.handleClick);
  },

  updated() {
    this.widgetId = this.el.dataset.widgetId;
    this.inputName = this.el.dataset.pathInputName || 'cat_paths[]';
    this.eventName = this.el.dataset.eventName || 'category_paths_update';
  },

  destroyed() {
    if (this.handleClick) {
      this.el.removeEventListener('click', this.handleClick);
    }
  },

  readPaths() {
    return Array.from(this.el.querySelectorAll(`input[name="${this.inputName}"]`)).map((input) =>
      input.value || ''
    );
  }
}


Hooks.PhantomRows = {
  mounted() {
    this.addPhantomRows();
  },
  
  updated() {
    this.addPhantomRows();
  },
  
  addPhantomRows() {
    // Remove existing phantom rows
    this.clearPhantomRows();
    
    const container = this.el;
    const scrollContainer = container.querySelector('[data-role="table-scroll"]');
    const table = scrollContainer ? scrollContainer.querySelector('[data-role="data-table"]') : null;
    if (!table || !scrollContainer) return;
    
    // Fix border width to match table width
    const borderDiv = scrollContainer.querySelector('[data-role="table-border"]');
    if (borderDiv) {
      const tableWidth = table.scrollWidth;
      borderDiv.style.width = `${tableWidth}px`;
      borderDiv.style.minWidth = '100%';
    }
    
    // Get dimensions
    const scrollRect = scrollContainer.getBoundingClientRect();
    const table2Bottom = scrollContainer.scrollTop + table.offsetHeight;
    const scrollHeight = scrollContainer.scrollHeight;
    const clientHeight = scrollContainer.clientHeight;
    
    // Calculate if we need phantom rows (table + borders is shorter than visible area)
    const borderHeight = borderDiv ? borderDiv.offsetHeight : 0;
    const totalContentHeight = table.offsetHeight + borderHeight;
    
    if (totalContentHeight < clientHeight) {
      const remainingSpace = clientHeight - totalContentHeight;
      this.createPhantomRowsElement(remainingSpace, scrollContainer);
    }
  },
  
  createPhantomRowsElement(height, scrollContainer) {
    const table = scrollContainer.querySelector('[data-role="data-table"]');
    const tableWidth = table ? table.scrollWidth : scrollContainer.scrollWidth;
    
    const phantomContainer = document.createElement('div');
    phantomContainer.className = 'phantom-rows-js';
    
    // Create horizontal stripes background
    const isDark = document.documentElement.classList.contains('dark');
    const stripeColor = isDark ? 'rgb(71 85 105)' : 'rgb(229 231 235)';
    const bgColor = isDark ? 'transparent' : 'transparent';
    
    phantomContainer.style.cssText = `
      height: ${height}px;
      width: ${tableWidth}px;
      min-width: 100%;
      background-image: repeating-linear-gradient(
        to bottom,
        ${bgColor} 0px,
        ${bgColor} 23px,
        ${stripeColor} 23px,
        ${stripeColor} 24px
      );
      pointer-events: none;
    `;
    
    // Append to scroll container, right after the border
    const borderDiv = scrollContainer.querySelector('[data-role="table-border"]');
    if (borderDiv && borderDiv.nextSibling) {
      scrollContainer.insertBefore(phantomContainer, borderDiv.nextSibling);
    } else {
      scrollContainer.appendChild(phantomContainer);
    }
  },
  
  clearPhantomRows() {
    const existing = this.el.querySelectorAll('.phantom-rows-js');
    existing.forEach(el => el.remove());
  }
}

Hooks.FastTooltip = {
  mounted() {
    this.initTooltips();
  },
  
  updated() {
    this.initTooltips();
  },
  
  initTooltips() {
    // Remove existing tooltips
    document.querySelectorAll('.fast-tooltip').forEach(el => el.remove());
    
    const tooltipElements = this.el.querySelectorAll('[data-tooltip]');
    
    tooltipElements.forEach(el => {
      el.addEventListener('mouseenter', (e) => {
        this.showTooltip(e.target, e.target.dataset.tooltip);
      });
      
      el.addEventListener('mouseleave', (e) => {
        this.hideTooltip();
      });
    });
  },
  
  showTooltip(element, text) {
    // Detect dark mode
    const isDarkMode = document.documentElement.classList.contains('dark');
    const backgroundColor = isDarkMode ? '#0f172a' : '#374151';
    const textColor = isDarkMode ? '#ffffff' : '#ffffff';
    
    // Create tooltip element
    const tooltip = document.createElement('div');
    tooltip.className = 'fast-tooltip';
    tooltip.textContent = text;
    tooltip.style.cssText = `
      position: absolute;
      background: ${backgroundColor};
      color: ${textColor};
      padding: 4px 8px;
      border-radius: 4px;
      font-size: 12px;
      z-index: 1000;
      pointer-events: none;
      white-space: nowrap;
      box-shadow: 0 1px 4px rgba(0,0,0,0.1);
    `;
    
    document.body.appendChild(tooltip);
    
    // Position tooltip
    const rect = element.getBoundingClientRect();
    const tooltipRect = tooltip.getBoundingClientRect();
    
    let left = rect.left + (rect.width / 2) - (tooltipRect.width / 2) + window.scrollX;
    let top = rect.top - tooltipRect.height - 8 + window.scrollY;
    
    // Keep tooltip within viewport
    if (left < 8) left = 8;
    if (left + tooltipRect.width > window.innerWidth - 8) {
      left = window.innerWidth - tooltipRect.width - 8;
    }
    if (top < 8 + window.scrollY) {
      top = rect.bottom + 8 + window.scrollY;
    }
    
    tooltip.style.left = left + 'px';
    tooltip.style.top = top + 'px';
  },
  
  hideTooltip() {
    document.querySelectorAll('.fast-tooltip').forEach(el => el.remove());
  }
}


let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
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

// Theme Management
class ThemeManager {
  constructor() {
    this.init();
  }

  init() {
    // Apply theme on page load
    this.applyTheme();
    
    // Listen for theme changes from LiveView
    window.addEventListener("phx:theme-changed", (event) => {
      this.applyTheme(event.detail.theme);
    });

    // Listen for system theme changes
    if (window.matchMedia) {
      const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
      mediaQuery.addEventListener('change', () => {
        // Only apply system theme change if user has system preference
        const currentTheme = document.body.getAttribute('data-theme') || 'system';
        if (currentTheme === 'system') {
          this.applyTheme();
        }
      });
    }
  }

  shouldUseDarkTheme(themePreference = null) {
    const body = document.body;
    const preload = window.__TRIFLE_THEME_PRELOAD__ || {};
    const currentTheme = themePreference || preload.pref || body.getAttribute('data-theme') || 'system';
    
    let shouldUseDark;
    switch (currentTheme) {
      case 'dark':
        shouldUseDark = true;
        break;
      case 'light':
        shouldUseDark = false;
        break;
      case 'system':
      default:
        // Check system preference
        shouldUseDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
        break;
    }
    
    return shouldUseDark;
  }

  applyTheme(themePreference = null) {
    const body = document.body;
    const preload = window.__TRIFLE_THEME_PRELOAD__ || {};
    const currentTheme = themePreference || preload.pref || body.getAttribute('data-theme') || 'system';
    const shouldUseDark = this.shouldUseDarkTheme(currentTheme);
    const resolvedTheme = shouldUseDark ? 'dark' : 'light';
    const previousTheme = this._resolvedTheme;

    // Update data-theme attribute if preference was provided
    if (themePreference) {
      body.setAttribute('data-theme', themePreference);
    } else if (body.getAttribute('data-theme') !== currentTheme) {
      body.setAttribute('data-theme', currentTheme);
    }
    
    // Remove existing theme classes
    body.classList.remove('dark');
    document.documentElement.classList.remove('dark');

    // Apply theme classes based on user preference
    if (shouldUseDark) {
      body.classList.add('dark');
      document.documentElement.classList.add('dark');
    }

    this._resolvedTheme = resolvedTheme;
    try {
      if (window.localStorage) {
        window.localStorage.setItem('trifle:theme-pref', currentTheme);
        window.localStorage.setItem('trifle:resolved-theme', resolvedTheme);
      }
    } catch (_) {}

    window.__TRIFLE_THEME_PRELOAD__ = { pref: currentTheme, resolved: resolvedTheme };
    if (previousTheme !== resolvedTheme) {
      try {
        window.dispatchEvent(new CustomEvent('trifle:theme-changed', { detail: { theme: resolvedTheme } }));
      } catch (_) {}
    }
  }

}

// Initialize theme manager when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  window.themeManager = new ThemeManager();
});
