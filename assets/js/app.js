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
    const series = isStacked ? data : [{name: key, data: data}];
    
    return Highcharts.chart('timeline-chart', {
      chart: {
        type: 'column',
        height: '120',
        marginTop: 10,
        spacingTop: 5
      },
      time: {
        useUTC: false
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
        }
      },
      yAxis: {
        title: {
          enabled: false
        },
        min: 0,
        endOnTick: false,
        maxPadding: 0.05
      },

      tooltip: {
        xDateFormat: '%Y-%m-%d %H:%M:%S'
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
    console.log("Something has happened!");
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
      data.forEach(series => {
        this.chart.addSeries(series, false);
      });
      this.chart.redraw();
    } else {
      // Update single series
      this.chart.series[0].setData(data);
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
        
        // Highlight current cell's row header with important style
        const rowHeader = table.querySelector(`td[data-row="${row}"]:not([data-col])`);
        if (rowHeader) {
          rowHeader.style.backgroundColor = '#f0fdfa';
          rowHeader.classList.add('table-highlight');
        }
        
        // Highlight current cell's column header
        const colHeader = table.querySelector(`th[data-col="${col}"]`);
        if (colHeader) {
          colHeader.style.backgroundColor = '#f0fdfa';
          colHeader.classList.add('table-highlight');
        }
        
        // Highlight all cells in the same column
        const colCells = table.querySelectorAll(`td[data-col="${col}"]`);
        colCells.forEach(colCell => {
          colCell.style.backgroundColor = '#f0fdfa';
          colCell.classList.add('table-highlight');
        });
        
        // Highlight all cells in the same row
        const rowCells = table.querySelectorAll(`td[data-row="${row}"]`);
        rowCells.forEach(rowCell => {
          rowCell.style.backgroundColor = '#f0fdfa';
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
    console.log("All done!");
  })
})
