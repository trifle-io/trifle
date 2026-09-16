import test from 'node:test';
import assert from 'node:assert/strict';
import * as echarts from 'echarts';
import {
  timeseriesSeriesOptions, timeseriesYAxes, timeseriesPointValue,
  formatTimeseriesValue, timeseriesWeightedAverages, bindTimeseriesAverageLegend
} from '../js/widgets/dashboard_runtime/shared/timeseries_axes.mjs';

const format = value => String(value);
const primary = { type: 'value', min: 0, name: 'Events', nameLocation: 'middle', nameGap: 40,
  axisLabel: { color: '#777', formatter: format }, splitLine: { show: true } };

test('ordinary series stay on the primary axis and retain their chart type and stacking', () => {
  for (const [type, expected] of [['line', 'line'], ['area', 'line'], ['bar', 'bar'], ['dots', 'scatter']]) {
    const series = timeseriesSeriesOptions({ name: 'count', data: [[1, 5]] }, { chart_type: type, stacked: true }, 0);
    assert.equal(series.type, expected);
    assert.equal(series.yAxisIndex, 0);
    assert.equal(series.stack, type === 'dots' ? undefined : 'total');
    assert.equal(!!series.areaStyle, type === 'area');
    assert.equal(series.showSymbol, type === 'dots');
    assert.strictEqual(timeseriesYAxes(primary, {}, [series], format), primary);
  }
  assert.equal(timeseriesSeriesOptions({ y_axis: 'invalid' }, {}, 0).yAxisIndex, 0);
});

test('a secondary line does not inherit bars, stacking, percentages, or primary bounds', () => {
  const chart = { chart_type: 'bar', stacked: true, normalized: true, secondary_y_label: 'Avg. duration (ms)' };
  const source = { name: 'Average duration', chart_type: 'line', y_axis: 'secondary', unit: 'ms', data: [[1, 5000], [2, null]] };
  const line = timeseriesSeriesOptions(source, chart, 1);
  assert.equal(line.type, 'line');
  assert.equal(line.yAxisIndex, 1);
  assert.equal(line.stack, undefined);
  assert.equal(line.areaStyle, undefined);
  assert.deepEqual(line.data, source.data);
  const axes = timeseriesYAxes({ ...primary, max: 100 }, chart, [line], format);
  assert.equal(axes[0].max, 100);
  assert.equal(axes[1].max, undefined);
  assert.equal(axes[1].position, 'right');
  assert.equal(axes[1].name, 'Avg. duration (ms)');
  assert.equal(axes[1].splitLine.show, false);
  assert.equal(axes[1].axisLabel.formatter(5000), '5000');
  assert.equal(formatTimeseriesValue(5000, source, chart, format), '5000 ms');
  assert.equal(formatTimeseriesValue(50, {}, chart, format), '50.00%');
  assert.equal(formatTimeseriesValue(null, source, chart, format), '-');
});

test('independent axis stacks and negative secondary values are supported', () => {
  const series = timeseriesSeriesOptions({ y_axis: 'secondary', chart_type: 'bar', stacked: true, data: [[1, -5]] }, {}, 0);
  assert.equal(series.stack, 'secondary-total');
  assert.equal(timeseriesYAxes(primary, {}, [series], format)[1].min, 'dataMin');
  assert.equal(primary.min, 0);
});

const weightedChart = () => ({
  series: [
    { name: 'jobs/A', data: [[1, 10], [2, 1], [3, 0]] },
    { name: 'jobs/B', data: [[1, 1], [2, 0], [3, 0]] },
    { id: 'average', name: 'Average duration', y_axis: 'secondary', unit: 'ms', chart_type: 'line',
      data: [[1, null], [2, null], [3, null]],
      average_samples: [
        { name: 'jobs/A', data: [[1, 1000, 10], [2, 0, 1], [3, 0, 0]] },
        { name: 'jobs/B', data: [[1, 1000, 1], [2, 0, 0], [3, 0, 0]] }
      ] }
  ]
});

test('combined averages weight sample counts across paths and summary buckets', () => {
  const payload = weightedChart();
  const result = timeseriesWeightedAverages(payload);
  assert.equal(result.series[2].data[0][1], 2000 / 11);
  assert.equal(result.series[2].data[1][1], 0);
  assert.equal(result.series[2].data[2][1], null);
  assert.deepEqual(result.series[2].summary, { mean: 2000 / 12, sum: null });
  assert.equal(payload.series[2].data[0][1], null);
  assert.strictEqual(result.series[0], payload.series[0]);
  const filtered = timeseriesWeightedAverages(payload, { 'jobs/A': false });
  assert.deepEqual(filtered.series[2].data, [[1, 1000], [2, null], [3, null]]);
  const hidden = timeseriesWeightedAverages(payload, { 'jobs/A': false, 'jobs/B': false });
  assert.deepEqual(hidden.series[2].data, [[1, null], [2, null], [3, null]]);
  assert.equal(hidden.series[2].summary.mean, null);
});

test('legend changes update only the weighted line and keep expanded summary synchronized', () => {
  const handlers = new Set();
  let option, summary;
  const chart = { on: (_event, handler) => handlers.add(handler), off: (_event, handler) => handlers.delete(handler), setOption: value => { option = value; } };
  bindTimeseriesAverageLegend(chart, weightedChart(), updated => { summary = updated; });
  bindTimeseriesAverageLegend(chart, weightedChart(), updated => { summary = updated; });
  assert.equal(handlers.size, 1);
  [...handlers][0]({ selected: { 'jobs/A': false } });
  assert.deepEqual(option, { series: [{ id: 'average', data: [[1, 1000], [2, null], [3, null]] }] });
  assert.equal(summary.series[2].summary.mean, 1000);
  bindTimeseriesAverageLegend(chart, { series: [] });
  assert.equal(handlers.size, 0);
});

test('missing samples do not become zero-valued summary observations', () => {
  assert.deepEqual([[1, null], [2, 0], { value: [3, ''] }, { value: [4, 5] }]
    .map(timeseriesPointValue).filter(Number.isFinite), [0, 5]);
});

test('real ECharts click and programmatic legend actions recompute the combined line', () => {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 800, height: 300 });
  try {
    const payload = timeseriesWeightedAverages(weightedChart());
    const series = payload.series.map((source, index) => timeseriesSeriesOptions(source, payload, index));
    chart.setOption({ animation: false, xAxis: { type: 'value' }, legend: {},
      yAxis: timeseriesYAxes(primary, payload, series, format), series });
    bindTimeseriesAverageLegend(chart, payload);
    chart.dispatchAction({ type: 'legendToggleSelect', name: 'jobs/A' });
    assert.deepEqual(chart.getOption().series[2].data, [[1, 1000], [2, null], [3, null]]);
    chart.dispatchAction({ type: 'legendSelect', name: 'jobs/A' });
    assert.equal(chart.getOption().series[2].data[0][1], 2000 / 11);
    chart.dispatchAction({ type: 'legendUnSelect', name: 'jobs/B' });
    assert.equal(chart.getOption().series[2].data[0][1], 100);
  } finally { chart.dispose(); }
});

test('ECharts renders stacked event bars and a separate duration line with independent scales', () => {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 1000, height: 300 });
  try {
    const payload = { chart_type: 'bar', stacked: true, secondary_y_label: 'Avg. duration (ms)', series: [
      { name: 'Success', data: [[1000, 2], [2000, 3]] },
      { name: 'Warning', data: [[1000, 1], [2000, 2]] },
      { name: 'Average duration', chart_type: 'line', y_axis: 'secondary', data: [[1000, 5000], [2000, 4000]] }
    ] };
    const series = payload.series.map((source, index) => timeseriesSeriesOptions(source, payload, index));
    chart.setOption({ animation: false, grid: { left: 80, right: 80 }, xAxis: { type: 'time' },
      yAxis: timeseriesYAxes(primary, payload, series, format), series });
    assert.ok(chart.renderToSVGString().includes('Avg. duration (ms)'));
    assert.ok(chart.getModel().getComponent('yAxis', 0).axis.scale.getExtent()[1] < 10);
    assert.ok(chart.getModel().getComponent('yAxis', 1).axis.scale.getExtent()[1] >= 5000);
    // Resetting to a regular widget must remove the secondary axis completely.
    chart.setOption({ animation: false, xAxis: { type: 'time' }, yAxis: primary, series: [series[0]] }, true);
    assert.equal(chart.getOption().yAxis.length, 1);
  } finally { chart.dispose(); }
});
