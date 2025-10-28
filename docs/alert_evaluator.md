# Alert Evaluation Pipeline

## Overview
- New module `Trifle.Monitors.AlertEvaluator` standardises how monitor alerts are evaluated against a `Trifle.Stats.Series`.
- Supported strategies: `:threshold`, `:range`, `:hampel`, `:cusum`. Each returns a `%AlertEvaluator.Result{}` with trigger metadata, highlight segments, and summary copy.
- `AlertEvaluator.overlay/1` converts a result into a JSON-friendly payload consumed by the dashboard grid to render mark lines/areas/points in ECharts.

## Monitor LiveView Integration
- `TrifleApp.MonitorLive` builds per-alert timeseries widgets via `alert_widget_dom_id/2` and enriches widget datasets with overlay details + evaluation summaries.
- New assign `:alert_evaluations` maps alert ids to their latest evaluation, allowing UI badges/summary copy.
- Front-end (`assets/js/app.js`) reads the overlay payload to draw threshold lines, range bands, breach areas, and Hampel/CUSUM markers.

## Follow-up / QA Notes
- Ensure background jobs that will run evaluations reuse `AlertEvaluator.evaluate/4` so the visual + persisted state stay in sync.
- Existing visual tests rely on mocked data; consider adding LiveView assertions around `@alert_evaluations` once we expand monitor feature tests.
- When new strategies are added, extend `AlertEvaluator` plus front-end overlay handling and add regression tests in `alert_evaluator_test.exs`.
