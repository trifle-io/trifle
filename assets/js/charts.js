// The chart library, built as its own file (priv/static/assets/charts.js) so it
// downloads in parallel with app.js and stays cached across deploys that do not
// touch it. app.js reaches it through ./charts_loader.mjs.
import * as echarts from "./echarts.mjs"

window.TrifleECharts = echarts
