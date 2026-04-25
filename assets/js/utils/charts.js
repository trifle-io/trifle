export const ECHARTS_RENDERER = 'svg';
export const ECHARTS_DEVICE_PIXEL_RATIO = Math.max(1, window.devicePixelRatio || 1);
export const withChartOpts = (opts = {}) => Object.assign({ renderer: ECHARTS_RENDERER, devicePixelRatio: ECHARTS_DEVICE_PIXEL_RATIO }, opts);
export const chartFontFamily =
  'Inter var, Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';

export const extractTimestamp = (point) => {
  if (Array.isArray(point) && point.length) return Number(point[0]);
  if (point && typeof point === 'object') {
    if (Array.isArray(point.value) && point.value.length) return Number(point.value[0]);
    if (Array.isArray(point.coord) && point.coord.length) return Number(point.coord[0]);
  }
  return null;
};

export const detectOngoingSegment = (seriesList) => {
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
