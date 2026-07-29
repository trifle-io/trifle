export const escapeTimeseriesTooltipHtml = (value) =>
  String(value == null ? '' : value).replace(/[&<>"']/g, (s) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#039;'
  }[s]));

export const renderTimeseriesTooltipLines = (lines) => `<div>${lines.join('<br/>')}</div>`;
export const TIMESERIES_TOOLTIP_Z_INDEX = 10000;
export const ANNOTATION_POPOVER_Z_INDEX = 12050;
export const TIMESERIES_TOOLTIP_RESPONSIVE_CSS =
  'max-width:min(30rem, calc(100vw - 2rem));white-space:normal;overflow-wrap:anywhere;word-break:break-word;';

export const annotationGroupsForItem = (context, item) => {
  if (!item || item.annotations_enabled === false || item.annotations_enabled === 'false') return [];
  if (context && context._annotationsVisible === false) return [];
  const payload = context && context._annotationPayload;
  return payload && Array.isArray(payload.groups) ? payload.groups : [];
};

export const timestampMs = (value) => {
  if (Number.isFinite(value)) return Number(value);
  if (typeof value === 'string') {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  if (Array.isArray(value)) return timestampMs(value[0]);
  if (value && Array.isArray(value.value)) return timestampMs(value.value[0]);
  return null;
};

export const annotationGroupForAxisValue = (groups, value) => {
  const ts = timestampMs(value);
  if (!Number.isFinite(ts)) return null;
  return groups.find((group) => Math.abs(Number(group.at_ts) - ts) < 1) || null;
};

export const renderAnnotationTooltipSection = (group, isDarkMode = false) => {
  if (!group || !Array.isArray(group.annotations) || group.annotations.length === 0) return '';
  const titleColor = isDarkMode ? '#f8fafc' : '#0f172a';
  const bodyColor = isDarkMode ? '#cbd5e1' : '#334155';
  const borderColor = isDarkMode ? 'rgba(148,163,184,0.25)' : 'rgba(100,116,139,0.25)';
  const rows = group.annotations.slice(0, 10).map((annotation) => {
    const text = escapeTimeseriesTooltipHtml(annotation.snippet || annotation.body || '');
    return `<div style="margin-top:2px;color:${bodyColor};">${text}</div>`;
  });
  const remaining = group.annotations.length - rows.length;
  const more = remaining > 0
    ? `<div style="margin-top:2px;color:#64748b;">${remaining} more</div>`
    : '';
  return [
    `<div style="margin-top:8px;padding-top:6px;border-top:1px solid ${borderColor};">`,
    `<div style="font-weight:600;color:${titleColor};">Annotations</div>`,
    rows.join(''),
    more,
    '</div>'
  ].join('');
};

export const buildAnnotationMarkLineSeries = (groups) => ({
  name: 'Annotations',
  type: 'line',
  data: [],
  showSymbol: false,
  animation: false,
  silent: false,
  tooltip: { show: false },
  markLine: {
    symbol: 'none',
    silent: false,
    animation: false,
    label: { show: false },
    emphasis: {
      lineStyle: { width: 2 }
    },
    data: groups.map((group) => ({
      name: group.count === 1 ? '1 annotation' : `${group.count || 0} annotations`,
      xAxis: group.at_iso,
      annotation: true,
      annotationGroupId: group.id,
      lineStyle: {
        color: '#3b82f6',
        width: 1,
        type: 'solid',
        opacity: 0.9
      },
      emphasis: {
        lineStyle: {
          color: '#1d4ed8',
          width: 2
        }
      }
    }))
  },
  z: 40
});

export const resolveHoveredTimeseriesParam = (chart, params) => {
  if (!chart || !Array.isArray(params) || params.length <= 1) return null;

  const pointer = chart.__tsPointerPosition;
  if (!pointer || !Number.isFinite(pointer.y)) return null;

  let bestParam = null;
  let bestDiff = Infinity;

  params.forEach((param) => {
    const point =
      Array.isArray(param?.value) ? param.value :
      (param?.data && Array.isArray(param.data) ? param.data : null);

    if (!Array.isArray(point) || point.length < 2) return;

    const x = point[0];
    const y = Number(point[1]);
    if (!Number.isFinite(y)) return;

    try {
      const pixel = chart.convertToPixel({ xAxisIndex: 0, yAxisIndex: 0 }, [x, y]);
      if (!Array.isArray(pixel) || pixel.length < 2 || !Number.isFinite(pixel[1])) return;

      const diff = Math.abs(pixel[1] - pointer.y);
      if (diff < bestDiff) {
        bestDiff = diff;
        bestParam = param;
      }
    } catch (_) {}
  });

  return bestParam;
};
