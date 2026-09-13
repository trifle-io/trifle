# Timeseries axes (internal rendering contract)

The shared compact and expanded timeseries renderers support an optional right-hand value axis and mixed chart types. This is a **rendered chart data** contract, not a new dashboard form or dashboard API configuration option. Widgets built through the existing form continue to emit every series with `y_axis: "primary"`.

```json
{
  "chart_type": "bar",
  "stacked": true,
  "y_label": "Events",
  "secondary_y_label": "Avg. duration (ms)",
  "series": [
    {"name": "Success", "data": [[1789380000000, 12]]},
    {
      "id": "average-duration",
      "name": "Average duration",
      "chart_type": "line",
      "y_axis": "secondary",
      "stacked": false,
      "unit": "ms",
      "data": [[1789380000000, 125.5]]
    }
  ]
}
```

- An omitted or unknown `y_axis` selects the primary axis. A secondary axis is created only when a series opts in with `"secondary"`.
- `chart_type` can override the widget's default for one series (`line`, `area`, `bar`, `dots`). Secondary series do not inherit primary stacking. Explicitly stacked secondary series use a separate stack.
- Primary normalization, alert thresholds and bounds do not affect the secondary scale. The secondary axis does not draw another set of horizontal grid lines.
- `unit` appears in tooltips and expanded numeric summaries. `null` represents an unavailable sample, not zero; line gaps are not joined. A lone duration sample remains visible as a small point.
- Optional `average_samples: [{name: "legend group", data: [[timestamp, sum, count]]}]` on a uniquely identified line lets both renderers recompute a weighted average when legend groups are hidden. Its expanded Mean is weighted across all selected samples, not averaged across buckets; Sum is omitted because summing averages is misleading.

This uses ECharts' [multiple-axis and per-series axis routing](https://echarts.apache.org/handbook/en/concepts/axis/).

## Trace activity metrics

Internal tracing now records `duration.count`, `duration.sum`, `duration.square`, and equivalent samples under `duration.states.<state>`. Values are milliseconds. The existing numeric `states.<state>` event counters are unchanged.

Timing is measured using the tracer lifecycle callbacks and the initial monotonic `bumped_at` timestamp, preserved in the tracer process until wrapup. This measures elapsed trace lifecycle time (including callback/persistence overhead), not Oban's native-unit execution measurement. It requires no extra trace-index or attachment reads and no plugin update.

The activity view combines duration sums/counts across the selected path and descendants exactly once, and uses state-specific duration samples when a state is selected. Missing samples are excluded from the denominator. Old buckets, or in-flight traces without a start callback, keep their event counts but do not receive invented duration values. No data is backfilled.

Restart the app after deploying the callback change so the Oban integration receives the new lifecycle configuration. New samples then appear as jobs complete.
