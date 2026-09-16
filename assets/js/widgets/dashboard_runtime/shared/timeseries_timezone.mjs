import {format, fullLeveledFormatter, leveledFormat, parseTimeAxisLabelFormatter} from 'echarts/lib/util/time.js';

const defaultAxisFormatter = parseTimeAxisLabelFormatter();

// ECharts' default tooltip label uses a date for long ranges, seconds normally,
// and milliseconds for subsecond ranges. Keep the precision chosen by its scale.
const tooltipTemplate = (defaultLabel) => {
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
        {value: sourceClock(value), time: metadata?.time}, index, defaultAxisFormatter, undefined, true
      ),
      tooltip: (value, defaultLabel) => format(sourceClock(value), tooltipTemplate(defaultLabel), true)
    };
  } catch (_) {
    return null;
  }
};
