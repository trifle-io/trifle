import { formatCompactNumber } from "./formatting";

export const normalizeHexColor = (color) => {
  if (typeof color !== 'string') return null;
  const trimmed = color.trim();
  const full = trimmed.match(/^#([0-9a-f]{6})$/i);
  if (full) return `#${full[1].toLowerCase()}`;

  const short = trimmed.match(/^#([0-9a-f]{3})$/i);
  if (!short) return null;
  const [r, g, b] = short[1].toLowerCase().split('');
  return `#${r}${r}${g}${g}${b}${b}`;
};

export const hexToRgb = (hexColor) => {
  const normalized = normalizeHexColor(hexColor);
  if (!normalized) return null;
  const hex = normalized.slice(1);
  return {
    r: parseInt(hex.slice(0, 2), 16),
    g: parseInt(hex.slice(2, 4), 16),
    b: parseInt(hex.slice(4, 6), 16)
  };
};

export const pickHeatmapBaseColor = (seriesList, fallbackColor = null) => {
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

export const heatmapColorScale = (baseColor, isDarkMode) => {
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

export const heatmapColorWithAlpha = (hexColor, alpha) => {
  const rgb = hexToRgb(hexColor);
  if (!rgb) return null;
  const safeAlpha = Number.isFinite(alpha) ? Math.max(0, Math.min(1, alpha)) : 1;
  return `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${safeAlpha})`;
};

export const normalizeHeatmapColorMode = (value) => {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'single' || normalized === 'palette' || normalized === 'diverging') return normalized;
  return 'auto';
};

export const normalizeHeatmapColorConfig = (config, fallbackSingleColor = '#14b8a6') => {
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

export const heatmapPaletteScale = (paletteId, isDarkMode) => {
  const palette = HEATMAP_PALETTES[paletteId] || HEATMAP_PALETTES.default;
  if (!Array.isArray(palette) || !palette.length) return heatmapColorScale('#14b8a6', isDarkMode);
  const start = heatmapColorWithAlpha(palette[0], isDarkMode ? 0.08 : 0.05) || palette[0];
  return [start, ...palette];
};

export const resolveHeatmapVisualMap = ({
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

export const heatmapFocusItemStyle = (isDarkMode) => ({
  shadowBlur: isDarkMode ? 16 : 12,
  shadowColor: isDarkMode ? 'rgba(248, 250, 252, 0.45)' : 'rgba(15, 23, 42, 0.35)',
  shadowOffsetX: 0,
  shadowOffsetY: 0
});

export const buildBucketIndexMap = (labels) => {
  const map = new Map();
  (Array.isArray(labels) ? labels : []).forEach((label, idx) => {
    map.set(String(label), idx);
  });
  return map;
};

export const distributionSeriesName = (seriesItem, idx) => {
  const rawName =
    typeof (seriesItem && seriesItem.name) === 'string'
      ? seriesItem.name.trim()
      : '';
  return rawName !== '' ? rawName : `Series ${idx + 1}`;
};

export const buildDistributionHeatmapAggregation = ({
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

export const buildDistributionScatterSeries = ({
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

export const aggregateHeatmapBreakdown = (entries) => {
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

const escapeHeatmapHtml = (value) =>
  String(value == null ? '' : value).replace(/[&<>"']/g, (char) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#039;'
  }[char]));

export const formatHeatmapTooltip = ({
  params,
  labels,
  verticalLabels,
  breakdownByCell,
  escapeHtml
}) => {
  const safeLabels = Array.isArray(labels) ? labels : [];
  const safeVerticalLabels = Array.isArray(verticalLabels) ? verticalLabels : [];
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
  const xLabel = xIdx != null && safeLabels[xIdx] ? safeLabels[xIdx] : safeLabels[0] || '';
  const yLabel = yIdx != null && safeVerticalLabels[yIdx] ? safeVerticalLabels[yIdx] : safeVerticalLabels[0] || '';
  if (!xLabel && !yLabel) return '';

  const key = `${xIdx}:${yIdx}`;
  const breakdown =
    breakdownByCell instanceof Map && Array.isArray(breakdownByCell.get(key))
      ? breakdownByCell.get(key)
      : [];

  const safeEscape = typeof escapeHtml === 'function' ? escapeHtml : escapeHeatmapHtml;

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

export const buildHeatmapOptions = ({
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
}) => {
  const safeLabels = Array.isArray(labels) ? labels : [];
  const safeVerticalLabels = Array.isArray(verticalLabels) ? verticalLabels : [];
  const safeVisualSettings = visualSettings && typeof visualSettings === 'object' ? visualSettings : {};
  const visualMapMin = Number.isFinite(Number(safeVisualSettings.min)) ? Number(safeVisualSettings.min) : 0;
  const visualMapMax = Number.isFinite(Number(safeVisualSettings.max)) ? Number(safeVisualSettings.max) : visualMapMin;
  const visualMapColors = Array.isArray(safeVisualSettings.colorScale) && safeVisualSettings.colorScale.length
    ? safeVisualSettings.colorScale
    : undefined;

  return {
  backgroundColor: 'transparent',
  legend: { show: false },
  tooltip: {
    trigger: 'item',
    appendToBody: true,
    formatter: (params) =>
      formatHeatmapTooltip({
        params,
        labels: safeLabels,
        verticalLabels: safeVerticalLabels,
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
    data: safeLabels,
    splitLine: {
      show: true,
      lineStyle: {
        type: 'dashed',
        color: isDarkMode ? '#1f2937' : '#e2e8f0',
        opacity: isDarkMode ? 0.4 : 0.9
      }
    },
    axisLabel: { color: isDarkMode ? '#CBD5F5' : '#475569', interval: 0, rotate: safeLabels.length > 8 ? 30 : 0 }
  },
  yAxis: {
    type: 'category',
    data: safeVerticalLabels,
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
        min: visualMapMin,
        max: visualMapMax,
        calculable: false,
        orient: 'horizontal',
        left: 'center',
        bottom: visualMapBottom,
        textStyle: { color: isDarkMode ? '#E2E8F0' : '#0F172A', fontFamily: chartFontFamily },
        ...(visualMapColors ? { inRange: { color: visualMapColors } } : {})
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
  };
};
