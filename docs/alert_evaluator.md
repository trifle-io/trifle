# Alert Evaluation Pipeline

## Overview
- New module `Trifle.Monitors.AlertEvaluator` standardises how monitor alerts are evaluated against a `Trifle.Stats.Series`.
- Supported strategies: `:threshold`, `:range`, `:hampel`, `:cusum`. Each returns a `%AlertEvaluator.Result{}` with trigger metadata, highlight segments, and summary copy.
- Threshold/Range strings use math italic 𝑥 with inequalities (`𝑥 ≥ τ`, `α ≤ 𝑥 ≤ β`) so charts and exports read like formulas; Hampel/CUSUM metadata applies the same styling to 𝑤/𝑘/𝑚/μ/𝐻.
- `AlertEvaluator.overlay/1` converts a result into a JSON-friendly payload consumed by the dashboard grid to render mark lines/areas/points in ECharts.

## Missing Buckets
- `AlertSeries.resolved_final_targets/2` preserves timestamped missing buckets, including entirely missing paths and formula outputs. Charts retain gaps, while each alert decides whether those gaps count as zero.
- Evaluation excludes the final, unfinished bucket by default, then applies `treat_nil_as_zero` to the remaining buckets. A timeline of `[150, 50, nil, nil]` therefore evaluates `[150, 50, 0]` when zero-fill is enabled.
- A lone unfinished bucket returns `{:error, :no_data}`. Callers can explicitly include the final bucket with `exclude_recent: false`.

## Monitor LiveView Integration
- `TrifleApp.MonitorLive` builds per-alert timeseries widgets via `MonitorLayout.alert_widgets/1`, enriches widget datasets through `MonitorLayout.inject_alert_overlay/3`, and formats display names with `MonitorLayout.alert_label/1` while keeping evaluation summaries in `@alert_evaluations`.
- New assign `:alert_evaluations` maps alert ids to their latest evaluation, allowing UI badges/summary copy.
- Front-end (`assets/js/app.js`) reads the overlay payload to draw threshold lines, range bands, breach areas, and Hampel/CUSUM markers.

## Follow-up / QA Notes
- Background jobs and monitor overlays share `AlertSeries.resolved_final_targets/2` and `AlertEvaluator.evaluate_points/4` so the visual and persisted state stay in sync.
- Existing visual tests rely on mocked data; consider adding LiveView assertions around `@alert_evaluations` once we expand monitor feature tests.
- When new strategies are added, extend `AlertEvaluator` plus front-end overlay handling and add regression tests in `alert_evaluator_test.exs`.
