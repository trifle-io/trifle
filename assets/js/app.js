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

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let Hooks = {}

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



Hooks.DatabaseExploreChart = {
  createChart(data, key, timezone, chartType, colors, selectedKeyColor) {
    // Parse colors from the passed parameter
    const colorArray = typeof colors === 'string' ? JSON.parse(colors) : colors;
    
    // Initialize ECharts instance
    const isDarkMode = document.documentElement.classList.contains('dark');
    const container = document.getElementById('timeline-chart');
    
    // Set theme based on dark mode
    const theme = isDarkMode ? 'dark' : undefined;
    this.chart = echarts.init(container, theme, { height: 120 });
    
    // Configure options based on chart type
    const isStacked = chartType === 'stacked';
    
    // Prepare series data
    let series;
    if (isStacked) {
      // For stacked chart, data comes as array of series
      series = (data && data.length > 0) ? data.map((seriesData, index) => ({
        name: seriesData.name,
        type: 'bar',
        stack: 'total',
        data: seriesData.data,
        itemStyle: {
          color: colorArray[index % colorArray.length]
        }
      })) : [];
    } else {
      // For single series
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
    
    // Create ECharts options with theme-aware colors
    const textColor = isDarkMode ? '#9CA3AF' : '#6B7280';
    const axisLineColor = isDarkMode ? '#374151' : '#E5E7EB';
    
    const option = {
      backgroundColor: 'transparent',
      grid: {
        top: 10,
        bottom: 30,
        left: 50,
        right: 20
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
        extraCssText: 'z-index: 9999;',
        formatter: function(params) {
          const date = new Date(params.value[0]);
          const dateStr = echarts.format.formatTime('yyyy-MM-dd hh:mm:ss', date, false);
          const value = params.value[1];
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
          formatter: function(value) {
            // Format based on the granularity
            const date = new Date(value);
            const hours = date.getHours();
            const minutes = date.getMinutes();
            
            // Show date when it's midnight
            if (hours === 0 && minutes === 0) {
              return echarts.format.formatTime('MM-dd', value, false);
            }
            // Otherwise show time
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
          color: textColor
        },
        splitLine: {
          lineStyle: {
            color: axisLineColor
          }
        }
      },
      series: series,
      animation: true,
      animationDuration: 300
    };
    
    // Set the option
    this.chart.setOption(option);
    
    // Handle window resize
    this.resizeHandler = () => {
      if (this.chart && !this.chart.isDisposed()) {
        this.chart.resize();
      }
    };
    window.addEventListener('resize', this.resizeHandler);
    
    // Handle theme changes
    this.handleEvent("phx:theme-changed", () => {
      if (this.chart && !this.chart.isDisposed()) {
        this.chart.dispose();
        this.chart = this.createChart(
          JSON.parse(this.el.dataset.events),
          this.el.dataset.key,
          this.el.dataset.timezone,
          this.el.dataset.chartType,
          JSON.parse(this.el.dataset.colors),
          this.el.dataset.selectedKeyColor
        );
      }
    });
    
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
      // Check current theme
      const isDarkMode = document.documentElement.classList.contains('dark');
      const textColor = isDarkMode ? '#9CA3AF' : '#6B7280';
      const axisLineColor = isDarkMode ? '#374151' : '#E5E7EB';
      
      // Prepare series data
      let series;
      if (chartType === 'stacked') {
        series = (data && data.length > 0) ? data.map((seriesData, index) => ({
          name: seriesData.name,
          type: 'bar',
          stack: 'total',
          data: seriesData.data,
          itemStyle: {
            color: colors[index % colors.length]
          }
        })) : [];
      } else {
        const seriesColor = selectedKeyColor || colors[0];
        series = [{
          name: key || 'Data',
          type: 'bar',
          data: data || [],
          itemStyle: {
            color: seriesColor
          }
        }];
      }

      // Update the chart with theme-aware colors
      this.chart.setOption({
        textStyle: {
          color: textColor
        },
        tooltip: {
          backgroundColor: isDarkMode ? '#1F2937' : '#FFFFFF',
          borderColor: isDarkMode ? '#374151' : '#E5E7EB',
          textStyle: {
            color: isDarkMode ? '#F3F4F6' : '#1F2937'
          }
        },
        xAxis: {
          axisLine: {
            lineStyle: {
              color: axisLineColor
            }
          },
          axisLabel: {
            color: textColor
          }
        },
        yAxis: {
          axisLine: {
            lineStyle: {
              color: axisLineColor
            }
          },
          axisLabel: {
            color: textColor
          },
          splitLine: {
            lineStyle: {
              color: axisLineColor
            }
          }
        },
        series: series
      });
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
    this._tsCharts = {};
    this._catCharts = {};

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
      } catch (_) {}
    };
    window.addEventListener('resize', this._onWindowResize);
    // Avoid persisting transient responsive changes when navigating away
    this._onPageLoadingStart = () => { this._suppressSave = true; };
    window.addEventListener('phx:page-loading-start', this._onPageLoadingStart);
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

    // Determine renderer/devicePixelRatio for charts (SVG for print exports for crisp output)
    const printMode = (this.el.dataset.printMode === 'true' || this.el.dataset.printMode === '');
    this._echartsRenderer = printMode ? 'svg' : undefined;
    this._echartsDevicePixelRatio = printMode ? 2 : (window.devicePixelRatio || 1);
    this._chartInitOpts = (extra = {}) => {
      const opts = Object.assign({}, extra);
      if (this._echartsRenderer) opts.renderer = this._echartsRenderer;
      if (this._echartsDevicePixelRatio) opts.devicePixelRatio = this._echartsDevicePixelRatio;
      return opts;
    };

    this.initGrid();

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
    try { this.initialKpiSpark = this.el.dataset.initialKpiSpark ? JSON.parse(this.el.dataset.initialKpiSpark) : []; } catch (_) { this.initialKpiSpark = []; }
    try { this.initialTimeseries = this.el.dataset.initialTimeseries ? JSON.parse(this.el.dataset.initialTimeseries) : []; } catch (_) { this.initialTimeseries = []; }
    try { this.initialCategory = this.el.dataset.initialCategory ? JSON.parse(this.el.dataset.initialCategory) : []; } catch (_) { this.initialCategory = []; }
    if ((this.initialKpiValues && this.initialKpiValues.length) || (this.initialKpiSpark && this.initialKpiSpark.length) || (this.initialTimeseries && this.initialTimeseries.length) || (this.initialCategory && this.initialCategory.length)) {
      setTimeout(() => {
        try {
          if (this.initialKpiValues && this.initialKpiValues.length) this._render_kpi_values(this.initialKpiValues);
          if (this.initialKpiSpark && this.initialKpiSpark.length) this._render_kpi_sparkline(this.initialKpiSpark);
          if (this.initialTimeseries && this.initialTimeseries.length) this._render_timeseries(this.initialTimeseries);
          if (this.initialCategory && this.initialCategory.length) this._render_category(this.initialCategory);
        } catch (e) { console.error('initial print render failed', e); }
      }, 0);
    }

    // Ready signaling for export capture
    this._seen = { kpi_values: false, kpi_spark: false, timeseries: false, category: false };
    this._markedReady = false;
    this._scheduleReadyMark = () => {
      if (this._readyTimer) clearTimeout(this._readyTimer);
      this._readyTimer = setTimeout(() => {
        if (this._markedReady) return;
        const ready = this._seen.timeseries || this._seen.category || (this._seen.kpi_values && this._seen.kpi_spark);
        if (ready) { this._markedReady = true; try { window.TRIFLE_READY = true; } catch (_) {} }
      }, 200);
    };

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
      this._scheduleReadyMark = () => {
        if (this._readyTimer) clearTimeout(this._readyTimer);
        this._readyTimer = setTimeout(() => {
          try {
            const charts = document.querySelectorAll('.ts-chart, .cat-chart, .kpi-spark');
            if (charts.length === 0) return;
            const allReady = Array.prototype.every.call(charts, el => el && el.dataset && el.dataset.echartsReady === '1');
            if (allReady) requestAnimationFrame(() => requestAnimationFrame(() => { window.TRIFLE_READY = true; }));
          } catch (_) {}
        }, 100);
      };
    } catch (_) {}

    // LiveView -> Hook updates for widget edits/deletes
    this.handleEvent('dashboard_grid_widget_updated', ({ id, title }) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${id}"]`);
      const titleEl = item && item.querySelector('.grid-widget-title');
      if (titleEl) titleEl.textContent = title;
      // ensure layout save reflects new title
      this.saveLayout();
    });
    this.handleEvent('dashboard_grid_widget_deleted', ({ id }) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${id}"]`);
      if (item) {
        this.grid.removeWidget(item);
        this.saveLayout();
      }
    });

    // Update KPI numeric values inside widgets
    this.handleEvent('dashboard_grid_kpi_values', ({ items }) => {
      if (!Array.isArray(items)) return;
      items.forEach((it) => {
        const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
        const body = item && item.querySelector('.grid-widget-body');
        if (!body) return;
        // KPI display
        const sizeClass = (() => {
          const sz = (it.size || 'm');
          if (sz === 's') return 'text-2xl';
          if (sz === 'l') return 'text-4xl';
          return 'text-3xl';
        })();
        const fmt = (v) => {
          if (v === null || v === undefined || Number.isNaN(v)) return '—';
          const n = Number(v);
          if (!Number.isFinite(n)) return String(v);
          // Compact formatting
          if (Math.abs(n) >= 1000) {
            const units = ['','K','M','B','T'];
            let u = 0; let num = Math.abs(n);
            while (num >= 1000 && u < units.length-1) { num /= 1000; u++; }
            const sign = n < 0 ? '-' : '';
            return `${sign}${num.toFixed(num < 10 ? 2 : 1)}${units[u]}`;
          }
          return n.toFixed(2).replace(/\.00$/, '');
        };
        // Ensure persistent containers for top value + sparkline; stack vertically
        let wrap = body.querySelector('.kpi-wrap');
        if (!wrap) {
          body.innerHTML = `<div class="kpi-wrap w-full flex flex-col justify-center"><div class="kpi-top"></div><div class="kpi-spark mt-2" style="height: 40px; width: calc(100% + 24px); margin-left: -12px; margin-right: -12px; margin-bottom: -36px;"></div></div>`;
          wrap = body.querySelector('.kpi-wrap');
        }
        let top = wrap.querySelector('.kpi-top');
        if (it.split) {
          const prevNum = (it.previous == null ? null : Number(it.previous));
          const currNum = (it.current == null ? null : Number(it.current));
          const prev = fmt(it.previous);
          const curr = fmt(it.current);
          let diffHtml = '';
          if (it.diff && prevNum != null && currNum != null && isFinite(prevNum) && prevNum !== 0) {
            const delta = currNum - prevNum;
            const pct = (delta / Math.abs(prevNum)) * 100;
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
                <div class="flex items-baseline ${sizeClass} font-bold text-gray-900 dark:text-white">${curr}<span class="ml-2 text-sm font-medium text-gray-500 dark:text-slate-400">from ${prev}</span></div>
                ${diffHtml}
              </div>
            </div>`;
        } else {
          const val = fmt(it.value);
          top.innerHTML = `<div class="${sizeClass} font-bold text-gray-900 dark:text-white">${val}</div>`;
        }
      });
      this._seen.kpi_values = true; this._scheduleReadyMark();
    });

    // Draw/update sparkline charts for KPI widgets
    this.handleEvent('dashboard_grid_kpi_sparkline', ({ items }) => {
      if (!Array.isArray(items)) return;
      const isDarkMode = document.documentElement.classList.contains('dark');
      const color = (this.colors && this.colors[0]) || '#14b8a6';
      items.forEach((it) => {
        const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
        const body = item && item.querySelector('.grid-widget-body');
        if (!body) return;
        let spark = body.querySelector('.kpi-spark');
        if (!spark) {
          spark = document.createElement('div');
          spark.className = 'kpi-spark mt-2';
          spark.style.height = '40px';
          spark.style.width = 'calc(100% + 24px)';
          spark.style.marginLeft = '-12px';
          spark.style.marginRight = '-12px';
          spark.style.marginBottom = '-36px';
          body.appendChild(spark);
        }
        const render = () => {
          let chart = this._sparklines[it.id];
          const theme = isDarkMode ? 'dark' : undefined;
          if (!chart) {
            // Avoid init when container has zero size
            if (spark.clientWidth === 0 || spark.clientHeight === 0) {
              if (this._sparkTimers[it.id]) clearTimeout(this._sparkTimers[it.id]);
              this._sparkTimers[it.id] = setTimeout(render, 80);
              return;
            }
            chart = echarts.init(spark, theme, this._chartInitOpts({ height: 40 }));
            this._sparklines[it.id] = chart;
          }
          chart.setOption({
            backgroundColor: 'transparent',
            grid: { top: 0, bottom: 0, left: 0, right: 0 },
            xAxis: { type: 'time', show: false },
            yAxis: { type: 'value', show: false },
            tooltip: { show: false },
            series: [{
              type: 'line',
              data: it.data || [],
              smooth: true,
              showSymbol: false,
              lineStyle: { width: 1, color },
              areaStyle: { color, opacity: 0.08 },
            }],
            animation: false
          }, true);
          try { chart.off('finished'); chart.on('finished', () => { try { spark.dataset.echartsReady = '1'; this._scheduleReadyMark(); } catch(_){} }); } catch(_){}
          chart.resize();
          if (!this._sparkResize) {
            this._sparkResize = () => {
              Object.values(this._sparklines).forEach(c => c && !c.isDisposed() && c.resize());
            };
            window.addEventListener('resize', this._sparkResize);
          }
        };
        // Defer one frame to allow DOM layout
        setTimeout(render, 0);
      });
      this._seen.kpi_spark = true; this._scheduleReadyMark();
    });

    // Draw/update per-widget timeseries charts
    this.handleEvent('dashboard_grid_timeseries', ({ items }) => {
      // Render timeseries charts
      if (!Array.isArray(items)) return;
      const isDarkMode = document.documentElement.classList.contains('dark');
      const colors = this.colors || [];
      items.forEach((it) => {
        const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
        const body = item && item.querySelector('.grid-widget-body');
        if (!body) return;

        // Prepare container
        let container = body.querySelector('.ts-chart');
        if (!container) {
          // Clear placeholder
          body.innerHTML = '';
          body.classList.remove('items-center','justify-center','text-sm','text-gray-500','dark:text-slate-400');
          container = document.createElement('div');
          container.className = 'ts-chart';
          container.style.width = '100%';
          container.style.height = '100%';
          body.appendChild(container);
        }

        // Init or reuse chart
        let chart = this._tsCharts[it.id];
        const theme = isDarkMode ? 'dark' : undefined;
        const ensureInit = () => {
          if (!chart) {
            if (container.clientWidth === 0 || container.clientHeight === 0) {
              try { console.debug('ts chart delayed (zero size)', it.id); } catch (_) {}
              setTimeout(ensureInit, 80);
              return;
            }
            chart = echarts.init(container, theme, this._chartInitOpts());
            this._tsCharts[it.id] = chart;
          }

          // Build series options
          const type = (it.chart_type || 'line');
          const stacked = !!it.stacked;
          const normalized = !!it.normalized;
          const textColor = isDarkMode ? '#9CA3AF' : '#6B7280';
          const axisLineColor = isDarkMode ? '#374151' : '#E5E7EB';
          const legendText = isDarkMode ? '#D1D5DB' : '#374151';
          const showLegend = !!it.legend;
          const bottomPadding = showLegend ? 56 : 28;
          const series = (it.series || []).map((s, idx) => {
            const base = {
              name: s.name || `Series ${idx+1}`,
              type: (type === 'area') ? 'line' : type,
              data: s.data || [],
              showSymbol: false,
            };
            if (stacked) base.stack = 'total';
            if (type === 'area') base.areaStyle = { opacity: 0.1 };
            if (colors.length) base.itemStyle = { color: colors[idx % colors.length] };
            return base;
          });

          // Axis formatting
          const yName = normalized ? (it.y_label || 'Percentage') : (it.y_label || '');
          const yAxis = {
            type: 'value',
            min: 0,
            name: yName,
            nameLocation: 'middle',
            nameGap: 40,
            nameTextStyle: { color: textColor },
            axisLine: { lineStyle: { color: axisLineColor } },
            axisLabel: { color: textColor, margin: 8, hideOverlap: true },
          };
          if (normalized) {
            yAxis.max = 100;
            yAxis.axisLabel = { formatter: (v) => `${v}%` };
          }

          chart.setOption({
            backgroundColor: 'transparent',
            grid: { top: 12, bottom: bottomPadding, left: 56, right: 20, containLabel: true },
            xAxis: {
              type: 'time',
              axisLine: { lineStyle: { color: axisLineColor } },
              axisLabel: { color: textColor, margin: 8, hideOverlap: true },
            },
            yAxis,
            legend: showLegend ? { type: 'scroll', bottom: 4, textStyle: { color: legendText } } : { show: false },
            tooltip: {
              trigger: 'axis',
              confine: true,
              valueFormatter: (v) => v == null ? '-' : (normalized ? `${Number(v).toFixed(2)}%` : `${v}`),
            },
            series,
            animation: false
          }, true);
          try { chart.off('finished'); chart.on('finished', () => { try { container.dataset.echartsReady = '1'; this._scheduleReadyMark(); } catch(_){} }); } catch(_){}
          chart.resize();
        };
        setTimeout(ensureInit, 0);
      });
      this._seen.timeseries = true; this._scheduleReadyMark();
    });

    // Draw/update per-widget category charts
    this.handleEvent('dashboard_grid_category', ({ items }) => {
      // Render category charts
      if (!Array.isArray(items)) return;
      const isDarkMode = document.documentElement.classList.contains('dark');
      const colors = this.colors || [];
      items.forEach((it) => {
        const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
        const body = item && item.querySelector('.grid-widget-body');
        if (!body) return;

        // Prepare container
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

        // Init or reuse chart
        let chart = this._catCharts[it.id];
        const theme = isDarkMode ? 'dark' : undefined;
        const ensureInit = () => {
          if (!chart) {
            if (container.clientWidth === 0 || container.clientHeight === 0) {
              setTimeout(ensureInit, 80);
              return;
            }
            chart = echarts.init(container, theme, this._chartInitOpts());
            this._catCharts[it.id] = chart;
          }

          const data = it.data || [];
          const type = (it.chart_type || 'bar');
          let option;
          if (type === 'pie' || type === 'donut') {
            option = {
              backgroundColor: 'transparent',
              tooltip: { trigger: 'item' },
              // Use the same palette as other charts
              color: (colors && colors.length ? colors : undefined),
              series: [{
                type: 'pie',
                radius: (type === 'donut') ? ['50%','70%'] : '70%',
                avoidLabelOverlap: true,
                data,
                // Ensure each slice uses a palette color by index
                itemStyle: {
                  color: (params) => (colors && colors.length)
                    ? colors[params.dataIndex % colors.length]
                    : params.color
                }
              }],
              animation: false
            };
          } else {
            // bar chart
            option = {
              backgroundColor: 'transparent',
              grid: { top: 12, bottom: 28, left: 48, right: 16 },
              xAxis: {
                type: 'category',
                data: data.map(d => d.name),
              },
              yAxis: { type: 'value', min: 0 },
              tooltip: { trigger: 'axis' },
              series: [{
                type: 'bar',
                data: data.map(d => d.value),
                itemStyle: { color: (params) => colors[params.dataIndex % (colors.length || 1)] || '#14b8a6' }
              }],
              animation: false
            };
          }
          chart.setOption(option, true);
          try { chart.off('finished'); chart.on('finished', () => { try { container.dataset.echartsReady = '1'; this._scheduleReadyMark(); } catch(_){} }); } catch(_){}
          chart.resize();
        };
        setTimeout(ensureInit, 0);
      });
      this._seen.category = true; this._scheduleReadyMark();
    });
  },

  destroyed() {
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
  },

  initGrid() {
    // Pre-populate items into DOM so GridStack can pick them up
    if (Array.isArray(this.initialItems) && this.initialItems.length > 0) {
      this.initialItems.forEach((item) => this.addGridItemEl(item));
    }

    this.grid = GridStack.init({
      column: this.cols,
      minRow: this.minRows,
      float: true,
      margin: 5,
      disableOneColumnMode: true,
      styleInHead: true,
      cellHeight: 80,
      // drag only by the title bar (between title and cog button)
      draggable: { handle: '.grid-widget-handle' },
    }, this.el);

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
    };
    this.grid.on('change', () => { if (!this._suppressSave && !this._isOneCol && document.visibilityState !== 'hidden') save(); resizeCharts(); });
    this.grid.on('added', () => { if (!this._isOneCol) save(); resizeCharts(); });
    this.grid.on('removed', () => { if (!this._isOneCol) save(); resizeCharts(); });

    // No direct button binding needed; delegated handler set in mounted
  },

  // Reusable renderers (used by LiveView events and initial print rendering)
  _render_kpi_values(items) {
    if (!Array.isArray(items)) return;
    items.forEach((it) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
      const body = item && item.querySelector('.grid-widget-body');
      if (!body) return;
      const sizeClass = (() => {
        const sz = (it.size || 'm');
        if (sz === 's') return 'text-2xl';
        if (sz === 'l') return 'text-4xl';
        return 'text-3xl';
      })();
      const fmt = (v) => {
        if (v === null || v === undefined || Number.isNaN(v)) return '—';
        const n = Number(v);
        if (!Number.isFinite(n)) return String(v);
        if (Math.abs(n) >= 1000) {
          const units = ['','K','M','B','T'];
          let u = 0; let num = Math.abs(n);
          while (num >= 1000 && u < units.length-1) { num /= 1000; u++; }
          const sign = n < 0 ? '-' : '';
          return `${sign}${num.toFixed(num < 10 ? 2 : 1)}${units[u]}`;
        }
        return n.toFixed(2).replace(/\.00$/, '');
      };
      let wrap = body.querySelector('.kpi-wrap');
      if (!wrap) {
        body.innerHTML = `<div class="kpi-wrap w-full flex flex-col justify-center"><div class="kpi-top"></div><div class="kpi-spark mt-2" style="height: 40px; width: calc(100% + 24px); margin-left: -12px; margin-right: -12px; margin-bottom: -36px;"></div></div>`;
        wrap = body.querySelector('.kpi-wrap');
      }
      let top = wrap.querySelector('.kpi-top');
      if (it.split) {
        const prevNum = (it.previous == null ? null : Number(it.previous));
        const currNum = (it.current == null ? null : Number(it.current));
        const prev = fmt(it.previous);
        const curr = fmt(it.current);
        let diffHtml = '';
          if (it.diff && prevNum != null && currNum != null && isFinite(prevNum) && prevNum !== 0) {
            const delta = currNum - prevNum;
            const pct = (delta / Math.abs(prevNum)) * 100;
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
              <div class="flex items-baseline ${sizeClass} font-bold text-gray-900 dark:text-white">${curr}<span class="ml-2 text-sm font-medium text-gray-500 dark:text-slate-400">from ${prev}</span></div>
              ${diffHtml}
            </div>
          </div>`;
      } else {
        const val = fmt(it.value);
        top.innerHTML = `<div class="${sizeClass} font-bold text-gray-900 dark:text-white">${val}</div>`;
      }
    });
  },

  _render_kpi_sparkline(items) {
    if (!Array.isArray(items)) return;
    const isDarkMode = document.documentElement.classList.contains('dark');
    const color = (this.colors && this.colors[0]) || '#14b8a6';
    items.forEach((it) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
      const body = item && item.querySelector('.grid-widget-body');
      if (!body) return;
      let spark = body.querySelector('.kpi-spark');
      if (!spark) {
        spark = document.createElement('div');
        spark.className = 'kpi-spark mt-2';
        spark.style.height = '40px';
        spark.style.width = 'calc(100% + 24px)';
        spark.style.marginLeft = '-12px';
        spark.style.marginRight = '-12px';
        spark.style.marginBottom = '-36px';
        body.appendChild(spark);
      }
      const render = () => {
        let chart = this._sparklines[it.id];
        const theme = isDarkMode ? 'dark' : undefined;
        if (!chart) {
          if (spark.clientWidth === 0 || spark.clientHeight === 0) {
            setTimeout(render, 80);
            return;
          }
          chart = echarts.init(spark, theme, { height: 40 });
          this._sparklines[it.id] = chart;
        }
        const data = it.data || [];
        chart.setOption({
          backgroundColor: 'transparent',
          grid: { top: 0, bottom: 0, left: 0, right: 0 },
          xAxis: { type: 'time', show: false },
          yAxis: { type: 'value', show: false },
          tooltip: { show: false },
          series: [{ type: 'line', data, smooth: true, showSymbol: false, lineStyle: { width: 1, color }, areaStyle: { color, opacity: 0.08 } }]
        }, true);
        chart.resize();
      };
      setTimeout(render, 0);
    });
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
      const theme = isDarkMode ? 'dark' : undefined;
      const ensureInit = () => {
        if (!chart) {
          if (container.clientWidth === 0 || container.clientHeight === 0) { setTimeout(ensureInit, 80); return; }
          chart = echarts.init(container, theme);
          this._tsCharts[it.id] = chart;
        }
        const type = (it.chart_type || 'line');
        const stacked = !!it.stacked;
        const normalized = !!it.normalized;
        const textColor = isDarkMode ? '#9CA3AF' : '#6B7280';
        const axisLineColor = isDarkMode ? '#374151' : '#E5E7EB';
        const legendText = isDarkMode ? '#D1D5DB' : '#374151';
        const showLegend = !!it.legend;
        const bottomPadding = showLegend ? 56 : 28;
        const series = (it.series || []).map((s, idx) => {
          const base = { name: s.name || `Series ${idx+1}`, type: (type === 'area') ? 'line' : type, data: s.data || [], showSymbol: false };
          if (stacked) base.stack = 'total';
          if (type === 'area') base.areaStyle = { opacity: 0.1 };
          if (colors.length) base.itemStyle = { color: colors[idx % colors.length] };
          return base;
        });
        const yName = normalized ? (it.y_label || 'Percentage') : (it.y_label || '');
        const yAxis = { type: 'value', min: 0, name: yName, nameLocation: 'middle', nameGap: 40, nameTextStyle: { color: textColor }, axisLine: { lineStyle: { color: axisLineColor } }, axisLabel: { color: textColor, margin: 8, hideOverlap: true } };
        if (normalized) { yAxis.max = 100; yAxis.axisLabel = { formatter: (v) => `${v}%` }; }
        chart.setOption({ backgroundColor: 'transparent', grid: { top: 12, bottom: bottomPadding, left: 56, right: 20, containLabel: true }, xAxis: { type: 'time', axisLine: { lineStyle: { color: axisLineColor } }, axisLabel: { color: textColor, margin: 8, hideOverlap: true } }, yAxis, legend: showLegend ? { type: 'scroll', bottom: 4, textStyle: { color: legendText } } : { show: false }, tooltip: { trigger: 'axis', confine: true, valueFormatter: (v) => v == null ? '-' : (normalized ? `${Number(v).toFixed(2)}%` : `${v}`) }, series }, true);
        chart.resize();
      };
      setTimeout(ensureInit, 0);
    });
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
      const theme = isDarkMode ? 'dark' : undefined;
      const ensureInit = () => {
        if (!chart) {
          if (container.clientWidth === 0 || container.clientHeight === 0) { setTimeout(ensureInit, 80); return; }
          chart = echarts.init(container, theme);
          this._catCharts[it.id] = chart;
        }
        const data = it.data || [];
        const type = (it.chart_type || 'bar');
        let option;
        if (type === 'pie' || type === 'donut') {
          option = { backgroundColor: 'transparent', tooltip: { trigger: 'item' }, color: (colors && colors.length ? colors : undefined), series: [{ type: 'pie', radius: (type === 'donut') ? ['50%','70%'] : '70%', avoidLabelOverlap: true, data, itemStyle: { color: (params) => (colors && colors.length) ? colors[params.dataIndex % colors.length] : params.color } }] };
        } else {
          option = { backgroundColor: 'transparent', grid: { top: 12, bottom: 28, left: 48, right: 16 }, xAxis: { type: 'category', data: data.map(d => d.name) }, yAxis: { type: 'value', min: 0 }, tooltip: { trigger: 'axis' }, series: [{ type: 'bar', data: data.map(d => d.value), itemStyle: { color: (params) => colors[params.dataIndex % (colors.length || 1)] || '#14b8a6' } }] };
        }
        chart.setOption(option, true);
        chart.resize();
      };
      setTimeout(ensureInit, 0);
    });
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
    content.className = 'grid-stack-item-content bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-md shadow p-3 text-gray-700 dark:text-slate-300 flex flex-col';
    const titleText = item.title || `Widget ${String(item.id || '').slice(0,6)}`;
    const editBtn = this.editable ? `
      <button type=\"button\" class=\"grid-widget-edit inline-flex items-center p-1 rounded group\" data-widget-id=\"${el.getAttribute('gs-id')}\" title=\"Edit widget\"> 
        <svg xmlns=\"http://www.w3.org/2000/svg\" fill=\"none\" viewBox=\"0 0 24 24\" stroke-width=\"1.5\" stroke=\"currentColor\" class=\"h-4 w-4 text-gray-600 dark:text-slate-300 transition-colors group-hover:text-gray-800 dark:group-hover:text-slate-100\"> 
          <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z\" />
          <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z\" />
        </svg>
      </button>` : '';
    content.innerHTML = `
      <div class=\"grid-widget-header flex items-center justify-between mb-2 pb-1 border-b border-gray-100 dark:border-slate-700/60\">\n        <div class=\"grid-widget-handle cursor-move flex-1 flex items-center gap-2 min-w-0\"><div class=\"grid-widget-title font-semibold truncate text-gray-900 dark:text-white\">${this.escapeHtml(titleText)}</div></div>\n        ${editBtn}\n      </div>\n      <div class=\"grid-widget-body flex-1 flex items-center justify-center text-sm text-gray-500 dark:text-slate-400\">\n        Chart is coming soon\n      </div>`;
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
      contentEl.className = 'grid-stack-item-content bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-md shadow p-3 text-gray-700 dark:text-slate-300 flex flex-col';
      contentEl.innerHTML = `
        <div class=\"grid-widget-header flex items-center justify-between mb-2 pb-1 border-b border-gray-100 dark:border-slate-700/60\"> 
          <div class=\"grid-widget-handle cursor-move flex-1 flex items-center gap-2 min-w-0\"><div class=\"grid-widget-title font-semibold truncate text-gray-900 dark:text-white\">New Widget</div></div> 
          <button type=\"button\" class=\"grid-widget-edit inline-flex items-center p-1 rounded group\" data-widget-id=\"${id}\" title=\"Edit widget\"> 
          <svg xmlns=\"http://www.w3.org/2000/svg\" fill=\"none\" viewBox=\"0 0 24 24\" stroke-width=\"1.5\" stroke=\"currentColor\" class=\"h-4 w-4 text-gray-600 dark:text-slate-300 transition-colors group-hover:text-gray-800 dark:group-hover:text-slate-100\"> 
            <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.24-.438.613-.43.992a6.932 6.932 0 0 1 0 .255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z\" /> 
            <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z\" /> 
          </svg> 
          </button> 
        </div>
        <div class=\"grid-widget-body flex-1 flex items-center justify-center text-sm text-gray-500 dark:text-slate-400\"> 
          Chart is coming soon 
        </div>`;
    }
    this.saveLayout();
  },

  saveLayout() {
    if (!this.editable) return;
    const items = Array.from(this.el.querySelectorAll('.grid-stack-item')).map((el) => ({
      x: parseInt(el.getAttribute('gs-x') || '0', 10),
      y: parseInt(el.getAttribute('gs-y') || '0', 10),
      w: parseInt(el.getAttribute('gs-w') || '1', 10),
      h: parseInt(el.getAttribute('gs-h') || '1', 10),
      id: el.getAttribute('gs-id') || this.genId(),
      title: (el.querySelector('.grid-widget-title')?.textContent || '').trim(),
    }));
    this.pushEvent('dashboard_grid_changed', { items });
  },

  escapeHtml(str) {
    return String(str || '').replace(/[&<>"']/g, (s) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[s]));
  },
}

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
    this.button = this.el.querySelector('[data-role="download-button"]');
    this.label = this.el.querySelector('[data-role="download-text"]');
    const datasetLabel = (this.el.dataset && this.el.dataset.defaultLabel) || '';
    this.originalLabel = datasetLabel || (this.label ? this.label.textContent : '');
    this.iframe = document.querySelector('iframe[name="download_iframe"]');

    this.bindAnchors();
    this.bindIframe();

    // Global completion signal (for blob-based downloads or alternate flows)
    this._onDownloadComplete = () => this.stopLoading();
    window.addEventListener('download:complete', this._onDownloadComplete);
  },

  updated() {
    // Rebind anchors when dropdown content re-renders and reselect elements that may have been replaced
    this.button = this.el.querySelector('[data-role="download-button"]');
    this.label = this.el.querySelector('[data-role="download-text"]');
    const datasetLabel = (this.el.dataset && this.el.dataset.defaultLabel) || '';
    if (datasetLabel) {
      this.originalLabel = datasetLabel;
    } else if (!this.originalLabel && this.label) {
      this.originalLabel = this.label.textContent;
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
        // Inline handler manages tokens/loading for anchor-based downloads
        setTimeout(() => this.pushEvent('hide_export_dropdown', {}), 0);
        return;
      }
      if (!btn) return;
      this.startLoading();
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

  stopLoading() {
    if (!this.loading) return;
    this.loading = false;
    this.stopCookiePolling();
    if (this.button) {
      this.button.removeAttribute('aria-busy');
      this.button.classList.remove('opacity-70', 'cursor-wait');
      this.button.disabled = false;
    }
    const datasetLabel = (this.el.dataset && this.el.dataset.defaultLabel) || '';
    if (this.label) this.label.textContent = this.originalLabel || datasetLabel || 'Download';
  },

  applyLoadingState() {
    if (this.button) {
      this.button.setAttribute('aria-busy', 'true');
      this.button.classList.add('opacity-70', 'cursor-wait');
      this.button.disabled = true;
    }
    if (this.label) this.label.textContent = 'Generating...';
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
    const scrollContainer = container.querySelector('#table-hover-container');
    const table = container.querySelector('table');
    if (!table || !scrollContainer) return;
    
    // Fix border width to match table width
    const borderDiv = scrollContainer.querySelector('.border-t');
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
    const table = scrollContainer.querySelector('table');
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
    const borderDiv = scrollContainer.querySelector('.border-t');
    if (borderDiv && borderDiv.nextSibling) {
      scrollContainer.insertBefore(phantomContainer, borderDiv.nextSibling);
    } else {
      scrollContainer.appendChild(phantomContainer);
    }
  },
  
  clearPhantomRows() {
    const existing = document.querySelectorAll('.phantom-rows-js');
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
    const currentTheme = themePreference || body.getAttribute('data-theme') || 'system';
    
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
    const currentTheme = themePreference || body.getAttribute('data-theme') || 'system';
    const shouldUseDark = this.shouldUseDarkTheme(themePreference);
    
    // Update data-theme attribute if preference was provided
    if (themePreference) {
      body.setAttribute('data-theme', themePreference);
    }
    
    // Remove existing theme classes
    body.classList.remove('dark');
    document.documentElement.classList.remove('dark');
    
    // Apply theme classes based on user preference
    if (shouldUseDark) {
      body.classList.add('dark');
      document.documentElement.classList.add('dark');
    }
  }

}

// Initialize theme manager when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  window.themeManager = new ThemeManager();
});
