import assert from 'node:assert/strict';
import test from 'node:test';
import * as echarts from 'echarts';
import {timeseriesTimeFormatters} from '../js/widgets/dashboard_runtime/shared/timeseries_timezone.mjs';

test('widgets without a source timezone keep existing defaults', () => {
  for (const timezone of [undefined, null, '', 'Invalid/Timezone']) {
    assert.equal(timeseriesTimeFormatters(timezone), null);
  }
});

test('both chart sizes format bucket labels and tooltips in the source timezone', () => {
  const at = Date.parse('2026-09-12T23:00:00Z');
  const utc = timeseriesTimeFormatters('Etc/UTC');
  const dubai = timeseriesTimeFormatters('Asia/Dubai');
  assert.equal(utc.axis(at), '23:00');
  assert.equal(dubai.axis(at), '03:00');
  assert.equal(dubai.tooltip(at), '2026-09-13 03:00:00');
});

test('source timezone formatting respects daylight saving and midnight', () => {
  const newYork = timeseriesTimeFormatters('America/New_York');
  assert.equal(newYork.axis(Date.parse('2026-03-08T06:00:00Z')), '01:00');
  assert.equal(newYork.axis(Date.parse('2026-03-08T07:00:00Z')), '03:00');
  assert.equal(newYork.tooltip(Date.parse('2026-11-01T05:30:00Z')), '2026-11-01 01:30:00');
  assert.equal(newYork.tooltip(Date.parse('2026-11-01T06:30:00Z')), '2026-11-01 01:30:00');
  const utc = timeseriesTimeFormatters('Etc/UTC');
  assert.equal(utc.axis(Date.parse('2026-09-13T00:00:00Z')), '13');
  assert.equal(utc.tooltip(Date.parse('2026-09-13T00:00:00Z')), '2026-09-13 00:00:00');
});

test('adaptive labels retain the standard day, month and year styles', () => {
  const utc = timeseriesTimeFormatters('Etc/UTC');
  for (const [time, expected] of [
    ['2026-01-01T00:00:00Z', '2026'],
    ['2026-09-01T00:00:00Z', 'Sep'],
    ['2026-09-13T00:00:00Z', '13'],
    ['2026-09-13T12:30:00Z', '12:30'],
    ['2026-09-13T12:30:45Z', '12:30:45'],
    ['2026-09-13T12:30:45.123Z', '12:30:45 123']
  ]) assert.equal(utc.axis(Date.parse(time)), expected);
});

test('fractional timezone offsets and tooltip precision preserve the source clock', () => {
  const nepal = timeseriesTimeFormatters('Asia/Kathmandu');
  const at = Date.parse('2026-12-31T23:00:00.123Z');
  assert.equal(nepal.tooltip(at, '2026-12-31'), '2027-01-01');
  assert.equal(nepal.tooltip(at, '2026-12-31 23:00:00'), '2027-01-01 04:45:00');
  assert.equal(nepal.tooltip(at, '2026-12-31 23:00:00 123'), '2027-01-01 04:45:00 123');
});

test('source-timezone labels exactly match real ECharts defaults when clocks agree', () => {
  const localTimezone = new Intl.DateTimeFormat().resolvedOptions().timeZone;
  const ranges = [
    ['2026-09-12T12:00:00Z', 500],
    ['2026-09-12T12:00:00Z', 60_000],
    ['2026-09-12T00:00:00Z', 86_400_000],
    ['2026-09-12T00:00:00Z', 2 * 86_400_000],
    ['2026-09-12T00:00:00Z', 7 * 86_400_000],
    ['2026-01-01T00:00:00Z', 365 * 86_400_000],
    ['2026-01-01T00:00:00Z', 5 * 365 * 86_400_000]
  ];

  for (const width of [500, 1200]) {
    for (const [start, span] of ranges) {
      const from = Date.parse(start);
      const points = [[from, 1], [from + span, 2]];
      const formatters = timeseriesTimeFormatters(localTimezone);
      const charts = [undefined, formatters.axis].map(formatter => {
        const chart = echarts.init(null, null, {renderer: 'svg', ssr: true, width, height: 300});
        chart.setOption({
          animation: false,
          xAxis: {type: 'time', axisLabel: formatter ? {formatter} : {}},
          yAxis: {},
          series: [{type: 'bar', data: points}]
        });
        return chart;
      });

      try {
        const axes = charts.map(chart => chart.getModel().getComponent('xAxis').axis);
        const labels = axes.map(axis => axis.getViewLabels().map(label => label.formattedLabel));
        assert.ok(labels[0].length > 0);
        assert.deepEqual(labels[1], labels[0], `${start}, span=${span}, width=${width}`);

        for (const [at] of points) {
          const defaultLabel = axes[0].scale.getLabel({value: at});
          assert.equal(formatters.tooltip(at, defaultLabel), defaultLabel);
        }

        assert.deepEqual(charts[1].getOption().series[0].data, points);
      } finally {
        charts.forEach(chart => chart.dispose());
      }
    }
  }
});
