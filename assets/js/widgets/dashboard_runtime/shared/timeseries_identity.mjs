// Separate a series' unique identity and tooltip label from its optional legend group.
// ECharts toggles all series with the same name together (e.g. every state of a trace).
export const timeseriesIdentity = (series, index) => ({
  ...(series.id != null ? {id: String(series.id)} : {}),
  name: series.legend_name || series.name || `Series ${index + 1}`
});

export const timeseriesLabels = (series) => new Map(
  series.filter(item => item.id != null && item.name).map(item => [String(item.id), item.name])
);

export const timeseriesTooltipName = (param, labels) =>
  labels.get(String(param.seriesId)) || param.seriesName || '';
