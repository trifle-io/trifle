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
Hooks.ProjectTimeline = {
  createChart(data, key) {
    return Highcharts.chart('timeline-chart', {
      chart: {
        type: 'column',
        height: '150'
      },
      title: {
        text: undefined
      },
      xAxis: {
        type: 'datetime',
        dateTimeLabelFormats: { // don't display the year
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
        min: 0
      },

      legend: {
        enabled: false
      },

      plotOptions: {
        series: {
          marker: {
            enabled: true,
            radius: 2.5
          }
        }
      },

      colors: ['#14b8a6', '#39F', '#06C', '#036', '#000'],

      series: [
        {
          name: key,
          data: data
        }
      ]
    });
  },

  mounted() {
    let data = JSON.parse(this.el.dataset.events);
    let key = this.el.dataset.key;

    this.chart = this.createChart(data, key);
  },

  updated() {
    console.log("Something has happened!");
    let data = JSON.parse(this.el.dataset.events);

    this.chart.series[0].setData(data)
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
