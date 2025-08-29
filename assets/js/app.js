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

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let Hooks = {}

Hooks.SmartTimeframeInput = {
  mounted() {
    this.handleEvent("update_smart_timeframe_input", ({value}) => {
      this.el.value = value;
    });
  }
}


Hooks.ProjectTimeline = {
  createChart(data, key, timezone, chartType, colors, selectedKeyColor) {
    // Calculate dynamic bar width based on container and data points
    const container = document.getElementById('timeline-chart');
    const containerWidth = container.clientWidth || 800; // fallback width
    const dataPointsLength = chartType === 'stacked' ? (data[0]?.data?.length || 0) : data.length;
    const availableWidth = containerWidth * 0.8; // leave some margin
    const maxBarWidth = Math.max(8, Math.min(40, availableWidth / dataPointsLength * 0.7)); // min 8px, max 40px
    
    // Configure series and options based on chart type
    const isStacked = chartType === 'stacked';
    
    // Handle empty data case - ensure we have at least an empty series structure
    let series;
    if (isStacked) {
      series = (data && data.length > 0) ? data : [];
    } else {
      series = [{name: key || 'Data', data: data || []}];
    }
    
    // Detect dark mode
    const isDarkMode = document.documentElement.classList.contains('dark');
    const backgroundColor = isDarkMode ? '#1e293b' : '#ffffff';
    const textColor = isDarkMode ? '#94a3b8' : '#374151';
    const lineColor = isDarkMode ? '#475569' : '#d1d5db';
    const gridColor = isDarkMode ? '#475569' : '#f3f4f6';
    
    return Highcharts.chart('timeline-chart', {
      chart: {
        type: 'column',
        height: '120',
        marginTop: 10,
        spacingTop: 5,
        backgroundColor: backgroundColor
      },
      time: {
        useUTC: true,
        timezone: timezone
      },
      title: {
        text: undefined
      },
      xAxis: {
        type: 'datetime',
        dateTimeLabelFormats: {
          millisecond: '%H:%M:%S.%L',
          second: '%H:%M',
          minute: '%H:%M',
          hour: '%H:%M',
          day: '%m-%d %H:%M',
          week: '%m-%d',
          month: '%e. %b',
          year: '%b'
        },
        title: {
          enabled: false
        },
        labels: {
          style: {
            color: textColor
          }
        },
        lineColor: lineColor,
        tickColor: lineColor
      },
      yAxis: {
        title: {
          enabled: false
        },
        min: 0,
        endOnTick: false,
        maxPadding: 0.05,
        labels: {
          style: {
            color: textColor
          }
        },
        gridLineColor: gridColor
      },

      tooltip: {
        xDateFormat: '%Y-%m-%d %H:%M:%S',
        backgroundColor: isDarkMode ? '#0f172a' : '#ffffff',
        style: {
          color: isDarkMode ? '#ffffff' : '#374151'
        },
        borderColor: isDarkMode ? '#475569' : '#d1d5db'
      },

      legend: {
        enabled: false
      },

      plotOptions: {
        column: {
          pointPadding: 0.2,
          groupPadding: 0.1,
          maxPointWidth: maxBarWidth,
          borderWidth: 0,
          stacking: isStacked ? 'normal' : null
        },
        series: {
          marker: {
            enabled: true,
            radius: 2.5
          }
        }
      },

      colors: chartType === 'single' && selectedKeyColor ? [selectedKeyColor] : colors,

      series: series
    });
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
      this.chart.destroy();
      this.chart = this.createChart(data, key, timezone, chartType, colors, selectedKeyColor);
      this.currentChartType = chartType;
      return;
    }

    // Same chart type - just update data
    const container = document.getElementById('timeline-chart');
    const containerWidth = container.clientWidth || 800;
    const dataPointsLength = chartType === 'stacked' ? (data[0]?.data?.length || 0) : data.length;
    const availableWidth = containerWidth * 0.8;
    const maxBarWidth = Math.max(8, Math.min(40, availableWidth / dataPointsLength * 0.7));
    
    // Update chart options with new bar width and colors
    this.chart.update({
      colors: chartType === 'single' && selectedKeyColor ? [selectedKeyColor] : colors,
      plotOptions: {
        column: {
          pointPadding: 0.2,
          groupPadding: 0.1,
          maxPointWidth: maxBarWidth,
          borderWidth: 0,
          stacking: chartType === 'stacked' ? 'normal' : null
        }
      }
    });
    
    if (chartType === 'stacked') {
      // Update multiple series for stacked chart
      while (this.chart.series.length > 0) {
        this.chart.series[0].remove(false);
      }
      // Only add series if data exists and is not empty
      if (data && data.length > 0) {
        data.forEach(series => {
          this.chart.addSeries(series, false);
        });
      }
      this.chart.redraw();
    } else {
      // Update single series - only if data exists
      if (this.chart.series[0] && data) {
        this.chart.series[0].setData(data);
      }
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
        const highlightColor = isDarkMode ? '#1e293b' : '#f0fdfa';
        
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
      box-shadow: 0 2px 8px rgba(0,0,0,0.15);
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
