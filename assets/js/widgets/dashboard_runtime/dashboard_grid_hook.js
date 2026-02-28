import { createDashboardGridKpiRendererMethods } from "./dashboard_grid_renderers/kpi";
import { createDashboardGridTimeseriesRendererMethods } from "./dashboard_grid_renderers/timeseries";
import { createDashboardGridCategoryRendererMethods } from "./dashboard_grid_renderers/category";
import { createDashboardGridDistributionRendererMethods } from "./dashboard_grid_renderers/distribution";
import { createDashboardGridTableRendererMethods } from "./dashboard_grid_renderers/table";
import { createDashboardGridTextRendererMethods } from "./dashboard_grid_renderers/text";
import { createDashboardGridListRendererMethods } from "./dashboard_grid_renderers/list";

export const registerDashboardGridHook = (Hooks, deps) => {
  const {
    echarts,
    GridStack,
    withChartOpts,
    formatCompactNumber,
    sanitizeRichHtml,
    resolveHeatmapVisualMap,
    buildHeatmapOptions,
    detectOngoingSegment,
    buildBucketIndexMap,
    buildDistributionHeatmapAggregation,
    buildDistributionScatterSeries,
    TABLE_PATH_HTML_FIELD,
    AGGRID_PATH_COL_MIN_WIDTH,
    AGGRID_PATH_COL_MAX_WIDTH,
    ensureAgGridCommunity,
    getAggridHeaderComponentClass,
    parseJsonSafe,
    echartsDevicePixelRatio,
    extractTimestamp
  } = deps;

  const kpiRendererMethods = createDashboardGridKpiRendererMethods({ echarts, withChartOpts });
  const timeseriesRendererMethods = createDashboardGridTimeseriesRendererMethods({
    echarts,
    withChartOpts,
    formatCompactNumber,
    detectOngoingSegment,
    extractTimestamp
  });
  const categoryRendererMethods = createDashboardGridCategoryRendererMethods({ formatCompactNumber });
  const distributionRendererMethods = createDashboardGridDistributionRendererMethods({
    buildBucketIndexMap,
    buildDistributionHeatmapAggregation,
    buildDistributionScatterSeries,
    resolveHeatmapVisualMap,
    buildHeatmapOptions,
    formatCompactNumber
  });
  const tableRendererMethods = createDashboardGridTableRendererMethods({
    Hooks,
    TABLE_PATH_HTML_FIELD,
    AGGRID_PATH_COL_MIN_WIDTH,
    AGGRID_PATH_COL_MAX_WIDTH,
    ensureAgGridCommunity,
    getAggridHeaderComponentClass
  });
  const textRendererMethods = createDashboardGridTextRendererMethods({ sanitizeRichHtml });
  const listRendererMethods = createDashboardGridListRendererMethods();

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
    this._tsSeriesData = {};
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
    this._tsSyncGroup = ['ts-sync', this.el.dataset.dashboardId || this.el.id || 'grid', this.el.dataset.publicToken || 'priv'].join(':');
    this._tsSyncPending = null;
    this._tsSyncRaf = null;
    this._tsSyncApplying = false;
    this._tsSyncConnected = false;
    this._tsHoveringId = null;
    this._tsLastValue = null;
    this._tsSyncLoop = null;
    this._tsHideTimer = null;
    this._tsPointerMove = null;
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
      const baseDpr = Number.isFinite(echartsDevicePixelRatio)
        ? echartsDevicePixelRatio
        : Math.max(1, window.devicePixelRatio || 1);
      const base = printMode ? { devicePixelRatio: Math.max(2, baseDpr) } : {};
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
    this._tsSeriesData = {};
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
    if (this._tsSyncRaf) {
      cancelAnimationFrame(this._tsSyncRaf);
      this._tsSyncRaf = null;
    }
    if (this._tsSyncLoop) {
      cancelAnimationFrame(this._tsSyncLoop);
      this._tsSyncLoop = null;
    }
    if (this._tsHideTimer) {
      clearTimeout(this._tsHideTimer);
      this._tsHideTimer = null;
    }
    if (this._tsPointerMove) {
      window.removeEventListener('pointermove', this._tsPointerMove, true);
      this._tsPointerMove = null;
    }
    this._tsSyncConnected = false;
    this._tsHoveringId = null;
    this._tsLastValue = null;
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
  ...kpiRendererMethods,
  ...timeseriesRendererMethods,
  ...categoryRendererMethods,
  ...distributionRendererMethods,
  ...tableRendererMethods,
  ...textRendererMethods,
  ...listRendererMethods,
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
        if (this._tsSeriesData) {
          delete this._tsSeriesData[normalizedId];
        }
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

    if (type === 'distribution' || type === 'heatmap') {
      const resolvedWidgetType = type === 'heatmap' ? 'heatmap' : 'distribution';
      if (payload) {
        registry.distribution[normalizedId] = Object.assign({}, payload, {
          id: payload.id || normalizedId,
          widget_type: payload.widget_type || resolvedWidgetType
        });
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
};
