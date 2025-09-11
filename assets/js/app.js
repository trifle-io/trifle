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
    
    this.sortable = Sortable.create(this.el, {
      group: group,
      handle: handle,
      animation: 150,
      ghostClass: 'sortable-ghost',
      chosenClass: 'sortable-chosen',
      dragClass: 'sortable-drag',
      onEnd: (evt) => {
        // Get all item IDs in the new order
        const ids = Array.from(this.el.children).map(child => child.dataset.id);
        
        // Send the new order to LiveView
        this.pushEvent("reorder_transponders", { ids: ids });
      }
    });
  },
  
  destroyed() {
    if (this.sortable) {
      this.sortable.destroy();
    }
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

    this.initGrid();

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
              ? '<svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" class="mr-0.5 -ml-1 size-4 shrink-0 self-center text-green-500"><path d="M10 17a.75.75 0 0 1-.75-.75V5.612L5.29 9.77a.75.75 0 0 1-1.08-1.04l5.25-5.5a.75.75 0 0 1 1.08 0l5.25 5.5a.75.75 0 1 1-1.08 1.04l-3.96-4.158V16.25A.75.75 0 0 1 10 17Z" clip-rule="evenodd" fill-rule="evenodd"/></svg>'
              : '<svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true" class="mr-0.5 -ml-1 size-4 shrink-0 self-center text-red-500"><path d="M10 3a.75.75 0 0 1 .75.75v10.638l3.96-4.158a.75.75 0 1 1 1.08 1.04l-5.25 5.5a.75.75 0 0 1-1.08 0l-5.25-5.5a.75.75 0 1 1 1.08-1.04l3.96 4.158V3.75A.75.75 0 0 1 10 3Z" clip-rule="evenodd" fill-rule="evenodd"/></svg>';
            diffHtml = `<div class="inline-flex items-baseline rounded-full px-2.5 py-0.5 text-sm font-medium ${clrWrap}">${arrow}<span class="sr-only"> ${up ? 'Increased' : 'Decreased'} by </span>${pctText}</div>`;
          }
          top.innerHTML = `
            <div class="w-full">
              <div class="flex items-baseline justify-between w-full">
                <div class="flex items-baseline text-2xl font-bold text-gray-900 dark:text-white">${curr}<span class="ml-2 text-sm font-medium text-gray-500 dark:text-slate-400">from ${prev}</span></div>
                ${diffHtml}
              </div>
            </div>`;
        } else {
          const val = fmt(it.value);
          top.innerHTML = `<div class="text-3xl font-bold text-gray-900 dark:text-white">${val}</div>`;
        }
      });
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
            chart = echarts.init(spark, theme, { height: 40 });
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
            }]
          }, true);
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
    });

    // Draw/update per-widget timeseries charts
    this.handleEvent('dashboard_grid_timeseries', ({ items }) => {
      try { console.debug('dashboard_grid_timeseries', items && items.slice ? items.slice(0,2) : items); } catch (_) {}
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
            chart = echarts.init(container, theme);
            this._tsCharts[it.id] = chart;
          }

          // Build series options
          const type = (it.chart_type || 'line');
          const stacked = !!it.stacked;
          const normalized = !!it.normalized;
          const textColor = isDarkMode ? '#9CA3AF' : '#6B7280';
          const axisLineColor = isDarkMode ? '#374151' : '#E5E7EB';
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
          const yAxis = {
            type: 'value',
            min: 0,
            name: normalized ? 'Percentage' : 'Value',
            nameLocation: 'middle',
            nameGap: 40,
            nameTextStyle: { color: textColor },
            axisLine: { lineStyle: { color: axisLineColor } },
            axisLabel: { color: textColor },
          };
          if (normalized) {
            yAxis.max = 100;
            yAxis.axisLabel = { formatter: (v) => `${v}%` };
          }

          chart.setOption({
            backgroundColor: 'transparent',
            grid: { top: 12, bottom: 28, left: 48, right: 16 },
            xAxis: {
              type: 'time',
              name: 'Time',
              nameLocation: 'middle',
              nameGap: 22,
              nameTextStyle: { color: textColor },
              axisLine: { lineStyle: { color: axisLineColor } },
              axisLabel: { color: textColor },
            },
            yAxis,
            tooltip: {
              trigger: 'axis',
              confine: true,
              valueFormatter: (v) => v == null ? '-' : (normalized ? `${Number(v).toFixed(2)}%` : `${v}`),
            },
            series,
          }, true);
          chart.resize();
        };
        setTimeout(ensureInit, 0);
      });
    });

    // Draw/update per-widget category charts
    this.handleEvent('dashboard_grid_category', ({ items }) => {
      try { console.debug('dashboard_grid_category', items && items.slice ? items.slice(0,2) : items); } catch (_) {}
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
            chart = echarts.init(container, theme);
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
              }]
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
              }]
            };
          }
          chart.setOption(option, true);
          chart.resize();
        };
        setTimeout(ensureInit, 0);
      });
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
    this.grid.on('change', () => { save(); resizeCharts(); });
    this.grid.on('added', () => { save(); resizeCharts(); });
    this.grid.on('removed', () => { save(); resizeCharts(); });

    // No direct button binding needed; delegated handler set in mounted
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
      <div class=\"grid-widget-header flex items-center justify-between mb-2\">\n        <div class=\"grid-widget-title font-semibold truncate text-gray-900 dark:text-white\">${this.escapeHtml(titleText)}</div>\n        ${editBtn}\n      </div>\n      <div class=\"grid-widget-body flex-1 flex items-center justify-center text-sm text-gray-500 dark:text-slate-400\">\n        Chart is coming soon\n      </div>`;
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
        <div class=\"grid-widget-header flex items-center justify-between mb-2\"> 
          <div class=\"grid-widget-title font-semibold truncate text-gray-900 dark:text-white\">New Widget</div> 
          <button type=\"button\" class=\"grid-widget-edit inline-flex items-center p-1 rounded group\" data-widget-id=\"${id}\" title=\"Edit widget\"> 
          <svg xmlns=\"http://www.w3.org/2000/svg\" fill=\"none\" viewBox=\"0 0 24 24\" stroke-width=\"1.5\" stroke=\"currentColor\" class=\"h-4 w-4 text-gray-600 dark:text-slate-300 transition-colors group-hover:text-gray-800 dark:group-hover:text-slate-100\"> 
            <path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z\" /> 
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
