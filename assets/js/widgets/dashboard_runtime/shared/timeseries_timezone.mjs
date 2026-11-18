// ECharts' time helpers come from the chart bundle (js/charts.js exposes them as
// TrifleECharts.timeUtil). Importing them here would copy a slice of ECharts into
// app.js, which the split build exists to avoid.
const timeUtil = () => {
  const util = globalThis.TrifleECharts && globalThis.TrifleECharts.timeUtil;
  if (!util) throw new Error('chart bundle is not loaded');
  return util;
};

let cachedAxisFormatter = null;
const defaultAxisFormatter = () => {
  if (!cachedAxisFormatter) cachedAxisFormatter = timeUtil().parseTimeAxisLabelFormatter();
  return cachedAxisFormatter;
};

// ECharts' default tooltip label uses a date for long ranges, seconds normally,
// and milliseconds for subsecond ranges. Keep the precision chosen by its scale.
const tooltipTemplate = (defaultLabel) => {
  const {fullLeveledFormatter} = timeUtil();
  if (/^\d{4}-\d{2}-\d{2}$/.test(defaultLabel)) return fullLeveledFormatter.day;
  if (/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \d{3}$/.test(defaultLabel)) {
    return fullLeveledFormatter.millisecond;
  }
  return fullLeveledFormatter.second;
};

// Only translate the displayed clock: reuse ECharts' formats and tick hierarchy.
// Series timestamps, tick positions and widgets without a timezone stay unchanged.
export const timeseriesTimeFormatters = (timezone) => {
  if (!timezone) return null;
  try {
    const {format, leveledFormat} = timeUtil();
    const axisFormatter = defaultAxisFormatter();
    const clock = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone, calendar: 'gregory', numberingSystem: 'latn',
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23'
    });

    const sourceClock = (value) => {
      const instant = new Date(value);
      const parts = Object.fromEntries(clock.formatToParts(instant).map(({type, value}) => [type, value]));
      const wallClock = new Date(0);
      wallClock.setUTCFullYear(Number(parts.year), Number(parts.month) - 1, Number(parts.day));
      wallClock.setUTCHours(Number(parts.hour), Number(parts.minute), Number(parts.second), instant.getUTCMilliseconds());
      return wallClock.getTime();
    };

    return {
      axis: (value, index, metadata) => leveledFormat(
        {value: sourceClock(value), time: metadata?.time}, index, axisFormatter, undefined, true
      ),
      tooltip: (value, defaultLabel) => format(sourceClock(value), tooltipTemplate(defaultLabel), true)
    };
  } catch (_) {
    return null;
  }
};
