import { timeseriesIdentity } from './timeseries_identity.mjs';

// Series opt in to a right-hand axis. Existing widget/form payloads stay on axis 0.
export const timeseriesAxisIndex = (series) => series?.y_axis === 'secondary' ? 1 : 0;

export const timeseriesSeriesOptions = (series, chart, index) => {
  const axis = timeseriesAxisIndex(series);
  const type = String(series.chart_type || chart.chart_type || 'line').toLowerCase();
  const dots = type === 'dots';
  const stacked = typeof series.stacked === 'boolean' ? series.stacked : axis === 0 && !!chart.stacked;
  return {
    ...timeseriesIdentity(series, index),
    type: type === 'bar' ? 'bar' : dots ? 'scatter' : 'line',
    yAxisIndex: axis,
    data: Array.isArray(series.data) ? series.data : [],
    showSymbol: dots || (axis === 1 && type !== 'bar'),
    ...(axis === 1 && type !== 'bar' ? { symbolSize: 4 } : {}),
    ...(dots ? { symbol: 'circle', symbolSize: 5 } : {}),
    ...(stacked && !dots ? { stack: axis === 0 ? 'total' : 'secondary-total' } : {}),
    ...(type === 'area' ? { areaStyle: { opacity: 0.1 } } : {}),
    ...(axis === 1 ? { z: 5 } : {})
  };
};

export const timeseriesPointValue = (point) => {
  const raw = Array.isArray(point) ? point[1]
    : point && typeof point === 'object' ? (Array.isArray(point.value) ? point.value[1] : point.value)
    : point;
  if (raw == null || raw === '') return null;
  const value = Number(raw);
  return Number.isFinite(value) ? value : null;
};

export const timeseriesYAxes = (primary, chart, series, formatNumber) => {
  const secondarySeries = series.filter(item => item.yAxisIndex === 1);
  if (!secondarySeries.length) return primary;
  let min = 0;
  secondarySeries.forEach(item => (item.data || []).forEach(point => {
    const value = timeseriesPointValue(point);
    if (value != null) min = Math.min(min, value);
  }));

  // Do not inherit primary percentage limits, alert bounds, or grid lines.
  const secondary = {
    type: 'value',
    position: 'right',
    min: min < 0 ? 'dataMin' : 0,
    name: chart.secondary_y_label || '',
    nameLocation: primary.nameLocation,
    nameGap: primary.nameGap,
    nameTextStyle: primary.nameTextStyle,
    axisLine: primary.axisLine,
    axisLabel: { ...primary.axisLabel, formatter: formatNumber },
    splitLine: { show: false }
  };
  return [{ ...primary, position: 'left' }, secondary];
};

export const formatTimeseriesValue = (value, series, chart, formatNumber) => {
  if (value == null || value === '') return '-';
  const number = Number(value);
  if (!Number.isFinite(number)) return '-';
  if (chart.normalized && timeseriesAxisIndex(series) === 0) return `${number.toFixed(2)}%`;
  const unit = typeof series?.unit === 'string' ? series.unit : '';
  return `${formatNumber(number)}${unit ? ` ${unit}` : ''}`;
};

// Optional sample data keeps averages weighted when legend groups are hidden.
// Missing samples produce gaps; zero milliseconds is still a valid observation.
export const timeseriesWeightedAverages = (chart, selected = {}) => ({
  ...chart,
  series: (chart.series || []).map(series => {
    if (!Array.isArray(series.average_samples)) return series;
    const buckets = new Map((series.data || []).map(([at]) => [at, { sum: 0, count: 0 }]));
    let total = 0;
    let count = 0;
    series.average_samples.filter(source => selected[source.name] !== false).forEach(source => {
      (source.data || []).forEach(([at, sum, size]) => {
        if (!Number.isFinite(sum) || !Number.isFinite(size) || size <= 0) return;
        const bucket = buckets.get(at);
        if (!bucket) return;
        bucket.sum += sum;
        bucket.count += size;
        total += sum;
        count += size;
      });
    });
    return {
      ...series,
      data: Array.from(buckets, ([at, bucket]) => [at, bucket.count > 0 ? bucket.sum / bucket.count : null]),
      summary: { mean: count > 0 ? total / count : null, sum: null }
    };
  })
});

export const bindTimeseriesAverageLegend = (chart, data, onUpdate = () => {}) => {
  const events = ['legendselectchanged', 'legendselected', 'legendunselected'];
  if (chart.__tsAverageLegend) events.forEach(event => chart.off(event, chart.__tsAverageLegend));
  chart.__tsAverageLegend = null;
  if (!(data.series || []).some(series => Array.isArray(series.average_samples))) return;
  const handler = event => {
    const updated = timeseriesWeightedAverages(data, event.selected || {});
    chart.setOption({ series: updated.series
      .filter(series => Array.isArray(series.average_samples))
      .map(series => ({ id: String(series.id), data: series.data })) });
    onUpdate(updated);
  };
  chart.__tsAverageLegend = handler;
  events.forEach(event => chart.on(event, handler));
};
