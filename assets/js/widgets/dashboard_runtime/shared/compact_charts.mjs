import { timeseriesTimeFormatters } from "./timeseries_timezone.mjs";
import { formatCompactNumber, formatCompactDuration } from "../../../utils/formatting.mjs";

const numeric = value => typeof value === 'number' && Number.isFinite(value);
export const compactNumber = value => numeric(value) ? formatCompactNumber(value).toLowerCase() : '—';
export const gaugeMeasurement = (value, unit = '') => unit === 'ms' ? formatCompactDuration(value) : {value: compactNumber(value), unit};
const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const dateLabel = (at, timezone) => {
  try { return new Intl.DateTimeFormat('en', {timeZone: timezone || 'UTC', dateStyle: 'short', timeStyle: 'short'}).format(new Date(at)); } catch (_) { return ''; }
};

// Tiny charts cannot contain a readable tooltip. Render outside GridStack and
// position against the viewport while returning ECharts' local coordinates.
const compactTooltip = element => ({
  appendTo: 'body',
  confine: false,
  transitionDuration: 0,
  showDelay: 0,
  extraCssText: 'max-width:calc(100vw - 16px);white-space:normal;overflow-wrap:anywhere;',
  position(point, _params, _dom, _rect, size) {
    const origin = element?.getBoundingClientRect?.() || {left: 0, top: 0};
    const width = globalThis.window?.innerWidth || size.viewSize[0];
    const height = globalThis.window?.innerHeight || size.viewSize[1];
    const [tooltipWidth, tooltipHeight] = size.contentSize;
    const cursorX = origin.left + point[0];
    const cursorY = origin.top + point[1];
    let left = cursorX + 12;
    let top = cursorY + 12;
    if (left + tooltipWidth > width - 8) left = cursorX - tooltipWidth - 12;
    if (top + tooltipHeight > height - 8) top = cursorY - tooltipHeight - 12;
    left = Math.max(8, Math.min(left, width - tooltipWidth - 8));
    top = Math.max(8, Math.min(top, height - tooltipHeight - 8));
    return [left - origin.left, top - origin.top];
  }
});

export function gaugeComparisonColor(payload, dark = false) {
  const {average, latest} = payload.gauge || {};
  const colors = payload.comparison_colors;
  const fallback = dark ? '#94a3b8' : '#64748b';
  if (!colors || !numeric(average) || !numeric(latest)) return fallback;
  const comparison = latest < average ? 'lower' : latest > average ? 'higher' : 'equal';
  return colors[comparison] || fallback;
}

export function fitGaugeValue(element, target) {
  const label = element.querySelector('[data-gauge-value]');
  const reading = element.querySelector('[data-gauge-reading]');
  if (!label?.style || !reading?.getBoundingClientRect || typeof getComputedStyle !== 'function') return;
  label.style.fontSize = '';
  const fontSize = parseFloat(getComputedStyle(label).fontSize);
  const width = Math.max(reading.scrollWidth || 0, reading.getBoundingClientRect().width);
  if (!fontSize || !width) return;
  // The full icon/value row must fit inside the arc at the top of the text.
  const innerRadius = Math.max(0, Math.min(target.clientWidth, target.clientHeight) * 0.65 - 8);
  const fittedSize = Math.min(fontSize, 2 * innerRadius / Math.sqrt((width / fontSize) ** 2 + 4));
  if (fittedSize < fontSize) label.style.fontSize = `${fittedSize}px`;
}

export function compactChartOptions(payload, dark = false, size = {width: 120, height: 78}, element) {
  const text = dark ? '#cbd5e1' : '#334155';
  if (payload.presentation === 'proportion') {
    const neutral = dark ? '#334155' : '#e2e8f0';
    const radius = Math.min(size.width, size.height) * 0.46;
    const shape = {cx: size.width / 2, cy: size.height / 2, r: radius};
    const segments = (payload.segments || []).filter(segment => numeric(segment.value) && segment.value > 0);
    const background = {type: 'circle', silent: true, shape, style: {fill: neutral}};
    const outline = {type: 'circle', silent: true, shape, style: {fill: 'transparent', stroke: payload.outline_color || '#14b8a6', lineWidth: 1.5}};
    if (payload.layout === 'pie') {
      return {animation: false, backgroundColor: 'transparent', tooltip: {show: false},
        graphic: [{...background, z: 0}, {...outline, z: 3}],
        series: [{type: 'pie', radius, center: [shape.cx, shape.cy], silent: true, showEmptyCircle: false,
          label: {show: false}, labelLine: {show: false}, emphasis: {disabled: true},
          data: segments.map(segment => ({name: segment.name, value: segment.value,
            itemStyle: {color: segment.color || neutral, opacity: segment.color ? 0.55 : 1}}))}]
      };
    }
    const total = segments.reduce((sum, segment) => sum + segment.value, 0);
    let bottom = shape.cy + radius;
    const bands = segments.map(segment => {
      const height = radius * 2 * segment.value / total;
      bottom -= height;
      return {type: 'rect', silent: true, shape: {x: shape.cx - radius, y: bottom, width: radius * 2, height},
        style: {fill: segment.color || neutral, opacity: segment.color ? 0.55 : 1}};
    });
    return {animation: false, backgroundColor: 'transparent', tooltip: {show: false}, graphic: [
      background,
      {type: 'group', silent: true, clipPath: {type: 'circle', shape}, children: bands},
      outline
    ]};
  }
  // Leave one label row below the arc endpoints and use the same bounds for activity.
  const baseline = size.height - 16;
  const radius = Math.min(size.width, size.height) * 0.65;
  if (payload.presentation === 'gauge') {
    const {average, latest, unit = '', maximum, latest_at} = payload.gauge || {};
    const latestLabel = gaugeMeasurement(latest, unit);
    const averageLabel = gaugeMeasurement(average, unit);
    const labelText = label => `${escape(label.value)}${label.unit ? ' ' + escape(label.unit) : ''}`;
    const formatter = () => `${payload.title ? '<strong>' + escape(payload.title) + '</strong><br/>' : ''}Latest: ${labelText(latestLabel)}<br/>Average: ${labelText(averageLabel)}${latest_at != null ? '<br/>' + escape(dateLabel(latest_at, payload.timezone)) : ''}`;
    const max = numeric(maximum) && maximum > 0 ? maximum : Math.max(1, 1.2 * Math.max(average || 0, latest || 0));
    const valueColor = gaugeComparisonColor(payload, dark);
    const marker = Math.max(0, Math.min(1, (latest || 0) / max));
    const base = {type: 'gauge', min: 0, max, startAngle: 180, endAngle: 0, center: ['50%', payload.compact ? baseline : '70%'], radius: payload.compact ? radius : '94%', splitLine: {show: false}, axisTick: {show: false}, axisLabel: {show: false}, anchor: {show: false}, title: {show: false}, detail: {show: false}, animation: false};
    return {animation: false, backgroundColor: 'transparent', tooltip: {...compactTooltip(element), formatter}, series: [
      {...base, axisLine: {lineStyle: {width: 6, color: [[1, dark ? '#334155' : '#e2e8f0']]}}, progress: {show: numeric(average), width: 6, itemStyle: {color: valueColor}}, pointer: {show: false}, data: numeric(average) ? [{value: average}] : []},
      {...base, axisLine: {show: numeric(latest), lineStyle: {width: 10, color: [[Math.max(0, marker - 0.012), 'transparent'], [Math.min(1, marker + 0.012), text], [1, 'transparent']]}}, pointer: {show: false}, data: numeric(latest) ? [{value: latest}] : []}
    ], graphic: [
      // Keep the comparison readable when hovering the value or empty arc interior.
      ...(payload.compact ? [{type: 'rect', z: 100, cursor: 'default',
        shape: {x: 0, y: 0, width: size.width, height: size.height},
        style: {fill: 'transparent'}, tooltip: {formatter}}] : []),
      ...(payload.show_value === false ? [] : [
      {type: 'text', left: 'center', top: payload.compact ? '52%' : '44%', style: {text: `${latestLabel.value}${latestLabel.unit ? '{unit| ' + latestLabel.unit + '}' : ''}`, fill: payload.comparison_colors ? valueColor : text, font: payload.compact ? '600 22px sans-serif' : '600 16px sans-serif', rich: {unit: {fontSize: payload.compact ? 13 : 11, fontWeight: 500, fill: text}}}}
      ])
    ]};
  }
  const axes = payload.axes === true;
  const axisColor = dark ? '#475569' : '#cbd5e1';
  const labelColor = dark ? '#94a3b8' : '#64748b';
  const timeFormatters = axes ? timeseriesTimeFormatters(payload.timezone) : null;
  const grid = axes && payload.compact
    ? {left: 2, right: 6, top: baseline - radius, bottom: 16, containLabel: false}
    : axes ? {left: 2, right: 6, top: 6, bottom: 2, containLabel: true} : {left: 0, right: 0, top: 3, bottom: 2};
  return {animation: false, backgroundColor: 'transparent', grid,
    tooltip: {...compactTooltip(element), trigger: 'axis', formatter: items => {
      const at = items[0]?.value?.[0];
      return escape(dateLabel(at, payload.timezone)) + items.map(item => `<br/>${escape(item.seriesName)}: ${escape(compactNumber(item.value?.[1]))}`).join('');
    }},
    xAxis: {type: 'time', show: axes, splitNumber: 2, axisLine: {show: true, lineStyle: {color: axisColor}}, axisTick: {show: false}, axisLabel: {fontSize: 10, lineHeight: 12, color: labelColor, hideOverlap: true, margin: payload.compact ? 4 : 6, ...(timeFormatters ? {formatter: timeFormatters.axis} : {})}, splitLine: {show: false}},
    yAxis: {type: 'value', show: axes, min: 0, minInterval: 1, splitNumber: 2, axisLine: {show: true, lineStyle: {color: axisColor}}, axisTick: {show: false}, axisLabel: {show: payload.y_labels !== false, fontSize: 10, color: labelColor, hideOverlap: true, margin: 5, formatter: compactNumber}, splitLine: {show: axes, lineStyle: {color: axisColor, opacity: 0.35, type: 'dashed'}}},
    series: (payload.series || []).map((s, i) => {
      const type = String(s.chart_type || payload.chart_type || 'line').toLowerCase();
      const dots = type === 'dots';
      return {name: s.name, type: type === 'bar' ? 'bar' : dots ? 'scatter' : 'line', stack: payload.stacked && !dots ? 'activity' : undefined,
        data: s.data, showSymbol: dots, ...(dots ? {symbol: 'circle', symbolSize: 5} : {}),
        connectNulls: false, lineStyle: {width: 1.5}, itemStyle: {color: s.color || ['#14b8a6','#f59e0b','#f43f5e','#6366f1','#94a3b8'][i % 5]}, areaStyle: type === 'area' ? {opacity: 0.15} : undefined};
    })};
}

// The standalone overview uses the same options as the dashboard renderer.
export function registerCompactChartHook(Hooks, {echarts, withChartOpts}) {
  Hooks.CompactChart = {
    mounted() {
      this.near = !globalThis.IntersectionObserver;
      this.draw = () => {
        if (!this.near) return;
        const target = this.el.querySelector('[data-compact-canvas]');
        if (!target || !target.clientWidth || !target.clientHeight) return;
        const dark = document.documentElement.classList.contains('dark');
        if (this.chart && (this.dark !== dark || this.chart.getDom() !== target)) { this.chart.dispose(); this.chart = null; this.payloadKey = null; }
        this.dark = dark;
        const payload = JSON.parse(this.el.dataset.chart);
        const value = this.el.querySelector('[data-compact-value]');
        if (value && payload.presentation === 'gauge') {
          const label = gaugeMeasurement(payload.gauge?.latest, payload.gauge?.unit);
          value.textContent = label.value;
          const unit = this.el.querySelector('[data-compact-unit]');
          if (unit) unit.textContent = label.unit;
          if (value.style) value.style.color = gaugeComparisonColor(payload, dark);
          fitGaugeValue(this.el, target);
        }
        if (!this.chart) this.chart = echarts.init(target, dark ? 'dark' : undefined, withChartOpts());
        const size = {width: target.clientWidth, height: target.clientHeight};
        const sizeKey = payload.compact || payload.presentation === 'proportion' ? `${size.width}x${size.height}` : '';
        if (this.payloadKey !== this.el.dataset.chart || this.sizeKey !== sizeKey) {
          this.chart.setOption(compactChartOptions(payload, dark, size, target), {notMerge: true});
          this.payloadKey = this.el.dataset.chart;
          this.sizeKey = sizeKey;
        }
        this.chart.resize();
      };
      this.resize = new ResizeObserver(() => this.draw()); this.resize.observe(this.el);
      if (globalThis.IntersectionObserver) {
        this.viewport = new IntersectionObserver(entries => { this.near = entries[0].isIntersecting; this.draw(); }, {rootMargin: '150px'});
        this.viewport.observe(this.el);
      }
      this.theme = () => this.draw(); window.addEventListener('trifle:theme-changed', this.theme);
      this.draw();
    },
    updated() { this.draw(); },
    destroyed() { this.resize.disconnect(); this.viewport?.disconnect(); window.removeEventListener('trifle:theme-changed', this.theme); this.chart?.dispose(); }
  };
}
