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
  const categoryRendererMethods = createDashboardGridCategoryRendererMethods({
    echarts,
    withChartOpts,
    formatCompactNumber
  });
  const distributionRendererMethods = createDashboardGridDistributionRendererMethods({
    echarts,
    withChartOpts,
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
    getAggridHeaderComponentClass,
    sanitizeRichHtml
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

    this._observedLayoutTargets = new WeakSet();
    this._observedLayoutResizeRaf = null;
    this._layoutResizeObserver = typeof ResizeObserver === 'function'
      ? new ResizeObserver(() => {
        this._scheduleObservedLayoutResize();
      })
      : null;

    // Global window resize handler to resize all charts
    this._onWindowResize = () => {
      try {
        // Apply responsive column toggle if available
        if (typeof this._applyResponsiveGrid === 'function') {
          this._applyResponsiveGrid();
        }
        this._scheduleDeferredResize();
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
          this._scheduleDeferredResize();
        } catch (_) {}
      });
    };
    window.addEventListener('phx:page-loading-stop', this._onPageLoadingStop);
    this._sparkTimers = {};
    this._tsSyncGroupBase = ['ts-sync', this.el.dataset.dashboardId || this.el.id || 'grid', this.el.dataset.publicToken || 'priv'].join(':');
    this._tsConnectedGroups = new Set();
    this._tsSyncPending = null;
    this._tsSyncRaf = null;
    this._tsSyncApplying = false;
    this._tsHoveringId = null;
    this._tsHoveringGroup = null;
    this._tsLastValue = null;
    this._tsSyncLoop = null;
    this._tsHideTimer = null;
    this._tsPointerMove = null;
    this._deferredResizeRaf = null;
    this._deferredResizeRaf2 = null;
    this._deferredResizeTimers = [];
    const editableAttr = this.el.dataset.editable;
    this.editable = (editableAttr === 'true' || editableAttr === '' || editableAttr === '1');
    this.cols = parseInt(this.el.dataset.cols || '12', 10);
    this.minRows = parseInt(this.el.dataset.minRows || '8', 10);
    this.addBtnId = this.el.dataset.addBtnId;
    this.addGroupBtnId = this.el.dataset.addGroupBtnId;
    try {
      this.initialItems = this.el.dataset.initialGrid ? JSON.parse(this.el.dataset.initialGrid) : [];
    } catch (_) {
      this.initialItems = [];
    }
    this._childGrids = {};
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
    this._preferServerRenderedWidgets = false;
    this._preferServerRenderedWidgetsTimer = null;

    // Determine renderer/devicePixelRatio for charts (SVG for print exports for crisp output)
    const printMode = (this.el.dataset.printMode === 'true' || this.el.dataset.printMode === '');
    this._chartInitOpts = (extra = {}) => {
      const baseDpr = Number.isFinite(echartsDevicePixelRatio)
        ? echartsDevicePixelRatio
        : Math.max(1, window.devicePixelRatio || 1);
      const base = printMode ? { devicePixelRatio: Math.max(2, baseDpr) } : {};
      return withChartOpts(Object.assign({}, base, extra));
    };

    this._enableServerRenderedWidgetPreference();
    this.initGrid();
    this.syncServerRenderedItems();
    this._scheduleServerRenderedWidgetPreferenceClear();

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
      if (printMode) return;
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
          this._ensureGroupGrids();
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
            Object.values(this._childGrids || {}).forEach((grid) => {
              if (!grid) return;
              if (typeof grid.enableMove === 'function') {
                grid.enableMove(!oneCol);
                if (typeof grid.enableResize === 'function') {
                  grid.enableResize(!oneCol);
                }
              } else if (typeof grid.setStatic === 'function') {
                grid.setStatic(oneCol);
              }
            });
          }
        } catch (_) {
          // noop
        } finally {
          this._observeLayoutResizeTargets();
          this._scheduleDeferredResize();
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
    if ((this.initialKpiValues && this.initialKpiValues.length) || (this.initialKpiVisual && this.initialKpiVisual.length) || (this.initialTimeseries && this.initialTimeseries.length) || (this.initialCategory && this.initialCategory.length)) {
      setTimeout(() => {
        try {
          if (this.initialKpiValues && this.initialKpiValues.length) this._render_kpi_values(this.initialKpiValues);
          if (this.initialKpiVisual && this.initialKpiVisual.length) this._render_kpi_visuals(this.initialKpiVisual);
          if (this.initialTimeseries && this.initialTimeseries.length) this._render_timeseries(this.initialTimeseries);
          if (this.initialCategory && this.initialCategory.length) this._render_category(this.initialCategory);
        } catch (e) { console.error('initial print render failed', e); }
      }, 0);
    }

    // Ready signaling for export capture
    this._seen = { kpi_values: false, kpi_visual: false, timeseries: false, category: false, text: false, table: false, list: false, distribution: false };
    this._markedReady = false;
    this._markServerRenderedWidgetsReady();

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
          return;
        }
        const groupBtn = this.addGroupBtnId && e.target && (e.target.id === this.addGroupBtnId ? e.target : e.target.closest && e.target.closest(`#${this.addGroupBtnId}`));
        if (groupBtn) {
          e.preventDefault();
          this.addNewGroup();
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
      const duplicateBtn = e.target && (e.target.closest && e.target.closest('.grid-widget-duplicate'));
      if (duplicateBtn) {
        e.preventDefault();
        const id = duplicateBtn.getAttribute('data-widget-id');
        if (id) this.pushEvent('duplicate_widget', { id });
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
        const rawNodes = Array.from(
          document.querySelectorAll('.ts-chart, .cat-chart, .kpi-visual, .distribution-chart')
        );
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
          return this._seen.timeseries ||
            this._seen.category ||
            this._seen.table ||
            this._seen.text ||
            this._seen.list ||
            this._seen.distribution ||
            (this._seen.kpi_values && this._seen.kpi_visual);
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
    this.handleEvent('dashboard_grid_widget_updated', ({ id, title, type }) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${id}"]`);
      const content = item && item.querySelector('.grid-stack-item-content');
      const titleEl = item && item.querySelector('.grid-widget-title');
      const widgetType = type ? String(type).toLowerCase() : ((content && content.dataset && content.dataset.widgetType) || '');
      const isTextWidget = widgetType === 'text';
      const isListWidget = widgetType === 'list';

      // The dashboard grid root uses phx-update="ignore", so widget shell metadata
      // must be updated manually after saves or the next layout sync can serialize
      // stale widget types/titles back to the server.
      if (content && content.dataset) {
        if (widgetType) {
          content.dataset.widgetType = widgetType;
        }

        if (isTextWidget) {
          content.dataset.textWidget = '1';
        } else {
          delete content.dataset.textWidget;
        }

        if (isListWidget) {
          content.dataset.listWidget = '1';
        } else {
          delete content.dataset.listWidget;
        }
      }

      if (titleEl) {
        if (isTextWidget) {
          const rawTitle = title || '';
          if (content && content.dataset) {
            content.dataset.widgetTitle = rawTitle;
          }
          titleEl.dataset.originalTitle = rawTitle;
          titleEl.textContent = '';
          titleEl.setAttribute('aria-hidden', 'true');
          titleEl.setAttribute('role', 'presentation');
          titleEl.style.opacity = '0';
          titleEl.style.pointerEvents = 'none';
        } else {
          if (content && content.dataset) delete content.dataset.widgetTitle;
          titleEl.dataset.originalTitle = title || '';
          titleEl.removeAttribute('aria-hidden');
          titleEl.removeAttribute('role');
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
      const isGroup = item && this._isGroupItem(item);
      if (item && isGroup) {
        this._moveGroupChildrenToRoot(item);
      }
      if (item) {
        const content = item.querySelector('.grid-stack-item-content');
        const type = content && content.dataset && content.dataset.widgetType;
        this._removeGridItem(item);
        this.unregisterWidget(type || null, id);
        this.saveLayout();
      } else {
        this.unregisterWidget(null, id);
      }
    });
    this.handleEvent('dashboard_grid_widget_duplicated', ({ item }) => {
      this._insertDuplicatedWidget(item);
    });

  },

  updated() {
    this._enableServerRenderedWidgetPreference();
    this._ensureGroupGrids();
    this.syncServerRenderedItems();
    this._markServerRenderedWidgetsReady();
    this._scheduleServerRenderedWidgetPreferenceClear();
    this._observeLayoutResizeTargets();
    this._scheduleDeferredResize();
  },

  destroyed() {
    if (this.el) {
      this.el.classList.remove('opacity-100');
      this.el.classList.add('opacity-0', 'pointer-events-none');
    }

    if (this.el && this.el.__dashboardGrid === this) {
      delete this.el.__dashboardGrid;
    }
    if (this._preferServerRenderedWidgetsTimer) {
      clearTimeout(this._preferServerRenderedWidgetsTimer);
      this._preferServerRenderedWidgetsTimer = null;
    }
    this._widgetRegistry = null;
    Object.values(this._childGrids || {}).forEach((grid) => {
      if (grid && typeof grid.destroy === 'function') {
        try { grid.destroy(false); } catch (_) {}
      }
    });
    this._childGrids = {};
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
    if (this._observedLayoutResizeRaf) {
      cancelAnimationFrame(this._observedLayoutResizeRaf);
      this._observedLayoutResizeRaf = null;
    }
    if (this._layoutResizeObserver) {
      try { this._layoutResizeObserver.disconnect(); } catch (_) {}
      this._layoutResizeObserver = null;
    }
    this._cancelDeferredResize();
    this._tsHoveringId = null;
    this._tsHoveringGroup = null;
    this._tsLastValue = null;
    if (this._tsConnectedGroups && typeof echarts.disconnect === 'function') {
      this._tsConnectedGroups.forEach((groupKey) => {
        try { echarts.disconnect(groupKey); } catch (_) {}
      });
      this._tsConnectedGroups.clear();
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

    this._cellHeight = resolvedCellHeight;
    this._nestedCellHeight = Math.max(60, resolvedCellHeight);

    this.grid = GridStack.init(this._gridOptions(false), this.el);
    this._cellHeight = resolvedCellHeight;

    if (!this.editable) {
      this.grid.setStatic(true);
    }

    this._bindGridEvents(this.grid);
    this._ensureGroupGrids();
    this._observeLayoutResizeTargets();

    // No direct button binding needed; delegated handler set in mounted
  },
  _gridOptions(nested = false, groupItem = null) {
    const metrics = nested ? this._groupGridMetrics(groupItem) : null;
    const base = {
      column: nested ? metrics.cols : 12,
      minRow: nested ? metrics.rows : this.minRows,
      float: true,
      margin: 5,
      disableOneColumnMode: true,
      styleInHead: true,
      cellHeight: nested ? metrics.cellHeight : this._cellHeight,
      draggable: { appendTo: 'body', scroll: true },
      handleClass: nested ? 'nested-grid-widget-handle' : 'root-grid-widget-handle',
    };
    if (!nested) {
      base.column = this.cols;
      base.acceptWidgets = !!this.editable;
      return base;
    }
    base.maxRow = metrics.rows;
    base.dragOut = !!this.editable;
    if (!this.editable) {
      base.acceptWidgets = false;
      return base;
    }
    base.acceptWidgets = (el) => this._dragItemKind(el) !== 'group';
    return base;
  },

  _bindGridEvents(grid) {
    if (!grid || grid.__dashboardGridBound) return;
    const save = () => this.saveLayout();
    const resize = () => {
      if (this._activeGroupResizeId) return;
      this._resizeAllCharts();
    };
    const syncGroupState = () => {
      this._syncGridHandleClasses(grid);
      const owner = grid.el && grid.el.closest ? grid.el.closest('.grid-stack-item[data-item-kind="group"]') : null;
      if (grid === this.grid) {
        this._ensureGroupGrids();
        this._syncTimeseriesHoverGroups();
        return;
      }
      if (owner) {
        this._syncGroupGridGeometry(owner, grid);
        this._updateGroupEmptyHint(owner);
      }
      this._syncTimeseriesHoverGroups();
      requestAnimationFrame(() => this._refreshAllGroupHints());
    };
    grid.on('resizestart', (_event, el) => {
      if (grid !== this.grid || !el || !this._isGroupItem(el)) return;
      this._cancelDeferredResize();
      this._activeGroupResizeId = el.getAttribute('gs-id') || null;
      this._freezeGroupGeometry(el);
    });
    grid.on('resizestop', (_event, el) => {
      if (grid !== this.grid || !el || !this._isGroupItem(el)) return;
      const id = el.getAttribute('gs-id') || null;
      this._unfreezeGroupGeometry(el);
      if (this._activeGroupResizeId === id) {
        this._activeGroupResizeId = null;
      }
      this._syncGroupGridGeometry(el);
      this._updateGroupEmptyHint(el);
      requestAnimationFrame(() => this._refreshAllGroupHints());
      this._scheduleDeferredResize();
    });
    grid.on('change', () => {
      syncGroupState();
      if (!this._suppressSave && !this._isOneCol && document.visibilityState !== 'hidden') save();
      resize();
    });
    grid.on('added', () => {
      syncGroupState();
      if (!this._isOneCol) save();
      resize();
    });
    grid.on('removed', () => {
      this._pruneStaleGroupGrids();
      syncGroupState();
      if (!this._isOneCol) save();
      resize();
    });
    grid.__dashboardGridBound = true;
  },

  _resizeAllCharts() {
    if (this._sparklines) {
      Object.values(this._sparklines).forEach((c) => {
        this._resizeChartInstance(c);
      });
    }
    if (this._tsCharts) {
      Object.values(this._tsCharts).forEach((c) => {
        this._resizeChartInstance(c);
      });
    }
    if (this._catCharts) {
      Object.values(this._catCharts).forEach((c) => {
        this._resizeChartInstance(c);
      });
    }
    if (this._distCharts) {
      Object.values(this._distCharts).forEach((c) => {
        this._resizeChartInstance(c);
      });
    }
    this._resizeAgGridTables();
  },

  _resizeChartInstance(chart) {
    if (!chart || (typeof chart.isDisposed === 'function' && chart.isDisposed())) return;
    try {
      const dom = typeof chart.getDom === 'function' ? chart.getDom() : null;
      if (!dom) {
        chart.resize();
        return;
      }
      const rect = typeof dom.getBoundingClientRect === 'function' ? dom.getBoundingClientRect() : null;
      const width = Math.max(0, Math.round((rect && rect.width) || dom.clientWidth || 0));
      const height = Math.max(0, Math.round((rect && rect.height) || dom.clientHeight || 0));
      if (width > 0 && height > 0) {
        chart.resize({ width, height });
      } else {
        chart.resize();
      }
    } catch (_) {}
  },

  _scheduleObservedLayoutResize() {
    if (this._observedLayoutResizeRaf) return;
    this._observedLayoutResizeRaf = requestAnimationFrame(() => {
      this._observedLayoutResizeRaf = null;
      this._scheduleDeferredResize();
    });
  },

  _observeLayoutResizeTarget(target) {
    if (!target || !this._layoutResizeObserver || !this._observedLayoutTargets) return;
    if (this._observedLayoutTargets.has(target)) return;
    try {
      this._layoutResizeObserver.observe(target);
      this._observedLayoutTargets.add(target);
    } catch (_) {}
  },

  _observeLayoutResizeTargets() {
    if (!this.el || !this._layoutResizeObserver) return;
    const selectors = [
      '.grid-stack-item-content[data-item-kind="widget"]',
      '.grid-stack-item-content[data-item-kind="group"]',
      '[data-role="aggrid-table-root"]'
    ];
    selectors.forEach((selector) => {
      this.el.querySelectorAll(selector).forEach((target) => this._observeLayoutResizeTarget(target));
    });
  },

  _cancelDeferredResize() {
    if (this._deferredResizeRaf) {
      cancelAnimationFrame(this._deferredResizeRaf);
      this._deferredResizeRaf = null;
    }
    if (this._deferredResizeRaf2) {
      cancelAnimationFrame(this._deferredResizeRaf2);
      this._deferredResizeRaf2 = null;
    }
    if (Array.isArray(this._deferredResizeTimers)) {
      this._deferredResizeTimers.forEach((timer) => {
        try { clearTimeout(timer); } catch (_) {}
      });
      this._deferredResizeTimers = [];
    }
  },

  _scheduleDeferredResize() {
    this._cancelDeferredResize();
    this._deferredResizeRaf = requestAnimationFrame(() => {
      this._deferredResizeRaf = null;
      this._deferredResizeRaf2 = requestAnimationFrame(() => {
        this._deferredResizeRaf2 = null;
        this._resizeAllCharts();
      });
    });
    [120, 260, 420].forEach((delay) => {
      const timer = setTimeout(() => {
        this._resizeAllCharts();
      }, delay);
      this._deferredResizeTimers.push(timer);
    });
  },

  _gridItems(grid) {
    if (!grid || typeof grid.getGridItems !== 'function') return [];
    try {
      return grid.getGridItems() || [];
    } catch (_) {
      return [];
    }
  },

  _isGroupItem(el) {
    if (!el || !el.getAttribute) return false;
    return this._dragItemKind(el) === 'group';
  },

  _dragItemKind(el) {
    if (!el || !el.getAttribute) return 'widget';
    return el.getAttribute('data-item-kind') || 'widget';
  },

  _groupGridElement(groupItem) {
    if (!groupItem || !groupItem.querySelector) return null;
    return groupItem.querySelector('.grid-stack[data-group-grid="1"]');
  },

  _tsSyncScopeForItem(item) {
    const groupGrid = item && item.closest ? item.closest('.grid-stack[data-group-grid="1"]') : null;
    const groupId = groupGrid && groupGrid.dataset ? groupGrid.dataset.groupId : null;
    return groupId ? `group:${groupId}` : 'root';
  },

  _tsSyncGroupForWidget(widgetId) {
    const safeId = widgetId == null ? '' : String(widgetId);
    const item = safeId && this.el
      ? this.el.querySelector(`.grid-stack-item[gs-id="${safeId}"]`)
      : null;
    return `${this._tsSyncGroupBase}:${this._tsSyncScopeForItem(item)}`;
  },

  _registerTsSyncGroup(syncGroup) {
    if (!syncGroup || !echarts || typeof echarts.connect !== 'function') return;
    if (!this._tsConnectedGroups) {
      this._tsConnectedGroups = new Set();
    }
    if (this._tsConnectedGroups.has(syncGroup)) return;
    try {
      echarts.connect(syncGroup);
      this._tsConnectedGroups.add(syncGroup);
    } catch (_) {}
  },

  _tsChartsForGroup(syncGroup) {
    if (!syncGroup || !this._tsCharts) return [];
    return Object.entries(this._tsCharts)
      .filter(([, chart]) => chart && !(chart.isDisposed && chart.isDisposed()) && chart.__tsSyncGroup === syncGroup);
  },

  _syncTimeseriesHoverGroups() {
    if (!this._tsCharts) return;
    Object.entries(this._tsCharts).forEach(([widgetId, chart]) => {
      if (!chart || (chart.isDisposed && chart.isDisposed())) return;
      const syncGroup = this._tsSyncGroupForWidget(widgetId);
      chart.__tsWidgetId = String(widgetId);
      chart.__tsSyncGroup = syncGroup;
      if (chart.group !== syncGroup) {
        chart.group = syncGroup;
      }
      this._registerTsSyncGroup(syncGroup);
    });
  },

  _syncItemHandleClass(item, nested = false) {
    if (!item || !item.querySelector) return;
    if ((item.getAttribute && item.getAttribute('data-item-kind')) === 'group') return;
    const handle = item.querySelector('.grid-widget-handle');
    if (!handle) return;
    handle.classList.remove('root-grid-widget-handle', 'nested-grid-widget-handle');
    handle.classList.add(nested ? 'nested-grid-widget-handle' : 'root-grid-widget-handle');
  },

  _syncGridHandleClasses(grid) {
    if (!grid) return;
    const nested = !!(grid.el && grid.el.dataset && grid.el.dataset.groupGrid === '1');
    this._gridItems(grid).forEach((item) => this._syncItemHandleClass(item, nested));
  },

  _groupGridShell(groupItem) {
    if (!groupItem || !groupItem.querySelector) return null;
    return groupItem.querySelector('[data-group-grid-shell="1"]');
  },

  _groupColumnCount(groupItem) {
    if (this._isOneCol) return 1;
    const value = parseInt(
      (groupItem && groupItem.getAttribute && groupItem.getAttribute('gs-w')) ||
      (groupItem && groupItem.gridstackNode && groupItem.gridstackNode.w) ||
      '1',
      10
    );
    return Math.max(1, value || 1);
  },

  _groupRowCount(groupItem) {
    const value = parseInt(
      (groupItem && groupItem.getAttribute && groupItem.getAttribute('gs-h')) ||
      (groupItem && groupItem.gridstackNode && groupItem.gridstackNode.h) ||
      '1',
      10
    );
    return Math.max(1, value || 1);
  },

  _groupGridMetrics(groupItem) {
    const rows = this._groupRowCount(groupItem);
    const cols = this._groupColumnCount(groupItem);
    const shell = this._groupGridShell(groupItem);
    const margin = 5;
    const availableHeight = Math.max(
      48,
      shell && shell.clientHeight ? shell.clientHeight : rows * this._nestedCellHeight
    );
    const cellHeight = Math.max(24, Math.floor((availableHeight - Math.max(0, rows - 1) * margin) / rows));
    const height = rows * cellHeight + Math.max(0, rows - 1) * margin;

    return { cols, rows, cellHeight, height };
  },

  _freezeGroupGeometry(groupItem) {
    const nestedEl = this._groupGridElement(groupItem);
    const shell = this._groupGridShell(groupItem);
    if (!nestedEl) return;

    const width = nestedEl.getBoundingClientRect ? nestedEl.getBoundingClientRect().width : nestedEl.clientWidth;
    const height = nestedEl.getBoundingClientRect ? nestedEl.getBoundingClientRect().height : nestedEl.clientHeight;

    nestedEl.style.width = `${Math.max(0, Math.round(width))}px`;
    nestedEl.style.minWidth = `${Math.max(0, Math.round(width))}px`;
    nestedEl.style.maxWidth = `${Math.max(0, Math.round(width))}px`;
    nestedEl.style.height = `${Math.max(0, Math.round(height))}px`;
    nestedEl.style.minHeight = `${Math.max(0, Math.round(height))}px`;

    if (shell) {
      shell.style.overflow = 'hidden';
    }
  },

  _unfreezeGroupGeometry(groupItem) {
    const nestedEl = this._groupGridElement(groupItem);
    const shell = this._groupGridShell(groupItem);
    if (!nestedEl) return;

    nestedEl.style.removeProperty('width');
    nestedEl.style.removeProperty('min-width');
    nestedEl.style.removeProperty('max-width');
    nestedEl.style.removeProperty('height');
    nestedEl.style.removeProperty('min-height');

    if (shell) {
      shell.style.removeProperty('overflow');
    }
  },

  _groupContentBounds(groupItem, grid = null) {
    const groupId = groupItem && groupItem.getAttribute ? groupItem.getAttribute('gs-id') : null;
    const nestedGrid = grid || (groupId && this._childGrids[groupId]) || null;
    const items = this._gridItems(nestedGrid);

    return items.reduce((acc, item) => {
      const x = parseInt(item.getAttribute('gs-x') || '0', 10);
      const y = parseInt(item.getAttribute('gs-y') || '0', 10);
      const w = parseInt(item.getAttribute('gs-w') || '1', 10);
      const h = parseInt(item.getAttribute('gs-h') || '1', 10);

      return {
        minW: Math.max(acc.minW, x + w),
        minH: Math.max(acc.minH, y + h)
      };
    }, { minW: 1, minH: 1 });
  },

  _syncGroupConstraints(groupItem, grid = null) {
    if (!groupItem) return;
    const rootGrid = (groupItem.parentElement && groupItem.parentElement.gridstack) || this.grid;
    const node = groupItem.gridstackNode;
    if (!rootGrid || !node) return;

    const bounds = this._groupContentBounds(groupItem, grid);
    node.minW = bounds.minW;
    node.minH = bounds.minH;
    groupItem.setAttribute('gs-min-w', String(bounds.minW));
    groupItem.setAttribute('gs-min-h', String(bounds.minH));

    if (typeof rootGrid._prepareDragDropByNode === 'function') {
      try { rootGrid._prepareDragDropByNode(node); } catch (_) {}
    }
  },

  _syncGroupGridGeometry(groupItem, grid = null) {
    const groupId = groupItem && groupItem.getAttribute ? groupItem.getAttribute('gs-id') : null;
    const nestedGrid = grid || (groupId && this._childGrids[groupId]) || null;
    const nestedEl = this._groupGridElement(groupItem);
    if (!nestedGrid || !nestedEl) return;
    if (groupId && this._activeGroupResizeId === groupId) return;

    const metrics = this._groupGridMetrics(groupItem);

    if (typeof nestedGrid.column === 'function' && nestedGrid.getColumn && nestedGrid.getColumn() !== metrics.cols) {
      try { nestedGrid.column(metrics.cols, 'none'); } catch (_) {}
    }

    nestedGrid.opts.minRow = metrics.rows;
    nestedGrid.opts.maxRow = metrics.rows;
    if (nestedGrid.engine) {
      nestedGrid.engine.maxRow = metrics.rows;
    }

    if (typeof nestedGrid.cellHeight === 'function') {
      try { nestedGrid.cellHeight(metrics.cellHeight); } catch (_) {}
    }

    nestedEl.style.height = `${metrics.height}px`;
    nestedEl.style.minHeight = `${metrics.height}px`;
    nestedEl.setAttribute('gs-min-row', String(metrics.rows));
    nestedEl.setAttribute('gs-max-row', String(metrics.rows));

    if (typeof nestedGrid._updateContainerHeight === 'function') {
      try { nestedGrid._updateContainerHeight(); } catch (_) {}
    }

    this._syncGroupConstraints(groupItem, nestedGrid);
  },

  _ensureGroupGrids() {
    if (!this.grid) return;
    const seen = {};
    this._gridItems(this.grid).forEach((item) => {
      if (!this._isGroupItem(item)) return;
      const id = item.getAttribute('gs-id');
      if (!id) return;
      seen[id] = true;
      this._initGroupGrid(item);
    });
    this._pruneStaleGroupGrids(seen);
    this._refreshAllGroupHints();
    this._observeLayoutResizeTargets();
    this._syncTimeseriesHoverGroups();
  },

  _refreshAllGroupHints() {
    if (!this.grid) return;
    this._gridItems(this.grid).forEach((item) => {
      if (this._isGroupItem(item)) {
        this._updateGroupEmptyHint(item);
      }
    });
  },

  _pruneStaleGroupGrids(seen = null) {
    Object.keys(this._childGrids || {}).forEach((id) => {
      if (seen && seen[id]) return;
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${id}"][data-item-kind="group"]`);
      if (item) return;
      const grid = this._childGrids[id];
      if (grid && typeof grid.destroy === 'function') {
        try { grid.destroy(false); } catch (_) {}
      }
      delete this._childGrids[id];
    });
  },

  _initGroupGrid(groupItem) {
    const groupId = groupItem && groupItem.getAttribute ? groupItem.getAttribute('gs-id') : null;
    if (!groupId) return null;
    const nestedEl = this._groupGridElement(groupItem);
    if (!nestedEl) return null;
    let grid = nestedEl.gridstack || this._childGrids[groupId] || null;
    if (!grid) {
      grid = GridStack.init(this._gridOptions(true, groupItem), nestedEl);
      if (!this.editable && grid && typeof grid.setStatic === 'function') {
        grid.setStatic(true);
      }
      this._bindGridEvents(grid);
    }
    this._childGrids[groupId] = grid;
    this._syncGroupGridGeometry(groupItem, grid);
    this._syncGridWidgets(grid);
    this._syncGroupGridGeometry(groupItem, grid);
    this._updateGroupEmptyHint(groupItem);
    return grid;
  },

  _updateGroupEmptyHint(groupItem) {
    if (!groupItem || !groupItem.querySelector) return;
    const hint = groupItem.querySelector('[data-group-empty-hint="1"]');
    if (!hint) return;
    const nested = this._groupGridElement(groupItem);
    const grid = (nested && nested.gridstack) || null;
    const hasChildren = grid ? this._gridItems(grid).length > 0 : !!(nested && nested.querySelector('.grid-stack-item'));
    hint.classList.toggle('hidden', hasChildren);
  },

  _insertDuplicatedWidget(item) {
    if (!item || !item.id || item.type === 'group' || !this.grid) return;
    const existing = this.el.querySelector(`.grid-stack-item[gs-id="${item.id}"]`);
    if (existing) return;

    this._suppressSave = true;
    try {
      const el = this.grid.addWidget({
        x: item.x || 0,
        y: item.y || this._rootBottom(),
        w: item.w || 3,
        h: item.h || 2,
        id: item.id,
        content: ''
      });

      if (el) {
        el.setAttribute('data-item-kind', 'widget');
        const contentEl = el.querySelector('.grid-stack-item-content');
        if (contentEl) {
          contentEl.outerHTML = this._newWidgetContent(item, false);
        }
      }

      this._syncGridWidgets(this.grid);
      this._observeLayoutResizeTargets();

      const payload = this._widgetPayloadFromRegistry(item.type, item.id);
      if (payload !== undefined) {
        this.registerWidget(item.type || null, item.id, payload);
      }
    } finally {
      this._suppressSave = false;
    }

    this._scheduleDeferredResize();
  },

  _syncGridWidgets(grid) {
    if (!grid) return;
    this._syncGridHandleClasses(grid);
    const nodes = this._gridItems(grid);
    nodes.forEach((node) => {
      if (!node.gridstackNode) {
        try { grid.makeWidget(node); } catch (_) {}
      }
    });
    if (typeof grid.batchUpdate === 'function') {
      grid.batchUpdate();
    }
    nodes.forEach((node) => {
      if (!node.gridstackNode) {
        try { grid.makeWidget(node); } catch (_) {}
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
        grid.update(gsNode, target);
      } catch (_) {}
    });
    if (typeof grid.commit === 'function') {
      try { grid.commit(); } catch (_) {}
    }
    this._observeLayoutResizeTargets();
  },
  ...kpiRendererMethods,
  ...timeseriesRendererMethods,
  ...categoryRendererMethods,
  ...distributionRendererMethods,
  ...tableRendererMethods,
  ...textRendererMethods,
  ...listRendererMethods,
  addGridItemEl(item) {
    if (item && item.type === 'group') {
      this._appendGroupElement(this.el, item);
      return;
    }
    this._appendWidgetElement(this.el, item);
  },

  _appendWidgetElement(container, item) {
    const nested = !!(container && container.dataset && container.dataset.groupGrid === '1');
    const el = document.createElement('div');
    el.className = 'grid-stack-item';
    el.setAttribute('gs-w', item.w || 3);
    el.setAttribute('gs-h', item.h || 2);
    el.setAttribute('gs-x', item.x || 0);
    el.setAttribute('gs-y', item.y || 0);
    el.setAttribute('gs-id', item.id || (item.id = this.genId()));
    el.setAttribute('data-item-kind', 'widget');
    el.innerHTML = this._newWidgetContent(item, nested);
    container.appendChild(el);
  },

  _appendGroupElement(container, item) {
    const el = document.createElement('div');
    el.className = 'grid-stack-item';
    el.setAttribute('gs-w', item.w || 6);
    el.setAttribute('gs-h', item.h || 4);
    el.setAttribute('gs-x', item.x || 0);
    el.setAttribute('gs-y', item.y || 0);
    el.setAttribute('gs-id', item.id || (item.id = this.genId()));
    el.setAttribute('data-item-kind', 'group');
    el.innerHTML = this._newGroupContent(item);
    container.appendChild(el);
    const nested = this._groupGridElement(el);
    const children = Array.isArray(item && item.children) ? item.children : [];
    if (nested) {
      children.forEach((child) => this._appendWidgetElement(nested, child));
    }
  },

  _newWidgetContent(item, nested = false) {
    const titleText = item.title || `Widget ${String(item.id || '').slice(0, 6)}`;
    const widgetId = item.id || '';
    const widgetType = (item && item.type ? String(item.type).toLowerCase() : 'kpi') || 'kpi';
    const handleClass = nested ? 'nested-grid-widget-handle' : 'root-grid-widget-handle';
    const safeWidgetId = this.escapeHtml(widgetId);
    const duplicateBtn = this.editable ? `
      <button type=\"button\" class=\"grid-widget-duplicate inline-flex items-center p-1 rounded group\" data-widget-id=\"${safeWidgetId}\" title=\"Duplicate widget\">
        <svg xmlns=\"http://www.w3.org/2000/svg\" fill=\"none\" viewBox=\"0 0 24 24\" stroke-width=\"1.5\" stroke=\"currentColor\" class=\"h-4 w-4 text-gray-600 dark:text-slate-300 transition-colors group-hover:text-gray-800 dark:group-hover:text-slate-100\">
          <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M15.75 17.25v3.375c0 .621-.504 1.125-1.125 1.125h-9.75a1.125 1.125 0 0 1-1.125-1.125V7.875c0-.621.504-1.125 1.125-1.125H6.75a9.06 9.06 0 0 1 1.5.124m7.5 10.376h3.375c.621 0 1.125-.504 1.125-1.125V11.25c0-4.46-3.243-8.161-7.5-8.876a9.06 9.06 0 0 0-1.5-.124H9.375c-.621 0-1.125.504-1.125 1.125v3.5m7.5 10.375H9.375a1.125 1.125 0 0 1-1.125-1.125v-9.25m12 6.625v-1.875a3.375 3.375 0 0 0-3.375-3.375h-1.5a1.125 1.125 0 0 1-1.125-1.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H9.75\" />
        </svg>
      </button>` : '';
    const editBtn = this.editable ? `
      <button type=\"button\" class=\"grid-widget-edit inline-flex items-center p-1 rounded group\" data-widget-id=\"${safeWidgetId}\" title=\"Edit widget\">
        <svg xmlns=\"http://www.w3.org/2000/svg\" fill=\"none\" viewBox=\"0 0 24 24\" stroke-width=\"1.5\" stroke=\"currentColor\" class=\"h-4 w-4 text-gray-600 dark:text-slate-300 transition-colors group-hover:text-gray-800 dark:group-hover:text-slate-100\">
          <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z\" />
          <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M15 12a3 3 0 11-6 0 3 3 0 016 0z\" />
        </svg>
      </button>` : '';
    return `
      <div class=\"grid-stack-item-content bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-md shadow text-gray-700 dark:text-slate-300 flex flex-col group\" data-widget-id=\"${safeWidgetId}\" data-widget-type=\"${this.escapeHtml(widgetType)}\" data-item-kind=\"widget\" data-widget-title=\"${this.escapeHtml(titleText)}\">
        <div class=\"grid-widget-header flex items-center justify-between pt-2 px-3 mb-2 pb-1 border-b border-gray-100 dark:border-slate-700/60\">
          <div class=\"grid-widget-handle ${handleClass} cursor-move flex-1 flex items-center gap-2 py-1 min-w-0\"><div class=\"grid-widget-title font-semibold truncate text-gray-900 dark:text-white\" data-original-title=\"${this.escapeHtml(titleText)}\">${this.escapeHtml(titleText)}</div></div>
          <div class=\"grid-widget-actions flex items-center gap-1 opacity-0 transition-opacity duration-150 group-hover:opacity-100 group-focus-within:opacity-100\">
            <button type=\"button\" class=\"grid-widget-expand inline-flex items-center p-1 rounded group\" data-widget-id=\"${safeWidgetId}\" title=\"Expand widget\">
              <svg xmlns=\"http://www.w3.org/2000/svg\" fill=\"none\" viewBox=\"0 0 24 24\" stroke-width=\"1.5\" stroke=\"currentColor\" class=\"h-4 w-4 text-gray-600 dark:text-slate-300 transition-colors group-hover:text-gray-800 dark:group-hover:text-slate-100\">
                <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15\" />
              </svg>
            </button>
            ${duplicateBtn}
            ${editBtn}
          </div>
        </div>
        <div class=\"grid-widget-body flex-1 flex items-center justify-center text-sm text-gray-500 dark:text-slate-400\">
          Chart is coming soon
        </div>
      </div>`;
  },

  _newGroupContent(item) {
    const titleText = item.title || 'Widget Group';
    const groupId = item.id || '';
    const safeGroupId = this.escapeHtml(groupId);
    const editBtn = this.editable ? `
      <button type=\"button\" class=\"grid-widget-edit inline-flex items-center p-1 rounded group\" data-widget-id=\"${safeGroupId}\" title=\"Edit group\">
        <svg xmlns=\"http://www.w3.org/2000/svg\" fill=\"none\" viewBox=\"0 0 24 24\" stroke-width=\"1.5\" stroke=\"currentColor\" class=\"h-4 w-4 text-slate-600 dark:text-slate-300 transition-colors group-hover:text-slate-800 dark:group-hover:text-slate-100\">
          <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z\" />
          <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M15 12a3 3 0 11-6 0 3 3 0 016 0z\" />
        </svg>
      </button>` : '';
    return `
      <div class=\"grid-stack-item-content border border-slate-300/90 bg-slate-50/70 dark:border-slate-600 dark:bg-slate-900/35 rounded-md shadow-sm text-gray-700 dark:text-slate-300 flex flex-col min-h-0 group\" data-widget-id=\"${safeGroupId}\" data-widget-type=\"group\" data-item-kind=\"group\" data-widget-title=\"${this.escapeHtml(titleText)}\">
        <div class=\"grid-widget-header flex items-center justify-between pt-2 px-3 mb-2 pb-1 border-b border-slate-300/80 dark:border-slate-700/80\">
          <div class=\"grid-widget-handle root-grid-widget-handle group-grid-widget-handle cursor-move flex-1 flex items-center gap-2 py-1 min-w-0\"><div class=\"grid-widget-title font-semibold truncate text-slate-800 dark:text-slate-100\" data-original-title=\"${this.escapeHtml(titleText)}\">${this.escapeHtml(titleText)}</div></div>
          <div class=\"grid-widget-actions flex items-center gap-1 opacity-0 transition-opacity duration-150 group-hover:opacity-100 group-focus-within:opacity-100\">
            ${editBtn}
          </div>
        </div>
        <div class=\"flex-1 min-h-0 px-2 pb-2\">
          <div class=\"relative h-full min-h-0\" data-group-grid-shell=\"1\">
            <div class=\"grid-stack grid-stack-group h-full min-h-0 rounded-md border border-dashed border-slate-300/90 dark:border-slate-600 bg-transparent\" data-group-grid=\"1\" data-group-id=\"${safeGroupId}\" data-cols=\"12\"></div>
            <div data-group-empty-hint=\"1\" class=\"pointer-events-none absolute inset-0 flex items-center justify-center px-6 text-center text-xs font-medium uppercase tracking-[0.18em] text-slate-400 dark:text-slate-500\">Drag widgets here</div>
          </div>
        </div>
      </div>`;
  },

  genId() { return Math.random().toString(36).slice(2); },

  _rootBottom() {
    let bottom = 0;
    this._gridItems(this.grid).forEach((it) => {
      const y = parseInt(it.getAttribute('gs-y') || '0', 10);
      const h = parseInt(it.getAttribute('gs-h') || '1', 10);
      bottom = Math.max(bottom, y + h);
    });
    return bottom;
  },

  addNewWidget() {
    const id = this.genId();
    const w = 3, h = 2, x = 0, y = this._rootBottom();

    const el = this.grid.addWidget({ x, y, w, h, id, content: '' });
    if (el) {
      el.setAttribute('data-item-kind', 'widget');
      const contentEl = el.querySelector('.grid-stack-item-content');
      if (contentEl) {
        contentEl.outerHTML = this._newWidgetContent({ id, title: 'New Widget' });
      }
    }
    this.saveLayout();
  },

  addNewGroup() {
    const id = this.genId();
    const w = 6, h = 4, x = 0, y = this._rootBottom();
    const el = this.grid.addWidget({ x, y, w, h, id, content: '' });
    if (el) {
      el.setAttribute('data-item-kind', 'group');
      const contentEl = el.querySelector('.grid-stack-item-content');
      if (contentEl) {
        contentEl.outerHTML = this._newGroupContent({ id, title: 'Widget Group' });
      }
      this._initGroupGrid(el);
    }
    this.saveLayout();
  },

  _readItemTitle(el) {
    if (!el) return '';
    const content = el.querySelector('.grid-stack-item-content');
    const titleEl = el.querySelector('.grid-widget-title');
    const storedTitle = (content && content.dataset.widgetTitle) || (titleEl && titleEl.dataset.originalTitle);
    const textTitle = (titleEl && titleEl.textContent ? titleEl.textContent.trim() : '') || '';
    return (storedTitle !== undefined && storedTitle !== null ? storedTitle : textTitle).trim();
  },

  _serializeGrid(grid) {
    return this._gridItems(grid).map((el) => this._serializeGridItem(el));
  },

  _serializeGridItem(el) {
    const content = el.querySelector('.grid-stack-item-content');
    const item = {
      x: parseInt(el.getAttribute('gs-x') || '0', 10),
      y: parseInt(el.getAttribute('gs-y') || '0', 10),
      w: parseInt(el.getAttribute('gs-w') || '1', 10),
      h: parseInt(el.getAttribute('gs-h') || '1', 10),
      id: el.getAttribute('gs-id') || this.genId(),
      title: this._readItemTitle(el),
    };
    const widgetType = content && content.dataset ? content.dataset.widgetType : null;
    if (widgetType) {
      item.type = widgetType;
    }
    if (this._isGroupItem(el)) {
      const nested = this._initGroupGrid(el);
      item.type = 'group';
      item.children = nested ? this._serializeGrid(nested) : [];
    }
    return item;
  },

  saveLayout() {
    if (!this.editable) return;
    this._ensureGroupGrids();
    this._refreshAllGroupHints();
    const items = this._serializeGrid(this.grid);
    this.pushEvent('dashboard_grid_changed', { items });
  },

  syncServerRenderedItems() {
    if (!this.grid) return;
    this._syncGridWidgets(this.grid);
    this._ensureGroupGrids();
    Object.values(this._childGrids || {}).forEach((grid) => this._syncGridWidgets(grid));
    this._refreshAllGroupHints();
  },

  _removeGridItem(item) {
    if (!item) return;
    const gridEl = item.closest && item.closest('.grid-stack');
    const grid = (gridEl && gridEl.gridstack) || this.grid;
    if (grid && typeof grid.removeWidget === 'function') {
      try { grid.removeWidget(item); } catch (_) {}
    }
  },

  _moveGroupChildrenToRoot(groupItem) {
    const groupId = groupItem && groupItem.getAttribute ? groupItem.getAttribute('gs-id') : null;
    const childGrid = (groupId && this._childGrids[groupId]) || null;
    if (!childGrid || !this.grid) return;
    const groupX = parseInt(groupItem.getAttribute('gs-x') || '0', 10);
    const groupY = parseInt(groupItem.getAttribute('gs-y') || '0', 10);
    const children = this._gridItems(childGrid);
    children.forEach((child) => {
      const rawX = groupX + parseInt(child.getAttribute('gs-x') || '0', 10);
      const y = groupY + parseInt(child.getAttribute('gs-y') || '0', 10);
      const w = parseInt(child.getAttribute('gs-w') || '1', 10);
      const h = parseInt(child.getAttribute('gs-h') || '1', 10);
      const x = Math.min(Math.max(0, rawX), Math.max(0, this.cols - w));
      const id = child.getAttribute('gs-id') || this.genId();
      try { childGrid.removeWidget(child, false, false); } catch (_) {}
      child.setAttribute('data-item-kind', 'widget');
      try { this.grid.addWidget(child, { x, y, w, h, id }); } catch (_) {}
    });
  },

  _enableServerRenderedWidgetPreference() {
    this._preferServerRenderedWidgets = true;
    if (this._preferServerRenderedWidgetsTimer) {
      clearTimeout(this._preferServerRenderedWidgetsTimer);
      this._preferServerRenderedWidgetsTimer = null;
    }
  },

  _scheduleServerRenderedWidgetPreferenceClear() {
    if (this._preferServerRenderedWidgetsTimer) {
      clearTimeout(this._preferServerRenderedWidgetsTimer);
    }
    this._preferServerRenderedWidgetsTimer = setTimeout(() => {
      this._preferServerRenderedWidgets = false;
      this._preferServerRenderedWidgetsTimer = null;
    }, 60);
  },

  _markServerRenderedWidgetsReady() {
    if (!this._seen || !this.el) return;
    this._seen.text = !!this.el.querySelector('.grid-stack-item-content[data-text-widget="1"]');
    this._seen.list = !!this.el.querySelector('.grid-stack-item-content[data-list-widget="1"]');
    if (typeof this._scheduleReadyMark === 'function') {
      this._scheduleReadyMark();
    }
  },

  _disposeChartEntry(map, id) {
    if (!map || !id) return;
    const chart = map[id];
    if (chart) {
      try {
        if (typeof chart.dispose === 'function') {
          chart.dispose();
        } else if (typeof chart.destroy === 'function') {
          chart.destroy();
        }
      } catch (_) {}
    }
    delete map[id];
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
        this._disposeChartEntry(this._sparklines, normalizedId);
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
        this._disposeChartEntry(this._tsCharts, normalizedId);
        this._disposeChartEntry(this._sparklines, normalizedId);
      }
      this._render_timeseries(this._sortedWidgetValues(registry.timeseries));
      return;
    }

    if (type === 'category') {
      if (payload) {
        registry.category[normalizedId] = Object.assign({}, payload, { id: payload.id || normalizedId });
      } else {
        delete registry.category[normalizedId];
        this._disposeChartEntry(this._catCharts, normalizedId);
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
        this._disposeChartEntry(this._distCharts, normalizedId);
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

  _widgetPayloadFromRegistry(type, id) {
    const registry = this._widgetRegistry || {};
    const normalizedType = String(type || '').toLowerCase();
    const normalizedId = id == null ? null : String(id);
    if (!normalizedId) return undefined;

    switch (normalizedType) {
      case 'kpi': {
        const value = registry.kpiValues && registry.kpiValues[normalizedId];
        const visual = registry.kpiVisuals && registry.kpiVisuals[normalizedId];
        if (!value && !visual) return undefined;
        return this._deepClone({ value: value || null, visual: visual || null });
      }
      case 'timeseries':
        return registry.timeseries && registry.timeseries[normalizedId]
          ? this._deepClone(registry.timeseries[normalizedId])
          : undefined;
      case 'category':
        return registry.category && registry.category[normalizedId]
          ? this._deepClone(registry.category[normalizedId])
          : undefined;
      case 'table':
        return registry.table && registry.table[normalizedId]
          ? this._deepClone(registry.table[normalizedId])
          : undefined;
      case 'text':
        return registry.text && registry.text[normalizedId]
          ? this._deepClone(registry.text[normalizedId])
          : undefined;
      case 'list':
        return registry.list && registry.list[normalizedId]
          ? this._deepClone(registry.list[normalizedId])
          : undefined;
      case 'distribution':
      case 'heatmap':
        return registry.distribution && registry.distribution[normalizedId]
          ? this._deepClone(registry.distribution[normalizedId])
          : undefined;
      default:
        return undefined;
    }
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
      this._markServerRenderedWidgetsReady();
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
