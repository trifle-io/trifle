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
import Sortable from "sortablejs"
import * as echarts from "echarts"
import { GridStack } from "gridstack"
import "./components/delivery_selector"
import { registerDashboardRuntimeHooks } from "./widgets/dashboard_runtime"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const ECHARTS_RENDERER = 'svg';
const ECHARTS_DEVICE_PIXEL_RATIO = Math.max(1, window.devicePixelRatio || 1);
const withChartOpts = (opts = {}) => Object.assign({ renderer: ECHARTS_RENDERER, devicePixelRatio: ECHARTS_DEVICE_PIXEL_RATIO }, opts);
const chartFontFamily =
  'Inter var, Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';

const formatCompactNumber = (value) => {
  if (value === null || value === undefined || value === '') return '0';
  const n = Number(value);
  if (!Number.isFinite(n)) return String(value);
  const abs = Math.abs(n);
  if (abs >= 1_000) {
    const units = ['', 'K', 'M', 'B', 'T'];
    let unitIndex = 0;
    let scaled = abs;
    while (scaled >= 1000 && unitIndex < units.length - 1) {
      scaled /= 1000;
      unitIndex += 1;
    }
    const decimals = scaled < 10 ? 2 : scaled < 100 ? 1 : 0;
    const formatted = scaled
      .toFixed(decimals)
      .replace(/\.0+$/, '')
      .replace(/(\.\d*?[1-9])0+$/, '$1');
    return `${n < 0 ? '-' : ''}${formatted}${units[unitIndex]}`;
  }

  const decimals = abs < 1 ? 2 : Number.isInteger(n) ? 0 : abs < 10 ? 2 : 1;
  return n
    .toFixed(decimals)
    .replace(/\.0+$/, '')
    .replace(/(\.\d*?[1-9])0+$/, '$1');
};

const SAFE_HTML_ALLOWED_TAGS = new Set([
  'a', 'b', 'blockquote', 'br', 'code', 'div', 'em', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'hr', 'i', 'li', 'ol', 'p', 'pre', 's', 'span', 'strong', 'table', 'tbody', 'td', 'th',
  'thead', 'tr', 'u', 'ul'
]);
const SAFE_HTML_DROP_TAGS = new Set([
  'script', 'style', 'iframe', 'object', 'embed', 'link', 'meta', 'base', 'form', 'input',
  'button', 'textarea', 'select', 'option', 'svg', 'math'
]);
const SAFE_HTML_GLOBAL_ATTRS = new Set(['class', 'title', 'role']);
const SAFE_HTML_TAG_ATTRS = {
  a: new Set(['href', 'target', 'rel']),
  th: new Set(['colspan', 'rowspan', 'scope']),
  td: new Set(['colspan', 'rowspan'])
};

const isSafeHtmlHref = (value) => {
  const href = String(value || '').trim();
  if (href === '') return false;
  if (href.startsWith('#')) return true;
  if (href.startsWith('/')) return !href.startsWith('//');

  try {
    const baseOrigin =
      window.location && window.location.origin ? window.location.origin : 'http://localhost';
    const parsed = new URL(href, baseOrigin);
    const protocol = String(parsed.protocol || '').toLowerCase();
    return protocol === 'http:' || protocol === 'https:' || protocol === 'mailto:' || protocol === 'tel:';
  } catch (_) {
    return false;
  }
};

const sanitizeRichHtml = (rawHtml) => {
  if (typeof rawHtml !== 'string' || rawHtml.trim() === '') return '';
  const template = document.createElement('template');
  template.innerHTML = rawHtml;

  const sanitizeAttrs = (element, tag) => {
    const tagAllowedAttrs = SAFE_HTML_TAG_ATTRS[tag] || new Set();

    Array.from(element.attributes).forEach((attr) => {
      const name = String(attr.name || '').toLowerCase();
      const value = String(attr.value || '');
      const isAria = name.startsWith('aria-');
      const allowed = isAria || SAFE_HTML_GLOBAL_ATTRS.has(name) || tagAllowedAttrs.has(name);

      if (
        !allowed ||
        name.startsWith('on') ||
        name === 'style' ||
        name === 'srcdoc' ||
        name.includes(':')
      ) {
        element.removeAttribute(attr.name);
        return;
      }

      if (tag === 'a' && name === 'href') {
        const href = value.trim();
        if (!isSafeHtmlHref(href)) {
          element.removeAttribute(attr.name);
        } else {
          element.setAttribute('href', href);
        }
      }

      if (tag === 'a' && name === 'target') {
        const target = value.trim().toLowerCase();
        if (!['_blank', '_self', '_parent', '_top'].includes(target)) {
          element.removeAttribute(attr.name);
        } else {
          element.setAttribute('target', target);
        }
      }

      if ((name === 'colspan' || name === 'rowspan') && !/^\d+$/.test(value.trim())) {
        element.removeAttribute(attr.name);
      }
    });

    if (tag === 'a' && String(element.getAttribute('target') || '').toLowerCase() === '_blank') {
      const relTokens = new Set(
        String(element.getAttribute('rel') || '')
          .toLowerCase()
          .split(/\s+/)
          .filter(Boolean)
      );

      ['noopener', 'noreferrer', 'nofollow'].forEach((token) => {
        relTokens.add(token);
      });
      element.setAttribute('rel', Array.from(relTokens).sort().join(' '));
    }
  };

  const sanitizeNode = (node) => {
    if (!node) return;

    if (node.nodeType === 8) {
      node.remove();
      return;
    }

    if (node.nodeType !== 1) return;

    const tag = String(node.tagName || '').toLowerCase();
    if (SAFE_HTML_DROP_TAGS.has(tag)) {
      node.remove();
      return;
    }

    Array.from(node.childNodes).forEach((child) => {
      sanitizeNode(child);
    });

    if (!SAFE_HTML_ALLOWED_TAGS.has(tag)) {
      node.replaceWith(...Array.from(node.childNodes));
      return;
    }

    sanitizeAttrs(node, tag);
  };

  Array.from(template.content.childNodes).forEach((node) => {
    sanitizeNode(node);
  });
  return template.innerHTML;
};

const normalizeHexColor = (color) => {
  if (typeof color !== 'string') return null;
  const trimmed = color.trim();
  const full = trimmed.match(/^#([0-9a-f]{6})$/i);
  if (full) return `#${full[1].toLowerCase()}`;

  const short = trimmed.match(/^#([0-9a-f]{3})$/i);
  if (!short) return null;
  const [r, g, b] = short[1].toLowerCase().split('');
  return `#${r}${r}${g}${g}${b}${b}`;
};

const hexToRgb = (hexColor) => {
  const normalized = normalizeHexColor(hexColor);
  if (!normalized) return null;
  const hex = normalized.slice(1);
  return {
    r: parseInt(hex.slice(0, 2), 16),
    g: parseInt(hex.slice(2, 4), 16),
    b: parseInt(hex.slice(4, 6), 16)
  };
};

const pickHeatmapBaseColor = (seriesList, fallbackColor = null) => {
  const configuredColors = (Array.isArray(seriesList) ? seriesList : [])
    .map((series) => {
      const color = series && typeof series.color === 'string' ? series.color.trim() : '';
      return color !== '' ? color : null;
    })
    .filter(Boolean);

  if (!configuredColors.length) return fallbackColor;

  const uniqueConfiguredColors = Array.from(new Set(configuredColors.map((color) => color.toLowerCase())));
  if (uniqueConfiguredColors.length === 1) return configuredColors[0];
  return fallbackColor;
};

const heatmapColorScale = (baseColor, isDarkMode) => {
  const fallbackScale = isDarkMode
    ? ['#0f172a', '#1d4ed8', '#06b6d4', '#f59e0b', '#ef4444']
    : ['#ecfeff', '#bae6fd', '#67e8f9', '#fbbf24', '#dc2626'];

  const rgb = hexToRgb(baseColor);
  if (!rgb) return fallbackScale;

  const { r, g, b } = rgb;
  const minAlpha = isDarkMode ? 0.08 : 0.05;
  const lowAlpha = isDarkMode ? 0.25 : 0.2;
  const midAlpha = isDarkMode ? 0.48 : 0.42;
  const highAlpha = isDarkMode ? 0.72 : 0.68;

  return [
    `rgba(${r}, ${g}, ${b}, ${minAlpha})`,
    `rgba(${r}, ${g}, ${b}, ${lowAlpha})`,
    `rgba(${r}, ${g}, ${b}, ${midAlpha})`,
    `rgba(${r}, ${g}, ${b}, ${highAlpha})`,
    `rgba(${r}, ${g}, ${b}, 1)`
  ];
};

const HEATMAP_PALETTES = Object.freeze({
  default: ['#14b8a6', '#f59e0b', '#ef4444', '#8b5cf6', '#06b6d4', '#10b981', '#f97316', '#ec4899', '#3b82f6', '#84cc16', '#f43f5e', '#6366f1'],
  purple: ['#C4B5FD', '#A78BFA', '#8B5CF6', '#7C3AED', '#6D28D9', '#5B21B6', '#4C1D95'],
  cool: ['#BFDBFE', '#93C5FD', '#60A5FA', '#38BDF8', '#0EA5E9', '#0284C7', '#0369A1'],
  green: ['#BBF7D0', '#86EFAC', '#4ADE80', '#22C55E', '#16A34A', '#15803D', '#166534'],
  warm: ['#FDE68A', '#FCD34D', '#FBBF24', '#F59E0B', '#F97316', '#EF4444', '#DC2626']
});

const heatmapColorWithAlpha = (hexColor, alpha) => {
  const rgb = hexToRgb(hexColor);
  if (!rgb) return null;
  const safeAlpha = Number.isFinite(alpha) ? Math.max(0, Math.min(1, alpha)) : 1;
  return `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${safeAlpha})`;
};

const normalizeHeatmapColorMode = (value) => {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'single' || normalized === 'palette' || normalized === 'diverging') return normalized;
  return 'auto';
};

const normalizeHeatmapColorConfig = (config, fallbackSingleColor = '#14b8a6') => {
  const source = config && typeof config === 'object' ? config : {};
  const singleColor = normalizeHexColor(source.single_color || source.singleColor || fallbackSingleColor) || '#14b8a6';
  const paletteIdRaw = String(source.palette_id || source.paletteId || 'default').trim().toLowerCase();
  const paletteId = Object.prototype.hasOwnProperty.call(HEATMAP_PALETTES, paletteIdRaw) ? paletteIdRaw : 'default';
  const negativeColor = normalizeHexColor(source.negative_color || source.negativeColor || '#0EA5E9') || '#0EA5E9';
  const positiveColor = normalizeHexColor(source.positive_color || source.positiveColor || '#EF4444') || '#EF4444';
  const centerRaw = Number(source.center_value ?? source.centerValue ?? 0);
  const centerValue = Number.isFinite(centerRaw) ? centerRaw : 0;
  const symmetricRaw = source.symmetric;
  const symmetric =
    symmetricRaw === true || symmetricRaw === 'true' || symmetricRaw === 1 || symmetricRaw === '1';

  return {
    singleColor,
    paletteId,
    negativeColor,
    positiveColor,
    centerValue,
    symmetric
  };
};

const heatmapPaletteScale = (paletteId, isDarkMode) => {
  const palette = HEATMAP_PALETTES[paletteId] || HEATMAP_PALETTES.default;
  if (!Array.isArray(palette) || !palette.length) return heatmapColorScale('#14b8a6', isDarkMode);
  const start = heatmapColorWithAlpha(palette[0], isDarkMode ? 0.08 : 0.05) || palette[0];
  return [start, ...palette];
};

const resolveHeatmapVisualMap = ({
  payload,
  heatmapData,
  series,
  fallbackHeatColor,
  isDarkMode
}) => {
  const values = (Array.isArray(heatmapData) ? heatmapData : [])
    .map((point) => Number(point && point[2]))
    .filter((value) => Number.isFinite(value));

  let rawMin = 0;
  let rawMax = 0;
  if (values.length) {
    let min = Infinity;
    let max = -Infinity;
    values.forEach((value) => {
      if (value < min) min = value;
      if (value > max) max = value;
    });
    rawMin = min;
    rawMax = max;
  }
  const mode = normalizeHeatmapColorMode(payload && payload.color_mode);
  const config = normalizeHeatmapColorConfig(payload && payload.color_config, fallbackHeatColor || '#14b8a6');

  if (mode === 'diverging') {
    const center = config.symmetric ? 0 : config.centerValue;
    const span = Math.max(Math.abs(rawMax - center), Math.abs(rawMin - center), 1);
    const min = center - span;
    const max = center + span;
    const centerColor = isDarkMode ? 'rgba(148, 163, 184, 0.12)' : 'rgba(148, 163, 184, 0.18)';
    const negativeMid = heatmapColorWithAlpha(config.negativeColor, isDarkMode ? 0.45 : 0.35) || config.negativeColor;
    const positiveMid = heatmapColorWithAlpha(config.positiveColor, isDarkMode ? 0.45 : 0.35) || config.positiveColor;

    return {
      min,
      max,
      colorScale: [config.negativeColor, negativeMid, centerColor, positiveMid, config.positiveColor]
    };
  }

  const min = rawMin >= 0 ? 0 : rawMin;
  const max = rawMax > min ? rawMax : min + 1;

  if (mode === 'palette') {
    return {
      min,
      max,
      colorScale: heatmapPaletteScale(config.paletteId, isDarkMode)
    };
  }

  if (mode === 'single') {
    return {
      min,
      max,
      colorScale: heatmapColorScale(config.singleColor, isDarkMode)
    };
  }

  const baseColor = pickHeatmapBaseColor(series, fallbackHeatColor);
  return {
    min,
    max,
    colorScale: heatmapColorScale(baseColor, isDarkMode)
  };
};

const heatmapFocusItemStyle = (isDarkMode) => ({
  shadowBlur: isDarkMode ? 16 : 12,
  shadowColor: isDarkMode ? 'rgba(248, 250, 252, 0.45)' : 'rgba(15, 23, 42, 0.35)',
  shadowOffsetX: 0,
  shadowOffsetY: 0
});

const buildBucketIndexMap = (labels) => {
  const map = new Map();
  (Array.isArray(labels) ? labels : []).forEach((label, idx) => {
    map.set(String(label), idx);
  });
  return map;
};

const distributionSeriesName = (seriesItem, idx) => {
  const rawName =
    typeof (seriesItem && seriesItem.name) === 'string'
      ? seriesItem.name.trim()
      : '';
  return rawName !== '' ? rawName : `Series ${idx + 1}`;
};

const buildDistributionHeatmapAggregation = ({
  seriesList,
  labelIndexMap,
  verticalLabelIndexMap
}) => {
  const totalsByCell = new Map();
  const breakdownTotalsByCell = new Map();
  const safeSeries = Array.isArray(seriesList) ? seriesList : [];

  safeSeries.forEach((seriesItem, idx) => {
    const name = distributionSeriesName(seriesItem, idx);
    const points = Array.isArray(seriesItem && seriesItem.points) ? seriesItem.points : [];

    points.forEach((point) => {
      if (!point || point.bucket_x == null || point.bucket_y == null) return;
      const xIdx = labelIndexMap.get(String(point.bucket_x));
      const yIdx = verticalLabelIndexMap.get(String(point.bucket_y));
      if (xIdx == null || yIdx == null) return;

      const value = Number(point.value);
      if (!Number.isFinite(value)) return;

      const key = `${xIdx}:${yIdx}`;
      totalsByCell.set(key, (totalsByCell.get(key) || 0) + value);

      const seriesTotals = breakdownTotalsByCell.get(key) || new Map();
      seriesTotals.set(name, (seriesTotals.get(name) || 0) + value);
      breakdownTotalsByCell.set(key, seriesTotals);
    });
  });

  const breakdownByCell = new Map();
  breakdownTotalsByCell.forEach((seriesTotals, key) => {
    breakdownByCell.set(
      key,
      aggregateHeatmapBreakdown(
        Array.from(seriesTotals.entries()).map(([seriesName, totalValue]) => ({
          name: seriesName,
          value: totalValue
        }))
      )
    );
  });

  const heatmapData = Array.from(totalsByCell.entries())
    .map(([key, value]) => {
      const [xIdxRaw, yIdxRaw] = key.split(':');
      const xIdx = Number(xIdxRaw);
      const yIdx = Number(yIdxRaw);
      return [xIdx, yIdx, value];
    })
    .filter((entry) => Number.isFinite(entry[0]) && Number.isFinite(entry[1]));

  return { heatmapData, breakdownByCell };
};

const buildDistributionScatterSeries = ({
  seriesList,
  labelIndexMap,
  verticalLabelIndexMap,
  resolveColor
}) => {
  let maxValue = 0;
  const safeSeries = Array.isArray(seriesList) ? seriesList : [];

  const seriesData = safeSeries.map((seriesItem, idx) => {
    const name = distributionSeriesName(seriesItem, idx);

    const points = Array.isArray(seriesItem && seriesItem.points) ? seriesItem.points : [];
    const color = resolveColor(seriesItem, idx);

    const data = points
      .map((point) => {
        if (!point || point.bucket_x == null || point.bucket_y == null) return null;

        const xIdx = labelIndexMap.get(String(point.bucket_x));
        const yIdx = verticalLabelIndexMap.get(String(point.bucket_y));
        if (xIdx == null || yIdx == null) return null;

        const value = Number(point.value);
        if (!Number.isFinite(value)) return null;

        maxValue = Math.max(maxValue, value);
        return [xIdx, yIdx, value];
      })
      .filter(Boolean);

    return {
      name,
      type: 'scatter',
      data,
      symbolSize: (val) => {
        const v = val && val[2] ? val[2] : 0;
        if (!maxValue) return 10;
        const size = 8 + (v / maxValue) * 24;
        return Math.max(6, size);
      },
      itemStyle: { color, opacity: 1 },
      hoverAnimation: false,
      emphasis: {
        disabled: true,
        focus: 'none',
        scale: false,
        blurScope: 'none',
        itemStyle: { opacity: 1 }
      },
      select: { disabled: true }
    };
  });

  const filteredSeries = seriesData.filter(
    (entry) => Array.isArray(entry.data) && entry.data.length
  );
  const legendNames = filteredSeries.map((entry) => entry.name);

  return {
    seriesData: filteredSeries,
    legendNames
  };
};

const aggregateHeatmapBreakdown = (entries) => {
  const totals = new Map();

  (Array.isArray(entries) ? entries : []).forEach((entry) => {
    if (!entry) return;
    const rawName = typeof entry.name === 'string' ? entry.name.trim() : '';
    const name = rawName !== '' ? rawName : 'Series';
    const value = Number(entry.value);
    if (!Number.isFinite(value)) return;
    totals.set(name, (totals.get(name) || 0) + value);
  });

  return Array.from(totals.entries())
    .map(([name, value]) => ({ name, value }))
    .sort((a, b) => Number(b.value || 0) - Number(a.value || 0));
};

const formatHeatmapTooltip = ({
  params,
  labels,
  verticalLabels,
  breakdownByCell,
  escapeHtml
}) => {
  const valueArr =
    Array.isArray(params?.value) && params.value.length >= 3
      ? params.value
      : Array.isArray(params?.data) && params.data.length >= 3
        ? params.data
        : null;

  if (!valueArr) return '';

  const xIdx = Number.isFinite(valueArr[0]) ? valueArr[0] : null;
  const yIdx = Number.isFinite(valueArr[1]) ? valueArr[1] : null;
  const val = Number.isFinite(valueArr[2]) ? valueArr[2] : 0;
  const xLabel = xIdx != null && labels[xIdx] ? labels[xIdx] : labels[0] || '';
  const yLabel = yIdx != null && verticalLabels[yIdx] ? verticalLabels[yIdx] : verticalLabels[0] || '';
  if (!xLabel && !yLabel) return '';

  const key = `${xIdx}:${yIdx}`;
  const breakdown =
    breakdownByCell instanceof Map && Array.isArray(breakdownByCell.get(key))
      ? breakdownByCell.get(key)
      : [];

  const safeEscape =
    typeof escapeHtml === 'function'
      ? escapeHtml
      : (value) => String(value == null ? '' : value);

  const marker = params?.marker || '';
  const primaryLabel = breakdown.length === 1 ? breakdown[0].name : 'Total';
  const safeXLabel = safeEscape(xLabel);
  const safeYLabel = safeEscape(yLabel);
  const lines = [
    `${safeXLabel} × ${safeYLabel}`,
    `${marker}${safeEscape(primaryLabel)}  <strong>${formatCompactNumber(val)}</strong>`
  ];

  if (breakdown.length > 1) {
    breakdown.slice(0, 5).forEach((entry) => {
      lines.push(`${safeEscape(entry.name)}: ${formatCompactNumber(entry.value)}`);
    });
    if (breakdown.length > 5) {
      lines.push(`+${breakdown.length - 5} more`);
    }
  }

  return lines.join('<br/>');
};

const buildHeatmapOptions = ({
  labels,
  verticalLabels,
  breakdownByCell,
  isDarkMode,
  gridBottom,
  visualMapBottom,
  visualSettings,
  showScale,
  heatmapData,
  chartFontFamily,
  escapeHtml
}) => ({
  backgroundColor: 'transparent',
  legend: { show: false },
  tooltip: {
    trigger: 'item',
    appendToBody: true,
    formatter: (params) =>
      formatHeatmapTooltip({
        params,
        labels,
        verticalLabels,
        breakdownByCell,
        escapeHtml
      })
  },
  axisPointer: {
    show: true,
    type: 'line',
    lineStyle: { type: 'dashed', color: isDarkMode ? '#94a3b8' : '#0f172a' },
    link: [{ xAxisIndex: 'all' }, { yAxisIndex: 'all' }],
    label: { show: true }
  },
  grid: { top: 16, left: 64, right: 16, bottom: gridBottom },
  xAxis: {
    type: 'category',
    data: labels,
    splitLine: {
      show: true,
      lineStyle: {
        type: 'dashed',
        color: isDarkMode ? '#1f2937' : '#e2e8f0',
        opacity: isDarkMode ? 0.4 : 0.9
      }
    },
    axisLabel: { color: isDarkMode ? '#CBD5F5' : '#475569', interval: 0, rotate: labels.length > 8 ? 30 : 0 }
  },
  yAxis: {
    type: 'category',
    data: verticalLabels,
    splitLine: {
      show: true,
      lineStyle: {
        type: 'dashed',
        color: isDarkMode ? '#1f2937' : '#e2e8f0',
        opacity: isDarkMode ? 0.4 : 0.9
      }
    },
    axisLabel: { color: isDarkMode ? '#CBD5F5' : '#475569' }
  },
  visualMap: showScale
    ? {
        min: visualSettings.min,
        max: visualSettings.max,
        calculable: false,
        orient: 'horizontal',
        left: 'center',
        bottom: visualMapBottom,
        textStyle: { color: isDarkMode ? '#E2E8F0' : '#0F172A', fontFamily: chartFontFamily },
        inRange: { color: visualSettings.colorScale }
      }
    : { show: false },
  series: [{
    name: 'Heat',
    type: 'heatmap',
    data: heatmapData,
    progressive: 1000,
    emphasis: { itemStyle: heatmapFocusItemStyle(isDarkMode) },
    select: { itemStyle: heatmapFocusItemStyle(isDarkMode) }
  }]
});

const extractTimestamp = (point) => {
  if (Array.isArray(point) && point.length) return Number(point[0]);
  if (point && typeof point === 'object') {
    if (Array.isArray(point.value) && point.value.length) return Number(point.value[0]);
    if (Array.isArray(point.coord) && point.coord.length) return Number(point.coord[0]);
  }
  return null;
};

const detectOngoingSegment = (seriesList) => {
  const timestamps =
    (Array.isArray(seriesList) ? seriesList : [])
      .flatMap((series) => (Array.isArray(series?.data) ? series.data : []))
      .map((point) => extractTimestamp(point))
      .filter((ts) => Number.isFinite(ts));

  const sorted = Array.from(new Set(timestamps)).sort((a, b) => a - b);
  if (sorted.length < 2) return null;

  let bucketMs = null;
  for (let i = 1; i < sorted.length; i++) {
    const diff = sorted[i] - sorted[i - 1];
    if (diff > 0) {
      bucketMs = bucketMs == null ? diff : Math.min(bucketMs, diff);
    }
  }

  if (!Number.isFinite(bucketMs) || bucketMs <= 0) return null;

  const lastTs = sorted[sorted.length - 1];
  const now = Date.now();
  return now >= lastTs && now < lastTs + bucketMs ? { lastTs, bucketMs } : null;
};

const TABLE_PATH_HTML_FIELD = '__table_path_html__';
const AGGRID_PATH_COL_MIN_WIDTH = 160;
const AGGRID_PATH_COL_MAX_WIDTH = 640;
const AGGRID_SCRIPT_SRC = 'https://cdn.jsdelivr.net/npm/ag-grid-community@31.0.3/dist/ag-grid-community.min.js';
const AGGRID_BASE_STYLE_SRC = 'https://cdn.jsdelivr.net/npm/ag-grid-community@31.0.3/styles/ag-grid.css';
const AGGRID_THEME_LIGHT_STYLE_SRC = 'https://cdn.jsdelivr.net/npm/ag-grid-community@31.0.3/styles/ag-theme-alpine.css';
const AGGRID_THEME_DARK_STYLE_SRC = 'https://cdn.jsdelivr.net/npm/ag-grid-community@31.0.3/styles/ag-theme-alpine-dark.css';
let aggridLoaderPromise = null;
let aggridHeaderComponentClass = null;

const ensureStylesheet = (id, href) => {
  if (typeof document === 'undefined') return;
  if (document.getElementById(id)) return;
  const existing = Array.from(document.querySelectorAll(`link[data-trifle-css="${id}"]`));
  if (existing.length) return;
  const link = document.createElement('link');
  link.rel = 'stylesheet';
  link.href = href;
  link.id = id;
  link.dataset.trifleCss = id;
  document.head.appendChild(link);
};

const ensureAgGridCommunity = () => {
  if (typeof window !== 'undefined' && window.agGrid && window.agGrid.Grid) {
    return Promise.resolve(window.agGrid);
  }
  if (!aggridLoaderPromise) {
    aggridLoaderPromise = new Promise((resolve, reject) => {
      if (typeof document === 'undefined') {
        reject(new Error('Document not available'));
        return;
      }
      ensureStylesheet('ag-grid-base-css', AGGRID_BASE_STYLE_SRC);
      ensureStylesheet('ag-grid-alpine-css', AGGRID_THEME_LIGHT_STYLE_SRC);
      ensureStylesheet('ag-grid-alpine-dark-css', AGGRID_THEME_DARK_STYLE_SRC);
      const script = document.createElement('script');
      script.src = AGGRID_SCRIPT_SRC;
      script.async = true;
      script.onload = () => resolve(window.agGrid);
      script.onerror = (err) => {
        console.error('[AGGrid] failed to load ag-grid-community script', err);
        aggridLoaderPromise = null;
        reject(err);
      };
      document.head.appendChild(script);
    });
  }
  return aggridLoaderPromise;
};

const getAggridHeaderComponentClass = () => {
  if (aggridHeaderComponentClass) return aggridHeaderComponentClass;
  class TrifleAgGridHeader {
    init(params) {
      this.eGui = document.createElement('div');
      this.eGui.className = 'aggrid-header-cell-wrapper';
      if (params && params.align === 'left') {
        this.eGui.classList.add('aggrid-header-align-left');
      } else {
        this.eGui.classList.add('aggrid-header-align-right');
      }
      const lines =
        (params &&
          params.column &&
          params.column.getColDef &&
          params.column.getColDef() &&
          params.column.getColDef().headerComponentParams &&
          params.column.getColDef().headerComponentParams.lines) ||
        [];
      const displayName = params && typeof params.displayName === 'string' ? params.displayName : '';
      const segments = Array.isArray(lines) && lines.length ? lines : [displayName];
      segments.forEach((segment, idx) => {
        const span = document.createElement('span');
        span.className = 'aggrid-header-line';
        span.textContent = segment;
        this.eGui.appendChild(span);
      });
    }

    getGui() {
      return this.eGui;
    }

    destroy() {}
  }
  aggridHeaderComponentClass = TrifleAgGridHeader;
  return aggridHeaderComponentClass;
};

let Hooks = {}

const parseJsonSafe = (value) => {
  if (value == null || value === '') return null;
  try {
    return JSON.parse(value);
  } catch (_) {
    return null;
  }
};

const setHidden = (el, hidden) => {
  if (!el) return;
  if (hidden) {
    el.classList.add('hidden');
  } else {
    el.classList.remove('hidden');
  }
};

const findDashboardGridHook = (el) => {
  if (!el) return null;
  const gridId = el.dataset && el.dataset.gridId;
  if (gridId) {
    const direct = document.getElementById(gridId);
    if (direct && direct.__dashboardGrid) return direct.__dashboardGrid;
  }
  const gridEl = el.closest('#dashboard-grid') || el.closest('.grid-stack');
  if (gridEl && gridEl.__dashboardGrid) return gridEl.__dashboardGrid;
  if (gridId) {
    const fallback = document.querySelector(`#${gridId}`);
    if (fallback && fallback.__dashboardGrid) return fallback.__dashboardGrid;
  }
  return null;
};

registerDashboardRuntimeHooks(Hooks, {
  echarts,
  GridStack,
  withChartOpts,
  chartFontFamily,
  formatCompactNumber,
  sanitizeRichHtml,
  resolveHeatmapVisualMap,
  buildHeatmapOptions,
  detectOngoingSegment,
  buildBucketIndexMap,
  buildDistributionHeatmapAggregation,
  buildDistributionScatterSeries,
  TABLE_PATH_HTML_FIELD,
  AGGRID_PATH_COL_MIN_WIDTH,
  AGGRID_PATH_COL_MAX_WIDTH,
  ensureAgGridCommunity,
  getAggridHeaderComponentClass,
  parseJsonSafe,
  findDashboardGridHook
});

Hooks.DocumentTitle = {
  mounted() {
    // Create bound event handler so we can properly remove it
    this.handleNavigate = () => {
      // Force LiveView to update the title after navigation
      // This ensures the title updates even when using push_navigate
      requestAnimationFrame(() => {
        const liveTitle = document.querySelector('[data-phx-main] title')
        if (liveTitle && liveTitle.textContent) {
          document.title = liveTitle.textContent
        } else {
          // Fallback to our element's data
          this.updateTitle()
        }
      })
    }
    
    this.updateTitle()
    
    // Listen for both navigation events
    window.addEventListener("phx:page-loading-stop", this.handleNavigate)
    window.addEventListener("phx:navigate", this.handleNavigate)
  },
  updated() {
    this.updateTitle()
  },
  destroyed() {
    if (this.handleNavigate) {
      window.removeEventListener("phx:page-loading-stop", this.handleNavigate)
      window.removeEventListener("phx:navigate", this.handleNavigate)
    }
  },
  updateTitle() {
    const title = this.el.dataset.title || 'Trifle'
    const suffix = this.el.dataset.suffix || ''
    document.title = `${title}${suffix}`
  }
}

Hooks.CopyFeedback = {
  mounted() {
    this._copyFeedbackTimeout = null;
    this._handleCopyFeedbackClick = () => {
      const timeout = parseInt(this.el.dataset.copyTimeout || '2000', 10);
      const delay = Number.isFinite(timeout) ? timeout : 2000;
      const copyIcon = this.el.dataset.copyIcon
        ? document.getElementById(this.el.dataset.copyIcon)
        : null;
      const copiedIcon = this.el.dataset.copiedIcon
        ? document.getElementById(this.el.dataset.copiedIcon)
        : null;
      const copyLabel = this.el.dataset.copyLabel
        ? document.getElementById(this.el.dataset.copyLabel)
        : null;
      const copiedLabel = this.el.dataset.copiedLabel
        ? document.getElementById(this.el.dataset.copiedLabel)
        : null;

      setHidden(copyIcon, true);
      setHidden(copiedIcon, false);
      setHidden(copyLabel, true);
      setHidden(copiedLabel, false);

      if (this._copyFeedbackTimeout) {
        clearTimeout(this._copyFeedbackTimeout);
      }

      this._copyFeedbackTimeout = setTimeout(() => {
        setHidden(copyIcon, false);
        setHidden(copiedIcon, true);
        setHidden(copyLabel, false);
        setHidden(copiedLabel, true);
        this._copyFeedbackTimeout = null;
      }, delay);
    };

    this.el.addEventListener('click', this._handleCopyFeedbackClick);
  },
  destroyed() {
    if (this._handleCopyFeedbackClick) {
      this.el.removeEventListener('click', this._handleCopyFeedbackClick);
    }
    if (this._copyFeedbackTimeout) {
      clearTimeout(this._copyFeedbackTimeout);
      this._copyFeedbackTimeout = null;
    }
  }
}

Hooks.SmartTimeframeInput = {
  mounted() {
    this.handleEvent("update_smart_timeframe_input", ({value}) => {
      this.el.value = value;
    });
  }
}

Hooks.SmartTimeframeBlur = {
  mounted() {
    this.el.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        // Blur the input after Enter to trigger value update
        setTimeout(() => this.el.blur(), 100);
      }
    });
    
    // Auto-select text when input is focused
    this.el.addEventListener('focus', () => {
      // Use setTimeout to ensure selection happens after other focus events
      setTimeout(() => {
        this.el.select();
      }, 10);
    });
    
    // Also handle click events in case focus doesn't work
    this.el.addEventListener('click', () => {
      // Only select if the input wasn't already focused
      if (document.activeElement !== this.el) {
        setTimeout(() => {
          this.el.select();
        }, 10);
      }
    });
    
    this.handleEvent("update_timeframe_input", ({value}) => {
      this.el.value = value;
    });
  }
}

Hooks.ChatScroll = {
  mounted() {
    this._pendingScroll = null
    this.scrollToBottom()
    this.handleEvent("chat_scroll_bottom", () => this.scrollToBottom())
  },
  updated() {
    this.scrollToBottom()
  },
  scrollToBottom() {
    if (this._pendingScroll) {
      clearTimeout(this._pendingScroll)
    }

    const performScroll = (behavior = "auto") => {
      const el = this.el
      if (!el) return
      el.scrollTo({ top: el.scrollHeight, behavior })
    }

    requestAnimationFrame(() => {
      performScroll("auto")
      requestAnimationFrame(() => performScroll("smooth"))
    })

    this._pendingScroll = setTimeout(() => performScroll("auto"), 300)
  },
  destroyed() {
    if (this._pendingScroll) {
      clearTimeout(this._pendingScroll)
    }
  }
}

Hooks.ChatInput = {
  mounted() {
    this.handleKeydown = (event) => {
      if (event.defaultPrevented || this.el.disabled || this.el.readOnly) {
        return
      }

      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault()

        const form = this.el.form || this.el.closest("form")
        if (!form) return

        if (typeof form.requestSubmit === "function") {
          form.requestSubmit()
        } else {
          const submit = form.querySelector('[type="submit"]:not([disabled])')
          if (submit) submit.click()
        }
      }
    }

    this.el.addEventListener("keydown", this.handleKeydown)
  },
  destroyed() {
    if (this.handleKeydown) {
      this.el.removeEventListener("keydown", this.handleKeydown)
    }
  }
}

Hooks.ExportTheme = {
  mounted() {
    this.applyTheme();
  },
  updated() {
    this.applyTheme();
  },
  destroyed() {
    if (this._themeTimer) {
      clearTimeout(this._themeTimer);
      this._themeTimer = null;
    }
  },
  applyTheme() {
    const dataset = this.el.dataset || {};
    const value = (dataset.exportTheme || dataset.theme || '').toLowerCase();
    const theme = value === 'dark' ? 'dark' : 'light';
    const root = document.documentElement;
    const body = document.body;
    try {
      if (theme === 'dark') {
        root.classList.add('dark');
        if (body && body.classList) body.classList.add('dark');
      } else {
        root.classList.remove('dark');
        if (body && body.classList) body.classList.remove('dark');
      }
      root.dataset.exportTheme = theme;
      if (body) body.dataset.theme = theme;
      root.style.background = 'transparent';
      if (body) body.style.background = 'transparent';
    } catch (_) {}

    if (this._themeTimer) {
      clearTimeout(this._themeTimer);
      this._themeTimer = null;
    }

    this._themeTimer = setTimeout(() => {
      try {
        window.dispatchEvent(new CustomEvent('trifle:theme-changed', { detail: { theme } }));
      } catch (_) {}
    }, 0);
  }
}

Hooks.ChatChart = {
  mounted() {
    this.chart = null;
    this.theme = null;
    this.retryTimer = null;
    this.resizeObserver = null;
    this.pendingRender = false;
    this.resizeHandler = () => {
      if (this.chart && typeof this.chart.resize === 'function') {
        try { this.chart.resize(); } catch (_) {}
      }
    };
    this.themeHandler = () => this.render(true);
    this.createResizeObserver();
    window.addEventListener('resize', this.resizeHandler);
    window.addEventListener('trifle:theme-changed', this.themeHandler);
    this.render();
  },
  updated() {
    this.render();
  },
  destroyed() {
    if (this.retryTimer) {
      clearTimeout(this.retryTimer);
      this.retryTimer = null;
    }
    this.destroyResizeObserver();
    if (this.chart && typeof this.chart.dispose === 'function') {
      try { this.chart.dispose(); } catch (_) {}
    }
    this.chart = null;
    this.pendingRender = false;
    window.removeEventListener('resize', this.resizeHandler);
    window.removeEventListener('trifle:theme-changed', this.themeHandler);
  },
  render(force = false) {
    const chartData = this.parseChart();
    if (!chartData) return;
    if (this.retryTimer) {
      clearTimeout(this.retryTimer);
      this.retryTimer = null;
    }
    const width = this.el.clientWidth;
    const height = this.el.clientHeight;
    if (!width || !height) {
      this.pendingRender = true;
      if (!this.retryTimer) {
        this.retryTimer = setTimeout(() => this.render(true), 160);
      }
      return;
    }
    const theme = document.documentElement.classList.contains('dark') ? 'dark' : 'light';
    if (this.chart) {
      try { this.chart.dispose(); } catch (_) {}
      this.chart = null;
    }
    const chart = this.ensureChart(theme);
    if (!chart) return;
    const palette = this.palette();

    let option;
    if (chartData.type === 'category') {
      option = this.categoryOption(chartData, palette, theme);
    } else {
      option = this.timeseriesOption(chartData, palette, theme);
    }
    chart.setOption(option, true);
    requestAnimationFrame(() => {
      if (this.chart && typeof this.chart.resize === 'function') {
        try { this.chart.resize(); } catch (_) {}
      }
    });

    this.pendingRender = false;
  },
  parseChart() {
    const raw = this.el.dataset.chart || '';
    if (!raw) return null;
    try {
      const chart = JSON.parse(raw);
      chart.type = (chart.type || '').toLowerCase();
      chart.dataset = chart.dataset || {};
      return chart;
    } catch (_) {
      return null;
    }
  },
  palette() {
    const raw = this.el.dataset.colors || '[]';
    try {
      const colors = JSON.parse(raw);
      if (Array.isArray(colors) && colors.length) return colors;
    } catch (_) {}
    return ["#14b8a6", "#f59e0b", "#8b5cf6", "#06b6d4", "#10b981"];
  },
  ensureChart(theme) {
    if (this.chart) {
      const hasVisual = this.el && this.el.querySelector('canvas, svg');
      if (!hasVisual) {
        try { this.chart.dispose(); } catch (_) {}
        this.chart = null;
      }
    }

    if (this.chart) {
      try {
        const dom = typeof this.chart.getDom === 'function' ? this.chart.getDom() : null;
        if (!dom || dom !== this.el) {
          this.chart.dispose();
          this.chart = null;
        }
      } catch (_) {
        this.chart = null;
      }
    }

    if (this.chart && this.theme === theme) {
      if (this.el.clientWidth === 0 || this.el.clientHeight === 0) {
        this.scheduleRetry();
        return null;
      }
      return this.chart;
    }
    if (this.chart && typeof this.chart.dispose === 'function') {
      try { this.chart.dispose(); } catch (_) {}
    }
    this.chart = null;
    if (this.el.clientWidth === 0 || this.el.clientHeight === 0) {
      this.scheduleRetry();
      return null;
    }
    this.chart = echarts.init(this.el, theme === 'dark' ? 'dark' : undefined, withChartOpts());
    this.theme = theme;
    return this.chart;
  },
  scheduleRetry() {
    if (this.retryTimer) return;
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null;
      this.render(true);
    }, 160);
  },
  timeseriesOption(chartData, palette, theme) {
    const dataset = chartData.dataset || {};
    const seriesConfig = Array.isArray(dataset.series) ? dataset.series : [];
    const chartType = (dataset.chart_type || 'line').toLowerCase();
    const isBar = chartType === 'bar';
    const isArea = chartType === 'area';
    const isDots = chartType === 'dots';
    const seriesType = isBar ? 'bar' : isDots ? 'scatter' : 'line';
    const stacked = !!dataset.stacked;
    const showLegend = dataset.legend === undefined ? seriesConfig.length > 1 : !!dataset.legend;
    const textColor = theme === 'dark' ? '#9CA3AF' : '#6B7280';
    const axisLineColor = theme === 'dark' ? '#374151' : '#E5E7EB';
    const gridLineColor = theme === 'dark' ? '#1F2937' : '#E5E7EB';
    const legendText = theme === 'dark' ? '#D1D5DB' : '#374151';
    const yLabel = dataset.y_label || '';

    const series = seriesConfig.map((entry, idx) => {
      const dataPoints = Array.isArray(entry.data) ? entry.data : [];
      const sanitized = dataPoints.map((point) => {
        const toNumber = (val) => {
          const num = Number(val);
          return Number.isFinite(num) ? num : 0;
        };

        if (Array.isArray(point)) {
          const ts = toNumber(point[0]);
          const value = toNumber(point[1]);
          return [ts, value];
        }

        if (typeof point === 'object' && point !== null) {
          const ts = toNumber(point.at ?? point[0]);
          const value = toNumber(point.value ?? point[1]);
          return [ts, value];
        }

        const ts = toNumber(point);
        return [ts, 0];
      });

      const base = {
        name: entry.name || `Series ${idx + 1}`,
        type: seriesType,
        data: sanitized,
        smooth: !isBar && !isDots,
        showSymbol: isDots,
        emphasis: { focus: 'series' }
      };

      if (isDots) {
        base.symbol = 'circle';
        base.symbolSize = 5;
      }
      if (isArea) base.areaStyle = { opacity: 0.12 };
      if (stacked && !isDots) base.stack = 'total';
      if (isBar) base.barMaxWidth = 26;
      const customColor =
        typeof entry.color === 'string' && entry.color.trim() !== '' ? entry.color.trim() : null;
      const paletteColor = palette.length ? palette[idx % palette.length] : null;
      const appliedColor = customColor || paletteColor;
      if (appliedColor) {
        base.itemStyle = { color: appliedColor };
        base.lineStyle = { color: appliedColor };
        if (isArea) base.areaStyle = { opacity: 0.12, color: appliedColor };
      }

      return base;
    });

    const gridBottom = showLegend ? 64 : 36;

    return {
      color: palette,
      animation: false,
      tooltip: {
        trigger: 'axis',
        axisPointer: { type: isBar ? 'shadow' : 'cross' }
      },
      legend: showLegend
        ? { bottom: 0, textStyle: { color: legendText } }
        : { show: false },
      grid: { left: 48, right: 20, top: 20, bottom: gridBottom },
      xAxis: {
        type: 'time',
        boundaryGap: isBar,
        axisLabel: { color: textColor },
        axisLine: { lineStyle: { color: axisLineColor } },
        splitLine: { lineStyle: { color: gridLineColor } }
      },
      yAxis: {
        type: 'value',
        name: yLabel || null,
        nameLocation: 'end',
        nameTextStyle: { color: textColor, padding: [0, 0, 0, 8] },
        axisLabel: { color: textColor },
        axisLine: { lineStyle: { color: axisLineColor } },
        splitLine: { lineStyle: { color: gridLineColor } }
      },
      series
    };
  },
  categoryOption(chartData, palette, theme) {
    const dataset = chartData.dataset || {};
    const data = Array.isArray(dataset.data) ? dataset.data : [];
    const chartType = (dataset.chart_type || 'bar').toLowerCase();
    const textColor = theme === 'dark' ? '#9CA3AF' : '#475569';
    const axisLineColor = theme === 'dark' ? '#374151' : '#E5E7EB';

    if (chartType === 'pie' || chartType === 'donut') {
      return {
        color: palette,
        animation: false,
        tooltip: { trigger: 'item' },
        legend: {
          orient: 'vertical',
          left: 'left',
          textStyle: { color: textColor }
        },
        series: [
          {
            type: 'pie',
            radius: chartType === 'donut' ? ['45%', '80%'] : ['0%', '72%'],
            center: ['55%', '55%'],
            data: data.map((entry, idx) => {
              const numeric = Number(entry.value ?? 0);
              const value = Number.isFinite(numeric) ? numeric : 0;
              const explicitColor =
                typeof entry.color === 'string' && entry.color.trim() !== '' ? entry.color.trim() : null;
              return {
                value,
                name: entry.name || `Slice ${idx + 1}`,
                itemStyle: explicitColor ? { color: explicitColor } : undefined
              };
            }),
            label: { color: textColor }
          }
        ]
      };
    }

    const categories = data.map((entry) => entry.name || '');
    const values = data.map((entry, idx) => {
      const numeric = Number(entry.value ?? 0);
      const value = Number.isFinite(numeric) ? numeric : 0;
      const explicitColor =
        typeof entry.color === 'string' && entry.color.trim() !== '' ? entry.color.trim() : null;
      const paletteColor = palette.length ? palette[idx % palette.length] : undefined;
      return {
        value,
        itemStyle: { color: explicitColor || paletteColor }
      };
    });

    return {
      color: palette,
      animation: false,
      tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
      grid: { left: 48, right: 20, top: 20, bottom: 32 },
      xAxis: {
        type: 'category',
        data: categories,
        axisLabel: { color: textColor },
        axisLine: { lineStyle: { color: axisLineColor } }
      },
      yAxis: {
        type: 'value',
        axisLabel: { color: textColor },
        axisLine: { lineStyle: { color: axisLineColor } },
        splitLine: { lineStyle: { color: axisLineColor } }
      },
      series: [
        {
          type: 'bar',
          data: values,
          barWidth: 32
        }
      ]
    };
  },
  createResizeObserver() {
    if (typeof ResizeObserver !== 'function') return;
    if (this.resizeObserver) return;
    this.resizeObserver = new ResizeObserver((entries) => {
      if (!Array.isArray(entries)) return;
      const entry = entries[0];
      if (!entry) return;
      const { width, height } = entry.contentRect || {};
      if (width > 0 && height > 0) {
        if (this.pendingRender) {
          this.pendingRender = false;
          this.render(true);
        } else if (this.chart && typeof this.chart.resize === 'function') {
          try { this.chart.resize(); } catch (_) {}
        }
      }
    });
    try {
      this.resizeObserver.observe(this.el);
    } catch (_) {
      this.destroyResizeObserver();
    }
  },
  destroyResizeObserver() {
    if (this.resizeObserver && typeof this.resizeObserver.disconnect === 'function') {
      try { this.resizeObserver.disconnect(); } catch (_) {}
    }
    this.resizeObserver = null;
  }
}


Hooks.DatabaseExploreChart = {
  _resolveTheme() {
    return document.documentElement.classList.contains('dark') ? 'dark' : 'default';
  },

  _normalizeColors(colors) {
    if (Array.isArray(colors)) return colors;
    if (typeof colors === 'string') {
      try { return JSON.parse(colors); } catch (_) { return []; }
    }
    return [];
  },

  _parseJson(value, fallback) {
    try {
      return value ? JSON.parse(value) : fallback;
    } catch (_) {
      return fallback;
    }
  },

  _bindThemeListener() {
    if (this._themeListenerBound) return;
    this._themeListenerBound = true;
    this.handleEvent('phx:theme-changed', () => this._handleThemeChanged());
  },

  _handleThemeChanged() {
    if (!this.chart || this.chart.isDisposed()) return;
    const themeName = this._resolveTheme();
    if (themeName !== this._currentThemeName && typeof this.chart.setTheme === 'function') {
      try {
        this.chart.setTheme(themeName);
        this._currentThemeName = themeName;
      } catch (_) {}
    }

    this._refreshChartFromDataset();
  },

  _buildOption(data, key, chartType, colors, selectedKeyColor) {
    const themeName = this._resolveTheme();
    const isDarkMode = themeName === 'dark';
    const colorArray = this._normalizeColors(colors);

    const isStacked = chartType === 'stacked';
    let series;
    if (isStacked) {
      series = (data && data.length > 0) ? data.map((seriesData, index) => ({
        name: seriesData.name,
        type: 'bar',
        stack: 'total',
        data: seriesData.data,
        itemStyle: {
          color: colorArray.length ? colorArray[index % colorArray.length] : undefined
        }
      })) : [];
    } else {
      const seriesColor = selectedKeyColor || colorArray[0];
      series = [{
        name: key || 'Data',
        type: 'bar',
        data: data || [],
        itemStyle: {
          color: seriesColor
        }
      }];
    }

    const textColor = isDarkMode ? '#9CA3AF' : '#6B7280';
    const axisLineColor = isDarkMode ? '#374151' : '#E5E7EB';

    return {
      backgroundColor: 'transparent',
      grid: {
        top: 8,
        bottom: 12,
        left: 32,
        right: 8,
        containLabel: true
      },
      textStyle: {
        color: textColor
      },
      tooltip: {
        trigger: 'item',
        axisPointer: {
          type: 'shadow'
        },
        backgroundColor: isDarkMode ? '#1F2937' : '#FFFFFF',
        borderColor: isDarkMode ? '#374151' : '#E5E7EB',
        textStyle: {
          color: isDarkMode ? '#F3F4F6' : '#1F2937'
        },
        appendToBody: true,
        extraCssText: 'z-index: 9999;',
        formatter: function(params) {
          const date = new Date(params.value[0]);
          const dateStr = echarts.format.formatTime('yyyy-MM-dd hh:mm:ss', date, false);
          const value = formatCompactNumber(params.value[1]);
          return `${dateStr}<br/>${params.marker} ${params.seriesName}: ${value}`;
        }
      },
      xAxis: {
        type: 'time',
        axisLine: {
          lineStyle: {
            color: axisLineColor
          }
        },
        axisLabel: {
          color: textColor,
          margin: 6,
          formatter: function(value) {
            const date = new Date(value);
            const hours = date.getHours();
            const minutes = date.getMinutes();

            if (hours === 0 && minutes === 0) {
              return echarts.format.formatTime('MM-dd', value, false);
            }
            return echarts.format.formatTime('hh:mm', value, false);
          }
        },
        splitLine: {
          show: false
        }
      },
      yAxis: {
        type: 'value',
        min: 0,
        axisLine: {
          lineStyle: {
            color: axisLineColor
          }
        },
        axisLabel: {
          color: textColor,
          margin: 6,
          formatter: (value) => formatCompactNumber(value)
        },
        splitLine: {
          lineStyle: {
            color: axisLineColor
          }
        }
      },
      series,
      animation: true,
      animationDuration: 300
    };
  },

  _applyOption(option) {
    if (!this.chart || this.chart.isDisposed() || !option) return;
    try {
      this.chart.setOption(option, true);
      this.chart.resize();
    } catch (_) {}
  },

  _refreshChartFromDataset() {
    if (!this.chart || this.chart.isDisposed()) return;
    const data = this._parseJson(this.el.dataset.events, []);
    const key = this.el.dataset.key;
    const chartType = this.el.dataset.chartType;
    const colors = this._parseJson(this.el.dataset.colors, []);
    const selectedKeyColor = this.el.dataset.selectedKeyColor;

    const option = this._buildOption(data, key, chartType, colors, selectedKeyColor);
    this._applyOption(option);
  },

  createChart(data, key, timezone, chartType, colors, selectedKeyColor) {
    // Initialize ECharts instance
    const themeName = this._resolveTheme();
    const initTheme = themeName === 'dark' ? 'dark' : undefined;
    const container = document.getElementById('timeline-chart');
    if (container) {
      container.style.height = '140px';
      container.style.width = '100%';
    }

    // Set theme based on dark mode
    this.chart = echarts.init(container, initTheme, withChartOpts({ height: 140 }));
    this._currentThemeName = themeName;
    this._bindThemeListener();

    // Build and apply the base option
    const option = this._buildOption(data, key, chartType, colors, selectedKeyColor);
    this._applyOption(option);

    // Handle window resize
    this.resizeHandler = () => {
      if (this.chart && !this.chart.isDisposed()) {
        this.chart.resize();
      }
    };
    window.addEventListener('resize', this.resizeHandler);
    
    // Handle theme changes
    return this.chart;
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
    let data = JSON.parse(this.el.dataset.events);
    let key = this.el.dataset.key;
    let timezone = this.el.dataset.timezone;
    let chartType = this.el.dataset.chartType;
    let colors = JSON.parse(this.el.dataset.colors);
    let selectedKeyColor = this.el.dataset.selectedKeyColor;

    // Check if chart type changed - if so, recreate the entire chart
    if (this.currentChartType !== chartType) {
      if (this.chart && !this.chart.isDisposed()) {
        this.chart.dispose();
      }
      this.chart = this.createChart(data, key, timezone, chartType, colors, selectedKeyColor);
      this.currentChartType = chartType;
      return;
    }

    // Update existing chart with new data
    if (this.chart && !this.chart.isDisposed()) {
      const option = this._buildOption(data, key, chartType, colors, selectedKeyColor);
      this._applyOption(option);
    }
  },

  destroyed() {
    // Remove resize handler
    if (this.resizeHandler) {
      window.removeEventListener('resize', this.resizeHandler);
    }

    // Dispose chart
    if (this.chart && !this.chart.isDisposed()) {
      this.chart.dispose();
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
        
        // Detect if we're in dark mode
        const isDarkMode = document.documentElement.classList.contains('dark');
        const highlightColor = isDarkMode ? '#334155' : '#f9fafb';
        
        // Highlight current cell's row header with important style
        const rowHeader = table.querySelector(`td[data-row="${row}"]:not([data-col])`);
        if (rowHeader) {
          rowHeader.style.backgroundColor = highlightColor;
          rowHeader.classList.add('table-highlight');
        }
        
        // Highlight current cell's column header
        const colHeader = table.querySelector(`th[data-col="${col}"]`);
        if (colHeader) {
          colHeader.style.backgroundColor = highlightColor;
          colHeader.classList.add('table-highlight');
        }
        
        // Highlight all cells in the same column
        const colCells = table.querySelectorAll(`td[data-col="${col}"]`);
        colCells.forEach(colCell => {
          colCell.style.backgroundColor = highlightColor;
          colCell.classList.add('table-highlight');
        });
        
        // Highlight all cells in the same row
        const rowCells = table.querySelectorAll(`td[data-row="${row}"]`);
        rowCells.forEach(rowCell => {
          rowCell.style.backgroundColor = highlightColor;
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

Hooks.Sortable = {
  mounted() {
    const group = this.el.dataset.group;
    const handle = this.el.dataset.handle;
    const eventName = this.el.dataset.event || "reorder_transponders";
    
    const groupName = group || 'default';
    // Restrict cross-type moves: only allow within same named group
    const groupOpt = { name: groupName, pull: [groupName], put: [groupName] };

    this.lastTo = null;
    this.lastHeader = null;

    this.sortable = Sortable.create(this.el, {
      group: groupOpt,
      handle: handle,
      draggable: '[data-id]',
      animation: 150,
      ghostClass: 'sortable-ghost',
      chosenClass: 'sortable-chosen',
      dragClass: 'sortable-drag',
      emptyInsertThreshold: 5,
      onMove: (evt, originalEvent) => {
        try {
          // Highlight drop container
          if (this.lastTo && this.lastTo !== evt.to) {
            this.lastTo.style.backgroundColor = '';
          }
          evt.to.style.backgroundColor = 'rgba(20,184,166,0.08)';
          this.lastTo = evt.to;

          // Highlight corresponding group header if present
          const pid = evt.to.dataset.parentId;
          if (pid) {
            const header = document.querySelector(`[data-group-header="${pid}"]`);
            if (this.lastHeader && this.lastHeader !== header) {
              this.lastHeader.style.backgroundColor = '';
            }
            if (header) {
              header.style.backgroundColor = 'rgba(20,184,166,0.10)';
              this.lastHeader = header;
            }
          }
        } catch (_) {}
      },
      onEnd: (evt) => {
        const parentId = evt.to.dataset.parentId || null;
        const fromParentId = evt.from.dataset.parentId || null;
        const movedId = evt.item && evt.item.dataset ? evt.item.dataset.id : null;
        const movedType = evt.item && evt.item.dataset ? evt.item.dataset.type : null;

        if (eventName === 'reorder_transponders') {
          const ids = Array.from(evt.to.children).map(child => child.dataset.id).filter(Boolean);
          this.pushEvent(eventName, { ids });
        } else {
          // Mixed nodes payload with type info
          const items = Array.from(evt.to.children)
            .map(child => (child.dataset && child.dataset.id) ? { id: child.dataset.id, type: child.dataset.type } : null)
            .filter(Boolean);
          const fromItems = Array.from(evt.from.children)
            .map(child => (child.dataset && child.dataset.id) ? { id: child.dataset.id, type: child.dataset.type } : null)
            .filter(Boolean);
          this.pushEvent(eventName, { items, parent_id: parentId, from_items: fromItems, from_parent_id: fromParentId, moved_id: movedId, moved_type: movedType });
        }

        // Clear highlights
        try {
          if (this.lastTo) this.lastTo.style.backgroundColor = '';
          if (this.lastHeader) this.lastHeader.style.backgroundColor = '';
          this.lastTo = null;
          this.lastHeader = null;
        } catch (_) {}
      }
    });
  },
  
  destroyed() {
    if (this.sortable) {
      this.sortable.destroy();
    }
  }
}

// Collapsible Dashboard Groups: sync collapsed state to localStorage
Hooks.DashboardGroupsCollapse = {
  mounted() {
    const dbId = this.el.dataset.dbId || 'default';
    const key = `dashboard_group_collapsed_${dbId}`;
    let map = {};
    try { map = JSON.parse(localStorage.getItem(key) || '{}'); } catch (_) { map = {}; }
    const ids = Object.keys(map).filter(id => map[id]);
    try { this.pushEvent('set_collapsed_groups', { ids }); } catch (_) {}
    this.handleEvent('save_collapsed_groups', ({ ids }) => {
      const store = {};
      (ids || []).forEach(id => { store[id] = true; });
      try { localStorage.setItem(key, JSON.stringify(store)); } catch (_) {}
    });
  }
}

Hooks.HomeSparkline = {
  mounted() {
    this.renderSparkline();
  },
  updated() {
    this.renderSparkline(true);
  },
  destroyed() {
    this.dispose();
  },
  disconnected() {
    this.dispose();
  },
  renderSparkline(force) {
    let series;
    try {
      series = JSON.parse(this.el.dataset.series || '[]');
    } catch (_) {
      series = [];
    }
    if (!Array.isArray(series)) series = [];

    if (!this.chart || force) {
      this.dispose();
      const height = this.el.clientHeight || 64;
      const theme = document.documentElement.classList.contains('dark') ? 'dark' : undefined;
      this.chart = echarts.init(this.el, theme, withChartOpts({ height }));
    }

    const lineColor = 'oklch(70.4% 0.14 182.503)';

    this.chart.setOption(
      {
        backgroundColor: 'transparent',
        grid: { top: 2, bottom: 2, left: 0, right: 0, containLabel: false },
        xAxis: { type: 'time', show: false },
        yAxis: {
          type: 'value',
          show: false,
          min: 0,
          max: (value) => (value.max === 0 ? 1 : value.max)
        },
        tooltip: { show: false },
        series: [
          {
            type: 'line',
            data: series,
            smooth: true,
            showSymbol: false,
            lineStyle: { width: 2, color: lineColor },
            areaStyle: { color: lineColor, opacity: 0.0 },
            animation: false
          }
        ],
        animation: false
      },
      true
    );

    try {
      this.chart.resize();
    } catch (_) {}
  },
  dispose() {
    if (this.chart) {
      try {
        this.chart.dispose();
      } catch (_) {}
      this.chart = null;
    }
  }
}

// Generic file download handler via pushEvent
Hooks.FileDownload = {
  mounted() {
    this.handleEvent('file_download', ({ content, content_base64, base64, filename, type }) => {
      try {
        let blob;
        if (base64 || content_base64) {
          const b64 = content_base64 || content || '';
          const bytes = this._b64ToUint8Array(b64);
          blob = new Blob([bytes], { type: type || 'application/octet-stream' });
        } else {
          blob = new Blob([content || ''], { type: type || 'application/octet-stream' });
        }
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename || 'download';
        document.body.appendChild(a);
        a.click();
        setTimeout(() => {
          URL.revokeObjectURL(url);
          document.body.removeChild(a);
        }, 0);
        // Notify any listeners that a download was initiated
        window.dispatchEvent(new CustomEvent('download:complete'));
      } catch (e) {
        console.error('File download failed', e);
      }
    });

    this.handleEvent('file_download_url', ({ url, filename, target }) => {
      try {
        if (!url) throw new Error('Missing url');
        // Prefer hidden iframe to avoid interfering with LiveView navigation
        const iframe = document.createElement('iframe');
        iframe.style.display = 'none';
        iframe.src = url;
        iframe.addEventListener('load', () => {
          window.dispatchEvent(new CustomEvent('download:complete'));
        });
        document.body.appendChild(iframe);
        // Safety cleanup
        setTimeout(() => { try { document.body.removeChild(iframe); } catch (_) {} }, 60000);
        // Note: Avoid forcing navigation to keep LiveView intact
      } catch (e) {
        console.error('File download url failed', e);
      }
    });

    this.handleEvent('export_dashboard_pdf', ({ title, timeframe, granularity }) => {
      try {
        const root = document.documentElement;
        const wasDark = root.classList.contains('dark');
        if (wasDark) root.classList.remove('dark');

        const header = document.createElement('div');
        header.id = 'dashboard-print-header';
        header.style.background = '#ffffff';
        header.style.color = '#0f172a';
        header.style.padding = '16px 24px';
        header.style.borderBottom = '1px solid #e5e7eb';
        header.style.fontFamily = 'ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, Helvetica Neue, Arial';
        header.innerHTML = `
          <div style="max-width: 1024px; margin: 0 auto;">
            <div style="font-size: 18px; font-weight: 600;">${this.escapeHtml(title || 'Dashboard')}</div>
            <div style="margin-top: 6px; font-size: 12px; color: #475569;">
              ${timeframe ? this.escapeHtml(timeframe) + ' • ' : ''}Granularity: ${this.escapeHtml(granularity || '')}
            </div>
          </div>
        `;
        document.body.prepend(header);

        const cleanup = () => {
          try { header.remove(); } catch (_) {}
          if (wasDark) root.classList.add('dark');
          window.removeEventListener('afterprint', cleanup);
        };
        window.addEventListener('afterprint', cleanup);
        setTimeout(() => window.print(), 50);
      } catch (e) {
        console.error('PDF export failed', e);
      }
    });
  },

  escapeHtml(str) { return String(str || '').replace(/[&<>"']/g, (s) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[s])); },

  _b64ToUint8Array(b64) {
    const binary = atob(b64);
    const len = binary.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }
};

// Download menu: close on click, show loading state until iframe loads
Hooks.DownloadMenu = {
  mounted() {
    this.loading = false;
    this.setElements();
    const datasetLabel = (this.el.dataset && this.el.dataset.defaultLabel) || '';
    this.originalLabel = datasetLabel || (this.label ? this.label.textContent : '');
    this.loadingLabel = (this.el.dataset && this.el.dataset.loadingLabel) || 'Exporting…';
    this.iframe = document.querySelector('iframe[name="download_iframe"]');
    this.hrefSignature = this.computeHrefSignature();

    this.bindAnchors();
    this.bindIframe();

    this.handleEvent('monitor_widget_export_params', ({ params }) => {
      this.updateExportLinks(params || {});
    });

    // Global completion signal (for blob-based downloads or alternate flows)
    this._onDownloadComplete = () => this.stopLoading();
    window.addEventListener('download:complete', this._onDownloadComplete);
  },

  updated() {
    // Rebind anchors when dropdown content re-renders and reselect elements that may have been replaced
    this.setElements();
    const datasetLabel = (this.el.dataset && this.el.dataset.defaultLabel) || '';
    if (datasetLabel) {
      this.originalLabel = datasetLabel;
    } else if (!this.originalLabel && this.label) {
      this.originalLabel = this.label.textContent;
    }

    const newSignature = this.computeHrefSignature();
    if (newSignature !== this.hrefSignature) {
      this.hrefSignature = newSignature;
      if (!this.loading) {
        this.stopLoading(true);
      }
    }

    this.bindAnchors();
    // Rebind iframe in case it was re-rendered
    const newIframe = document.querySelector('iframe[name="download_iframe"]');
    if (newIframe !== this.iframe) {
      this.iframe = newIframe;
      this._iframeBound = false;
      this.bindIframe();
    }
    // If still loading, re-apply loading UI state after LV patch
    if (this.loading) this.applyLoadingState();
  },

  updateExportLinks(params) {
    if (!params || typeof params !== 'object') return;
    const managedKeys = ['timeframe', 'granularity', 'from', 'to', 'segments', 'key'];
    this.el.querySelectorAll('a[data-export-link]').forEach((a) => {
      const href = a.getAttribute('href');
      if (!href) return;
      try {
        const url = new URL(href, window.location.origin);
        managedKeys.forEach((key) => {
          const value = params[key];
          if (value == null || value === '') {
            url.searchParams.delete(key);
          }
        });
        Object.entries(params).forEach(([key, value]) => {
          if (value == null || value === '') {
            url.searchParams.delete(key);
          } else {
            url.searchParams.set(key, value);
          }
        });
        url.searchParams.delete('download_token');
        a.setAttribute('href', url.toString());
      } catch (_) {
        // Ignore malformed hrefs
      }
    });
    this.hrefSignature = this.computeHrefSignature();
  },

  computeHrefSignature() {
    return Array.from(this.el.querySelectorAll('a[data-export-link]'))
      .map((a) => a.getAttribute('href') || '')
      .join('|');
  },

  bindAnchors() {
    if (this._bound) {
      return;
    }
    this._bound = true;
    this._onClickCapture = (e) => {
      const a = e.target.closest('a[data-export-link]');
      const btn = e.target.closest('button[data-export-trigger]');
      if (!this.el.contains(e.target)) return; // Only handle clicks within this menu
      if (a) {
        this.startLoading();
        setTimeout(() => this.pushEvent('hide_export_dropdown', {}), 0);
        return;
      }
      if (!btn) return;
      // Separate loading instance for button-triggered exports
      this.loading = true;
      this.applyLoadingState();
      // Generate token so iframe poller knows when to reset for button-trigger downloads
      const token = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      this._downloadToken = token;
      try { window.__downloadToken = token; } catch (_) {}
      this.pushEvent('hide_export_dropdown', {});
      // Start polling for the cookie to flip back UI when done
      this.startCookiePolling();
    };
    // Use capture phase to run before LiveView's phx-click-away handler
    document.addEventListener('click', this._onClickCapture, true);
  },

  bindIframe() {
    if (!this.iframe || this._iframeBound) return;
    this._iframeBound = true;
    this.iframe.addEventListener('load', () => {
      // Any load in the download iframe marks completion
      this.stopLoading();
    });
  },

  startLoading() {
    if (this.loading) return;
    this.loading = true;
    this.applyLoadingState();
  },

  stopLoading(force = false) {
    if (!this.loading && !force) return;
    this.loading = false;
    this.stopCookiePolling();
    if (this.button) {
      this.button.removeAttribute('data-loading');
      this.button.removeAttribute('aria-busy');
      this.button.classList.remove('opacity-70', 'cursor-wait');
      this.button.disabled = false;
    }
    const datasetLabel = (this.el.dataset && this.el.dataset.defaultLabel) || '';
    if (this.icon) this.icon.classList.remove('hidden');
    if (this.spinner) this.spinner.classList.add('hidden');
    if (this.label) this.label.textContent = this.originalLabel || datasetLabel || 'Download';
  },

  applyLoadingState() {
    if (this.button) {
      this.button.setAttribute('aria-busy', 'true');
      this.button.setAttribute('data-loading', 'true');
      this.button.classList.add('opacity-70', 'cursor-wait');
      this.button.disabled = true;
    }
    if (this.icon) this.icon.classList.add('hidden');
    if (this.spinner) this.spinner.classList.remove('hidden');
    if (this.label) this.label.textContent = this.loadingLabel;
  },

  startCookiePolling() {
    this.stopCookiePolling();
    const token = this._downloadToken;
    if (!token) return;
    const deadline = Date.now() + 60000; // 60s timeout
    this._cookieTimer = setInterval(() => {
      try {
        const cookieEntry = document.cookie.split('; ').find((c) => c.startsWith('download_token='));
        if (cookieEntry) {
          const val = decodeURIComponent(cookieEntry.split('=')[1] || '');
          const expected = token || (window.__downloadToken || '');
          if (!expected || val === expected) {
            // Clear cookie and stop loading
            document.cookie = 'download_token=; Max-Age=0; path=/';
            this.stopLoading();
          }
        }
        if (Date.now() > deadline) {
          // Fallback timeout
          this.stopLoading();
        }
      } catch (_) {
        // ignore
      }
    }, 500);
  },

  stopCookiePolling() {
    if (this._cookieTimer) {
      clearInterval(this._cookieTimer);
      this._cookieTimer = null;
    }
  },

  setElements() {
    this.button = this.el.querySelector('[data-role="download-button"]');
    this.label = this.el.querySelector('[data-role="download-text"]');
    this.icon = this.el.querySelector('[data-role="download-icon"]');
    this.spinner = this.el.querySelector('[data-role="download-spinner"]');
  },

  destroyed() {
    if (this._onClickCapture) {
      document.removeEventListener('pointerdown', this._onClickCapture, true);
      document.removeEventListener('click', this._onClickCapture, true);
    }
    if (this._onDownloadComplete) {
      window.removeEventListener('download:complete', this._onDownloadComplete);
    }
    this.stopCookiePolling();
  }
}

// Widget export dropdown helpers (non-LiveView toggled)
window.TrifleDownloads = window.TrifleDownloads || {};
(function (scope) {
  const HIDDEN_CLASS = 'hidden';

  const queryDropdown = (menu) => (menu ? menu.querySelector('[data-widget-dropdown]') : null);
  const queryButton = (menu) => (menu ? menu.querySelector('[data-role="download-button"]') : null);

  scope.closeWidgetMenu = function closeWidgetMenu(menu) {
    if (!menu) return;
    const dropdown = queryDropdown(menu);
    if (dropdown) {
      dropdown.classList.add(HIDDEN_CLASS);
      dropdown.setAttribute('aria-hidden', 'true');
    }
    const button = queryButton(menu);
    if (button) button.setAttribute('aria-expanded', 'false');
    menu.dataset.open = 'false';
  };

  scope.closeAllWidgetMenus = function closeAllWidgetMenus(exceptMenu) {
    document
      .querySelectorAll('[data-widget-download-menu][data-open="true"]')
      .forEach((menu) => {
        if (exceptMenu && menu === exceptMenu) return;
        scope.closeWidgetMenu(menu);
      });
  };

  scope.toggleWidgetMenu = function toggleWidgetMenu(button) {
    if (!button) return;
    const menu = button.closest('[data-widget-download-menu]');
    if (!menu) return;
    const dropdown = queryDropdown(menu);
    if (!dropdown) return;
    const isOpen = menu.dataset.open === 'true';
    if (isOpen) {
      scope.closeWidgetMenu(menu);
      return;
    }
    scope.closeAllWidgetMenus(menu);
    dropdown.classList.remove(HIDDEN_CLASS);
    dropdown.setAttribute('aria-hidden', 'false');
    menu.dataset.open = 'true';
    button.setAttribute('aria-expanded', 'true');
  };

  scope.handleWidgetExportClick = function handleWidgetExportClick(link) {
    if (!link) return;
    const menu = link.closest('[data-widget-download-menu]');
    if (menu) {
      const dropdown = queryDropdown(menu);
      if (dropdown) {
        dropdown.classList.add(HIDDEN_CLASS);
        dropdown.setAttribute('aria-hidden', 'true');
      }
      menu.dataset.open = 'false';
      const button = queryButton(menu);
      if (button) {
        button.setAttribute('aria-expanded', 'false');
      }
    }
    try {
      const url = new URL(link.getAttribute('href') || '', window.location.origin);
      if (!url.searchParams.get('download_token')) {
        const token = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
        window.__downloadToken = token;
        url.searchParams.set('download_token', token);
        link.href = url.toString();
      }
    } catch (_) {
      // ignore malformed URLs
    }
  };

  document.addEventListener('click', (event) => {
    if (event.defaultPrevented) return;
    const menu = event.target.closest('[data-widget-download-menu]');
    if (!menu) {
      scope.closeAllWidgetMenus();
    }
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      scope.closeAllWidgetMenus();
    }
  });
})(window.TrifleDownloads);

Hooks.PathAutocomplete = {
  mounted() {
    this.input = this.el.querySelector('[data-role="path-input"]');
    this.suggestionBox = this.el.querySelector('[data-role="suggestions"]');
    this.matches = [];
    this.activeIndex = -1;
    this.visible = false;
    this.suppressNextFilter = false;

    this.loadOptions();

    if (!this.input || !this.suggestionBox) return;

    this.handleInput = () => this.filterSuggestions();
    this.handleFocus = () => this.openSuggestions();
    this.handleBlur = () => {
      this._blurTimer = setTimeout(() => this.hideSuggestions(), 100);
    };
    this.handleKeydown = (event) => this.onKeydown(event);

    this.input.addEventListener('input', this.handleInput);
    this.input.addEventListener('focus', this.handleFocus);
    this.input.addEventListener('blur', this.handleBlur);
    this.input.addEventListener('keydown', this.handleKeydown);

    // Show initial matches if input already has a value
    if (document.activeElement === this.input) {
      this.filterSuggestions();
    }
  },

  updated() {
    const previous = JSON.stringify(this.options || []);
    this.loadOptions();
    if (JSON.stringify(this.options) !== previous) {
      this.filterSuggestions();
    }
  },

  destroyed() {
    if (!this.input) return;
    this.input.removeEventListener('input', this.handleInput);
    this.input.removeEventListener('focus', this.handleFocus);
    this.input.removeEventListener('blur', this.handleBlur);
    this.input.removeEventListener('keydown', this.handleKeydown);
    if (this._blurTimer) clearTimeout(this._blurTimer);
  },

  loadOptions() {
    const raw = this.el.dataset.paths || '[]';
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (_) {
      parsed = [];
    }

    if (!Array.isArray(parsed)) parsed = [];

    this.options = parsed
      .map((item) => {
        if (typeof item === 'string') {
          return { value: item, label: item };
        }

        if (item && typeof item.value === 'string') {
          return {
            value: item.value,
            label: typeof item.label === 'string' ? item.label : item.value
          };
        }

        return null;
      })
      .filter(Boolean);
  },

  filterSuggestions() {
    if (this.suppressNextFilter) {
      this.suppressNextFilter = false;
      return;
    }

    if (!this.input) return;

    const hasFocus = document.activeElement === this.input;
    if (!hasFocus) {
      this.hideSuggestions();
      return;
    }

    const query = (this.input.value || '').trim().toLowerCase();

    let candidates = this.options;
    if (query) {
      candidates = this.options.filter((item) =>
        item.value.toLowerCase().includes(query)
      );
    }

    const limited = candidates.slice(0, 15);
    if (limited.length === 0) {
      this.hideSuggestions();
      return;
    }

    this.renderSuggestions(limited);
  },

  renderSuggestions(items) {
    if (!this.suggestionBox) return;

    this.matches = items;
    this.activeIndex = -1;

    const fragment = document.createDocumentFragment();

    items.forEach((item, index) => {
      const option = document.createElement('button');
      option.type = 'button';
      option.className = 'w-full px-3 py-2 text-left text-sm leading-tight text-slate-700 hover:bg-teal-50 focus:outline-none dark:text-slate-200 dark:hover:bg-slate-700';
      option.setAttribute('role', 'option');
      option.dataset.index = index;
      option.dataset.value = item.value;
      option.innerHTML = item.label;

      option.addEventListener('mousedown', (event) => {
        event.preventDefault();
        this.selectOption(index);
      });

      fragment.appendChild(option);
    });

    this.suggestionBox.innerHTML = '';
    this.suggestionBox.appendChild(fragment);
    this.suggestionBox.classList.remove('hidden');
    this.visible = true;
  },

  openSuggestions() {
    if (this._blurTimer) clearTimeout(this._blurTimer);
    this.filterSuggestions();
  },

  hideSuggestions() {
    if (!this.suggestionBox) return;
    this.suggestionBox.classList.add('hidden');
    this.suggestionBox.innerHTML = '';
    this.visible = false;
    this.matches = [];
    this.activeIndex = -1;
  },

  onKeydown(event) {
    if (!this.visible && (event.key === 'ArrowDown' || event.key === 'ArrowUp')) {
      this.filterSuggestions();
    }

    if (!this.visible) return;

    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault();
        this.moveActive(1);
        break;
      case 'ArrowUp':
        event.preventDefault();
        this.moveActive(-1);
        break;
      case 'Enter':
        if (this.activeIndex >= 0) {
          event.preventDefault();
          this.selectOption(this.activeIndex);
        }
        break;
      case 'Escape':
        this.hideSuggestions();
        break;
      default:
        break;
    }
  },

  moveActive(delta) {
    if (this.matches.length === 0 || !this.suggestionBox) return;

    const nextIndex = (this.activeIndex + delta + this.matches.length) % this.matches.length;
    this.setActive(nextIndex);
  },

  setActive(index) {
    if (!this.suggestionBox) return;

    const buttons = Array.from(this.suggestionBox.querySelectorAll('button[data-index]'));
    buttons.forEach((btn) => {
      btn.classList.remove('bg-teal-100', 'dark:bg-slate-600');
    });

    const active = buttons[index];
    if (active) {
      active.classList.add('bg-teal-100', 'dark:bg-slate-600');
      active.scrollIntoView({ block: 'nearest' });
      this.activeIndex = index;
    }
  },

  selectOption(index) {
    const item = this.matches[index];
    if (!item || !this.input) return;

    this.input.value = item.value;
    this.suppressNextFilter = true;
    this.hideSuggestions();

    const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
    if (nativeInputValueSetter) {
      nativeInputValueSetter.call(this.input, item.value);
    }

    this.input.dispatchEvent(new Event('input', { bubbles: true }));
    this.input.dispatchEvent(new Event('change', { bubbles: true }));
  }
}

Hooks.TimeseriesPaths = {
  mounted() {
    this.widgetId = this.el.dataset.widgetId;

    this.handleClick = (event) => {
      const button = event.target.closest('[data-action]');
      if (!button) return;

      const action = button.dataset.action;
      if (!action) return;

      event.preventDefault();

      const paths = this.readPaths();

      if (action === 'add') {
        paths.push('');
      } else if (action === 'remove') {
        const index = parseInt(button.dataset.index || '-1', 10);
        if (!Number.isNaN(index)) {
          paths.splice(index, 1);
        }
        if (paths.length === 0) {
          paths.push('');
        }
      } else {
        return;
      }

      this.pushEvent('timeseries_paths_update', {
        widget_id: this.widgetId,
        paths
      });
    };

    this.el.addEventListener('click', this.handleClick);
  },

  updated() {
    this.widgetId = this.el.dataset.widgetId;
  },

  destroyed() {
    if (this.handleClick) {
      this.el.removeEventListener('click', this.handleClick);
    }
  },

  readPaths() {
    return Array.from(this.el.querySelectorAll('input[name="ts_paths[]"]')).map((input) =>
      input.value || ''
    );
  }
}

Hooks.CategoryPaths = {
  mounted() {
    this.widgetId = this.el.dataset.widgetId;
    this.inputName = this.el.dataset.pathInputName || 'cat_paths[]';
    this.eventName = this.el.dataset.eventName || 'category_paths_update';

    this.handleClick = (event) => {
      const button = event.target.closest('[data-action]');
      if (!button) return;

      const action = button.dataset.action;
      if (!action) return;

      event.preventDefault();

      const paths = this.readPaths();

      if (action === 'add') {
        paths.push('');
      } else if (action === 'remove') {
        const index = parseInt(button.dataset.index || '-1', 10);
        if (!Number.isNaN(index)) {
          paths.splice(index, 1);
        }
        if (paths.length === 0) paths.push('');
      } else {
        return;
      }

      this.pushEvent(this.eventName, {
        widget_id: this.widgetId,
        paths
      });
    };

    this.el.addEventListener('click', this.handleClick);
  },

  updated() {
    this.widgetId = this.el.dataset.widgetId;
    this.inputName = this.el.dataset.pathInputName || 'cat_paths[]';
    this.eventName = this.el.dataset.eventName || 'category_paths_update';
  },

  destroyed() {
    if (this.handleClick) {
      this.el.removeEventListener('click', this.handleClick);
    }
  },

  readPaths() {
    return Array.from(this.el.querySelectorAll(`input[name="${this.inputName}"]`)).map((input) =>
      input.value || ''
    );
  }
}


Hooks.PhantomRows = {
  mounted() {
    this.addPhantomRows();
  },
  
  updated() {
    this.addPhantomRows();
  },
  
  addPhantomRows() {
    // Remove existing phantom rows
    this.clearPhantomRows();
    
    const container = this.el;
    const scrollContainer = container.querySelector('[data-role="table-scroll"]');
    const table = scrollContainer ? scrollContainer.querySelector('[data-role="data-table"]') : null;
    if (!table || !scrollContainer) return;
    
    // Fix border width to match table width
    const borderDiv = scrollContainer.querySelector('[data-role="table-border"]');
    if (borderDiv) {
      const tableWidth = table.scrollWidth;
      borderDiv.style.width = `${tableWidth}px`;
      borderDiv.style.minWidth = '100%';
    }
    
    // Get dimensions
    const scrollRect = scrollContainer.getBoundingClientRect();
    const table2Bottom = scrollContainer.scrollTop + table.offsetHeight;
    const scrollHeight = scrollContainer.scrollHeight;
    const clientHeight = scrollContainer.clientHeight;
    
    // Calculate if we need phantom rows (table + borders is shorter than visible area)
    const borderHeight = borderDiv ? borderDiv.offsetHeight : 0;
    const totalContentHeight = table.offsetHeight + borderHeight;
    
    if (totalContentHeight < clientHeight) {
      const remainingSpace = clientHeight - totalContentHeight;
      this.createPhantomRowsElement(remainingSpace, scrollContainer);
    }
  },
  
  createPhantomRowsElement(height, scrollContainer) {
    const table = scrollContainer.querySelector('[data-role="data-table"]');
    const tableWidth = table ? table.scrollWidth : scrollContainer.scrollWidth;
    
    const phantomContainer = document.createElement('div');
    phantomContainer.className = 'phantom-rows-js';
    
    // Create horizontal stripes background
    const isDark = document.documentElement.classList.contains('dark');
    const stripeColor = isDark ? 'rgb(71 85 105)' : 'rgb(229 231 235)';
    const bgColor = isDark ? 'transparent' : 'transparent';
    
    phantomContainer.style.cssText = `
      height: ${height}px;
      width: ${tableWidth}px;
      min-width: 100%;
      background-image: repeating-linear-gradient(
        to bottom,
        ${bgColor} 0px,
        ${bgColor} 23px,
        ${stripeColor} 23px,
        ${stripeColor} 24px
      );
      pointer-events: none;
    `;
    
    // Append to scroll container, right after the border
    const borderDiv = scrollContainer.querySelector('[data-role="table-border"]');
    if (borderDiv && borderDiv.nextSibling) {
      scrollContainer.insertBefore(phantomContainer, borderDiv.nextSibling);
    } else {
      scrollContainer.appendChild(phantomContainer);
    }
  },
  
  clearPhantomRows() {
    const existing = this.el.querySelectorAll('.phantom-rows-js');
    existing.forEach(el => el.remove());
  }
}

Hooks.FastTooltip = {
  mounted() {
    this.initTooltips();
  },
  
  updated() {
    this.initTooltips();
  },
  
  initTooltips() {
    // Remove existing tooltips
    document.querySelectorAll('.fast-tooltip').forEach(el => el.remove());
    
    const tooltipElements = this.el.querySelectorAll('[data-tooltip]');
    
    tooltipElements.forEach(el => {
      el.addEventListener('mouseenter', (e) => {
        this.showTooltip(e.target, e.target.dataset.tooltip);
      });
      
      el.addEventListener('mouseleave', (e) => {
        this.hideTooltip();
      });
    });
  },
  
  showTooltip(element, text) {
    // Detect dark mode
    const isDarkMode = document.documentElement.classList.contains('dark');
    const backgroundColor = isDarkMode ? '#0f172a' : '#374151';
    const textColor = isDarkMode ? '#ffffff' : '#ffffff';
    
    // Create tooltip element
    const tooltip = document.createElement('div');
    tooltip.className = 'fast-tooltip';
    tooltip.textContent = text;
    tooltip.style.cssText = `
      position: absolute;
      background: ${backgroundColor};
      color: ${textColor};
      padding: 4px 8px;
      border-radius: 4px;
      font-size: 12px;
      z-index: 1000;
      pointer-events: none;
      white-space: nowrap;
      box-shadow: 0 1px 4px rgba(0,0,0,0.1);
    `;
    
    document.body.appendChild(tooltip);
    
    // Position tooltip
    const rect = element.getBoundingClientRect();
    const tooltipRect = tooltip.getBoundingClientRect();
    
    let left = rect.left + (rect.width / 2) - (tooltipRect.width / 2) + window.scrollX;
    let top = rect.top - tooltipRect.height - 8 + window.scrollY;
    
    // Keep tooltip within viewport
    if (left < 8) left = 8;
    if (left + tooltipRect.width > window.innerWidth - 8) {
      left = window.innerWidth - tooltipRect.width - 8;
    }
    if (top < 8 + window.scrollY) {
      top = rect.bottom + 8 + window.scrollY;
    }
    
    tooltip.style.left = left + 'px';
    tooltip.style.top = top + 'px';
  },
  
  hideTooltip() {
    document.querySelectorAll('.fast-tooltip').forEach(el => el.remove());
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
    // Copy completed
  })
})

// Theme Management
class ThemeManager {
  constructor() {
    this.init();
  }

  init() {
    // Apply theme on page load
    this.applyTheme();
    
    // Listen for theme changes from LiveView
    window.addEventListener("phx:theme-changed", (event) => {
      this.applyTheme(event.detail.theme);
    });

    // Listen for system theme changes
    if (window.matchMedia) {
      const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
      mediaQuery.addEventListener('change', () => {
        // Only apply system theme change if user has system preference
        const currentTheme = document.body.getAttribute('data-theme') || 'system';
        if (currentTheme === 'system') {
          this.applyTheme();
        }
      });
    }
  }

  shouldUseDarkTheme(themePreference = null) {
    const body = document.body;
    const preload = window.__TRIFLE_THEME_PRELOAD__ || {};
    const currentTheme = themePreference || preload.pref || body.getAttribute('data-theme') || 'system';
    
    let shouldUseDark;
    switch (currentTheme) {
      case 'dark':
        shouldUseDark = true;
        break;
      case 'light':
        shouldUseDark = false;
        break;
      case 'system':
      default:
        // Check system preference
        shouldUseDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
        break;
    }
    
    return shouldUseDark;
  }

  applyTheme(themePreference = null) {
    const body = document.body;
    const preload = window.__TRIFLE_THEME_PRELOAD__ || {};
    const currentTheme = themePreference || preload.pref || body.getAttribute('data-theme') || 'system';
    const shouldUseDark = this.shouldUseDarkTheme(currentTheme);
    const resolvedTheme = shouldUseDark ? 'dark' : 'light';
    const previousTheme = this._resolvedTheme;

    // Update data-theme attribute if preference was provided
    if (themePreference) {
      body.setAttribute('data-theme', themePreference);
    } else if (body.getAttribute('data-theme') !== currentTheme) {
      body.setAttribute('data-theme', currentTheme);
    }
    
    // Remove existing theme classes
    body.classList.remove('dark');
    document.documentElement.classList.remove('dark');

    // Apply theme classes based on user preference
    if (shouldUseDark) {
      body.classList.add('dark');
      document.documentElement.classList.add('dark');
    }

    this._resolvedTheme = resolvedTheme;
    try {
      if (window.localStorage) {
        window.localStorage.setItem('trifle:theme-pref', currentTheme);
        window.localStorage.setItem('trifle:resolved-theme', resolvedTheme);
      }
    } catch (_) {}

    window.__TRIFLE_THEME_PRELOAD__ = { pref: currentTheme, resolved: resolvedTheme };
    if (previousTheme !== resolvedTheme) {
      try {
        window.dispatchEvent(new CustomEvent('trifle:theme-changed', { detail: { theme: resolvedTheme } }));
      } catch (_) {}
    }
  }

}

// Initialize theme manager when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  window.themeManager = new ThemeManager();
});
