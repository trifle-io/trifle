import assert from 'node:assert/strict';
import test from 'node:test';
import * as echarts from 'echarts';
import {timeseriesIdentity, timeseriesLabels, timeseriesTooltipName} from '../js/widgets/dashboard_runtime/shared/timeseries_identity.mjs';

test('ordinary dashboard widgets retain their default series names', () => {
  assert.deepEqual(timeseriesIdentity({name: 'Orders'}, 0), {name: 'Orders'});
  assert.deepEqual(timeseriesIdentity({}, 2), {name: 'Series 3'});
  assert.equal(timeseriesTooltipName({seriesName: 'Orders'}, new Map()), 'Orders');
});

test('one legend name groups all states while tooltip labels and IDs stay distinct', () => {
  const path = 'jobs/App.Worker';
  const series = ['success', 'warning', 'error', 'running'].map(state => ({
    id: JSON.stringify([path, state]), name: `${path} · ${state}`, legend_name: path
  }));
  const identities = series.map(timeseriesIdentity);
  assert.equal(new Set(identities.map(item => item.name)).size, 1);
  assert.equal(new Set(identities.map(item => item.id)).size, 4);
  const labels = timeseriesLabels(series);
  for (const item of identities) {
    assert.equal(timeseriesTooltipName({seriesId: item.id, seriesName: path}, labels), labels.get(item.id));
  }
});

test('literal path punctuation and state-like suffixes cannot collide', () => {
  const names = ['jobs/App.Worker', 'jobs/*', 'jobs/東京.rb', 'jobs/App.Worker · Warning'];
  const series = names.map(name => ({id: JSON.stringify([name, 'warning']), name: `${name} · Warning`, legend_name: name}));
  assert.deepEqual(series.map(timeseriesIdentity).map(item => item.name), names);
  assert.equal(timeseriesLabels(series).size, names.length);
});

test('ECharts legend toggles remove every state of a path without hiding other paths', () => {
  const items = [
    {id: 'a-success', name: 'jobs/A · Success', legend_name: 'jobs/A', color: '#14b8a6', data: [2]},
    {id: 'a-warning', name: 'jobs/A · Warning', legend_name: 'jobs/A', color: '#f97316', data: [1]},
    {id: 'b-running', name: 'jobs/B · Running', legend_name: 'jobs/B', color: '#3b82f6', data: [3]}
  ];
  const chart = echarts.init(null, null, {renderer: 'svg', ssr: true, width: 600, height: 400});
  try {
    chart.setOption({
      animation: false, legend: {data: ['jobs/A', 'jobs/B']}, xAxis: {type: 'category', data: ['now']}, yAxis: {},
      series: items.map((item, index) => ({...timeseriesIdentity(item, index), type: 'bar', stack: 'total', data: item.data, itemStyle: {color: item.color}}))
    });
    const before = chart.renderToSVGString();
    assert.ok(before.includes('#14b8a6') && before.includes('#f97316') && before.includes('#3b82f6'));
    chart.dispatchAction({type: 'legendToggleSelect', name: 'jobs/A'});
    const after = chart.renderToSVGString();
    assert.ok(!after.includes('#14b8a6') && !after.includes('#f97316'));
    assert.ok(after.includes('#3b82f6'));
    chart.dispatchAction({type: 'legendToggleSelect', name: 'jobs/A'});
    assert.ok(chart.renderToSVGString().includes('#f97316'));
  } finally {
    chart.dispose();
  }
});
