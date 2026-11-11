// Renders a fixed set of chart options to SVG strings with either the full
// ECharts build or the app's trimmed build, and prints them as JSON.
//
// Run in a separate process per build: `echarts.use` registers globally, so
// importing both builds in one process would make them indistinguishable.
//
//   node echarts_render.mjs full|trimmed
const build = process.argv[2];

// ECharts reports a missing component or feature with console output, not an
// exception. Collect it so the test can fail on it.
const warnings = [];
for (const level of ["log", "warn", "error"]) {
  console[level] = (...args) => warnings.push(args.map(String).join(" "));
}
const echarts =
  build === "full" ? await import("echarts") : await import("../../js/echarts.mjs");

const hours = (n) => Array.from({ length: n }, (_, i) => Date.UTC(2026, 0, 1, i));
const wave = (n, k = 1) => Array.from({ length: n }, (_, i) => Math.round(50 + 40 * Math.sin(i / k)));
const timeData = (n, k) => hours(n).map((t, i) => [t, wave(n, k)[i]]);
const font = { fontFamily: "sans-serif" };

// One entry per option shape the app builds. Keep in step with the renderers in
// assets/js/widgets and the hooks in assets/js/app.js.
export const options = {
  timeseries_line_with_overlays: {
    animation: false,
    textStyle: font,
    grid: { top: 12, bottom: 36, left: 56, right: 24, containLabel: true },
    legend: { show: true, type: "scroll", bottom: 6, data: ["a", "b"] },
    tooltip: { trigger: "axis", axisPointer: { type: "line", lineStyle: { type: "dashed" } } },
    axisPointer: { link: [{ xAxisIndex: "all" }] },
    xAxis: { type: "time", axisLine: { lineStyle: { color: "#e2e8f0" } } },
    yAxis: [{ type: "value" }, { type: "value", position: "right" }],
    series: [
      {
        name: "a",
        type: "line",
        showSymbol: false,
        data: timeData(24, 3),
        lineStyle: { width: 2 },
        areaStyle: { opacity: 0.18 },
        markLine: {
          silent: true,
          symbol: "none",
          data: [{ yAxis: 70, label: { formatter: "target", backgroundColor: "#fff" } }],
        },
        markArea: {
          silent: true,
          data: [[{ xAxis: hours(24)[4] }, { xAxis: hours(24)[8] }]],
        },
        markPoint: { data: [{ type: "max", name: "max" }] },
      },
      { name: "b", type: "line", yAxisIndex: 1, data: timeData(24, 5), emphasis: { focus: "series" } },
    ],
  },
  timeseries_stacked_bars: {
    animation: false,
    textStyle: font,
    grid: { top: 16, left: 52, right: 16, bottom: 40 },
    legend: { show: true, bottom: 6 },
    tooltip: { trigger: "axis", axisPointer: { type: "shadow" } },
    xAxis: { type: "time" },
    yAxis: { type: "value", splitLine: { lineStyle: { type: "dashed" } } },
    series: ["x", "y", "z"].map((name, i) => ({
      name,
      type: "bar",
      stack: "total",
      data: timeData(12, i + 2),
      itemStyle: { opacity: 1 },
    })),
  },
  category_bar: {
    animation: false,
    textStyle: font,
    grid: { top: 20, bottom: 40, left: 80, right: 36 },
    tooltip: { trigger: "axis", appendToBody: true },
    xAxis: { type: "category", data: ["alpha", "beta", "gamma", "delta"] },
    yAxis: { type: "value" },
    series: [{ type: "bar", data: [12, 30, 7, 19].map((value, i) => ({ value, itemStyle: { color: ["#14b8a6", "#3b82f6", "#f59e0b", "#ef4444"][i] } })) }],
  },
  category_horizontal_bar: {
    animation: false,
    grid: { top: 0, bottom: 0, left: 0, right: 0, containLabel: false },
    xAxis: { type: "value", show: false, min: 0, max: 40 },
    yAxis: { type: "category", show: false, data: [""] },
    series: [{ type: "bar", data: [28], stack: "s", select: { disabled: true } }],
  },
  category_pie_and_donut: {
    animation: false,
    textStyle: font,
    legend: { show: true },
    tooltip: { trigger: "item" },
    series: [
      {
        type: "pie",
        radius: ["40%", "65%"],
        label: { color: "#334155" },
        labelLine: { lineStyle: { color: "#94a3b8" } },
        data: [
          { name: "alpha", value: 12 },
          { name: "beta", value: 30 },
          { name: "gamma", value: 7 },
        ],
      },
    ],
  },
  distribution_scatter: {
    animation: false,
    textStyle: font,
    grid: { top: 16, left: 64, right: 16, bottom: 40 },
    tooltip: { trigger: "item" },
    xAxis: { type: "category", data: ["0-10", "10-20", "20-30"] },
    yAxis: { type: "category", data: ["low", "mid", "high"] },
    series: [{ type: "scatter", symbolSize: (v) => 6 + v[2], data: [[0, 0, 4], [1, 1, 9], [2, 2, 2], [1, 2, 6]] }],
  },
  distribution_heatmap_with_scale: {
    animation: false,
    textStyle: font,
    grid: { top: 16, left: 64, right: 16, bottom: 64 },
    tooltip: { trigger: "item" },
    xAxis: { type: "category", data: ["0-10", "10-20", "20-30"], splitArea: { show: true } },
    yAxis: { type: "category", data: ["low", "mid", "high"], splitArea: { show: true } },
    visualMap: { min: 0, max: 10, calculable: true, orient: "horizontal", left: "center", bottom: 6 },
    series: [
      {
        type: "heatmap",
        label: { show: true },
        data: [[0, 0, 4], [1, 1, 9], [2, 2, 2], [1, 2, 6], [0, 2, 1]],
        emphasis: { itemStyle: { borderColor: "#000", borderWidth: 1 } },
        select: { itemStyle: { borderColor: "#000" } },
      },
    ],
  },
  kpi_sparkline: {
    animation: false,
    backgroundColor: "transparent",
    grid: { top: 2, bottom: 2, left: 0, right: 0, containLabel: false },
    xAxis: { type: "time", show: false },
    yAxis: { type: "value", show: false },
    tooltip: { show: false },
    series: [{ type: "line", showSymbol: false, data: timeData(24, 2), lineStyle: { width: 1 }, areaStyle: { opacity: 0.08 } }],
  },
  empty_state_graphic: {
    animation: false,
    xAxis: { type: "time", show: false },
    yAxis: { type: "value", show: false },
    tooltip: { show: false },
    series: [{ type: "line", data: [], silent: true }],
    graphic: [{ type: "text", left: "center", top: "middle", style: { text: "No data", fill: "#64748b", font: "14px sans-serif" } }],
    title: { text: "Requests", left: "center", textStyle: { fontSize: 12 } },
  },
};

const rendered = {};
for (const [name, option] of Object.entries(options)) {
  const chart = echarts.init(null, null, { renderer: "svg", ssr: true, width: 640, height: 360 });
  chart.setOption(option);
  rendered[name] = chart.renderToSVGString();
  chart.dispose();
}

const api = ["init", "connect", "disconnect", "getInstanceByDom", "use"].map((name) => [name, typeof echarts[name]]);
api.push(["format.formatTime", typeof (echarts.format && echarts.format.formatTime)]);

process.stdout.write(JSON.stringify({ rendered, api, warnings }));
