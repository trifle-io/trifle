import assert from 'node:assert/strict';
import test from 'node:test';
import {compactChartOptions, compactNumber, fitGaugeValue, gaugeMeasurement, gaugeComparisonColor, registerCompactChartHook} from '../js/widgets/dashboard_runtime/shared/compact_charts.mjs';

test('overview counts use shared compact notation and durations adapt units', () => {
  assert.equal(compactNumber(15_213), '15.2k');
  assert.equal(compactNumber(22_512_623), '22.5m');
  assert.equal(compactNumber(1250), '1.25k');
  assert.equal(compactNumber(0), '0');
  assert.equal(compactNumber(null), '—');
  for (const [value, number, unit] of [[null, '—', 'ms'], [0, '0', 'ms'], [125.25, '125.3', 'ms'], [999.99, '1', 's'], [4125, '4.1', 's'], [59_999, '1', 'm'], [150_000, '2.5', 'm'], [3_599_999, '1', 'h'], [5_400_000, '1.5', 'h'], [216_000_000, '2.5', 'd'], [-4125, '-4.1', 's']]) {
    assert.deepEqual(gaugeMeasurement(value, 'ms'), {value: number, unit});
  }
  const options = compactChartOptions({presentation: 'gauge', title: 'Duration', gauge: {latest: 4125, average: 150_000, unit: 'ms'}});
  assert.ok(options.tooltip.formatter().includes('Latest: 4.1 s'));
  assert.ok(options.tooltip.formatter().includes('Average: 2.5 m'));
});

test('gauge readings shrink for long numbers and narrow gauges, then regain their normal size', () => {
  const saved = globalThis.getComputedStyle;
  const label = {style: {}};
  let width = 48;
  const reading = {getBoundingClientRect: () => ({width})};
  const element = {querySelector: selector => selector === '[data-gauge-value]' ? label : reading};
  const target = {clientWidth: 120, clientHeight: 78};
  globalThis.getComputedStyle = () => ({fontSize: '24px'});
  try {
    fitGaugeValue(element, target);
    assert.equal(label.style.fontSize, '');
    width = 110;
    fitGaugeValue(element, target);
    const wideFont = parseFloat(label.style.fontSize);
    assert.ok(wideFont < 24);
    target.clientWidth = 96;
    target.clientHeight = 62;
    fitGaugeValue(element, target);
    assert.ok(parseFloat(label.style.fontSize) < wideFont);
    width = 32;
    fitGaugeValue(element, target);
    assert.equal(label.style.fontSize, '');
  } finally {
    if (saved === undefined) delete globalThis.getComputedStyle;
    else globalThis.getComputedStyle = saved;
  }
});

test('gauge scale handles zeros and fixed maxima without inventing missing values', () => {
  assert.equal(compactChartOptions({presentation: 'gauge', gauge: {average: 0, latest: 0}}).series[0].max, 1);
  const options = compactChartOptions({presentation: 'gauge', gauge: {average: 100, latest: 200, maximum: 500}});
  assert.equal(options.series[0].max, 500);
  assert.equal(options.series[0].data[0].value, 100);
  assert.equal(options.series[1].data[0].value, 200);
  const missing = compactChartOptions({presentation: 'gauge', gauge: {}});
  assert.deepEqual(missing.series[0].data, []);
  const compact = compactChartOptions({presentation: 'gauge', compact: true, show_value: false, gauge: {latest: 10}}, false, {width: 120, height: 78});
  assert.deepEqual(compact.graphic[0].shape, {x: 0, y: 0, width: 120, height: 78});
  assert.equal(compact.graphic[0].tooltip.formatter(), compact.tooltip.formatter());
});

test('comparison gauges use their supplied palette for lower, higher and equal measurements', () => {
  const comparison_colors = {lower: '#14b8a6', higher: '#ef4444', equal: '#3b82f6'};
  for (const [latest, average, expected] of [[80, 100, comparison_colors.lower], [120, 100, comparison_colors.higher], [100, 100, comparison_colors.equal], [0, 0, comparison_colors.equal], [0, 100, comparison_colors.lower]]) {
    const payload = {presentation: 'gauge', comparison_colors, gauge: {latest, average}};
    assert.equal(gaugeComparisonColor(payload), expected);
    assert.equal(compactChartOptions(payload).series[0].progress.itemStyle.color, expected);
  }
  assert.equal(gaugeComparisonColor({comparison_colors, gauge: {latest: null, average: 100}}), '#64748b');
  assert.equal(gaugeComparisonColor({gauge: {latest: 120, average: 100}}, true), '#94a3b8');
});

test('activity tooltip escapes job names and formats source timezone', () => {
  const options = compactChartOptions({presentation: 'sparkline', timezone: 'Asia/Dubai', series: []});
  const html = options.tooltip.formatter([{seriesName: '<script>bad</script>', value: [Date.UTC(2026, 0, 1), 2]}]);
  assert.ok(html.includes('&lt;script&gt;'));
  assert.ok(html.includes('4:00'));
  assert.ok(!html.includes('<script>'));
});

test('compact chart types preserve line, area and bar behavior and render Dots as visible scatter', () => {
  const data = [[1, 2], [2, 3]];
  for (const [chart_type, expected] of [['line', 'line'], ['area', 'line'], ['bar', 'bar'], ['dots', 'scatter'], ['Dots', 'scatter']]) {
    const options = compactChartOptions({presentation: 'sparkline', chart_type, stacked: true, series: [{name: 'Events', data}]});
    const [series] = options.series;
    const dots = expected === 'scatter';
    assert.equal(series.type, expected);
    assert.equal(series.showSymbol, dots);
    assert.equal(series.stack, dots ? undefined : 'activity');
    assert.deepEqual(series.areaStyle, chart_type === 'area' ? {opacity: 0.15} : undefined);
    assert.deepEqual(series.data, data);
    if (dots) {
      assert.equal(series.symbol, 'circle');
      assert.equal(series.symbolSize, 5);
    }
  }
  const mixed = compactChartOptions({presentation: 'sparkline', chart_type: 'bar', series: [{chart_type: 'dots', data}]}).series[0];
  assert.equal(mixed.type, 'scatter');
  assert.equal(mixed.showSymbol, true);
});

test('compact tooltips escape the chart frame, follow the pointer and stay inside the viewport', () => {
  const saved = globalThis.window;
  globalThis.window = {innerWidth: 1000, innerHeight: 700};
  let origin = {left: 100, top: 100};
  const element = {getBoundingClientRect: () => origin};
  const dimensions = {viewSize: [200, 78], contentSize: [300, 120]};
  try {
    for (const presentation of ['gauge', 'sparkline']) {
      const {tooltip} = compactChartOptions({presentation}, false, undefined, element);
      assert.equal(tooltip.appendTo, 'body');
      assert.equal(tooltip.confine, false);
      assert.equal(tooltip.transitionDuration, 0);
      assert.deepEqual(tooltip.position([20, 30], null, null, null, dimensions), [32, 42]);
      assert.deepEqual(tooltip.position([80, 40], null, null, null, dimensions), [92, 52]);
      // Re-read chart position after scrolling, and flip away from viewport edges.
      origin = {left: 850, top: 600};
      const [x, y] = tooltip.position([100, 50], null, null, null, dimensions);
      assert.ok(origin.left + x >= 8 && origin.left + x + 300 <= 992);
      assert.ok(origin.top + y >= 8 && origin.top + y + 120 <= 692);
      // A tooltip wider than its chart must also remain visible at the left edge.
      origin = {left: 0, top: 0};
      assert.deepEqual(tooltip.position([0, 0], null, null, null, dimensions), [12, 12]);
      origin = {left: 100, top: 100};
    }
  } finally {
    if (saved === undefined) delete globalThis.window;
    else globalThis.window = saved;
  }
});

test('overview defers invisible charts, updates instances and disposes on theme change and removal', () => {
  const saved = Object.fromEntries(['window', 'document', 'ResizeObserver', 'IntersectionObserver'].map(k => [k, globalThis[k]]));
  const listeners = new Map(); const renderedOptions = []; let dark = false; let created = 0; let disposed = 0;
  globalThis.window = {addEventListener: (k, fn) => listeners.set(k, fn), removeEventListener: k => listeners.delete(k)};
  globalThis.document = {documentElement: {classList: {contains: () => dark}}};
  globalThis.ResizeObserver = class {constructor(fn) {this.fn = fn;} observe() {} disconnect() {this.disconnected = true;}};
  globalThis.IntersectionObserver = class {constructor(fn) {this.fn = fn;} observe() {} disconnect() {this.disconnected = true;}};
  const target = {clientWidth: 180, clientHeight: 80};
  const Hooks = {};
  registerCompactChartHook(Hooks, {withChartOpts: () => ({}), echarts: {init: () => {created++; return {getDom: () => target, setOption(options) {renderedOptions.push(options);}, resize() {}, dispose() {disposed++;}};}}});
  const hook = {...Hooks.CompactChart, el: {dataset: {chart: JSON.stringify({presentation: 'gauge', compact: true, gauge: {latest: 10}})}, querySelector: () => target}};
  try {
    hook.mounted(); assert.equal(created, 0);
    hook.viewport.fn([{isIntersecting: true}]); assert.equal(created, 1);
    hook.updated(); assert.equal(created, 1);
    assert.equal(renderedOptions.length, 1);
    const originalCenter = renderedOptions[0].series[0].center[1];
    target.clientHeight -= 16;
    hook.resize.fn();
    assert.equal(created, 1);
    assert.equal(renderedOptions.length, 2);
    assert.equal(renderedOptions[1].series[0].center[1], originalCenter - 16);
    dark = true; listeners.get('trifle:theme-changed')(); assert.equal(created, 2); assert.equal(disposed, 1);
    hook.destroyed(); assert.equal(disposed, 2); assert.equal(listeners.size, 0);
    assert.ok(hook.resize.disconnected); assert.ok(hook.viewport.disconnected);
  } finally { for (const [k, value] of Object.entries(saved)) {if (value === undefined) delete globalThis[k]; else globalThis[k] = value;} }
});
