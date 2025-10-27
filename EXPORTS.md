# Export System Refactor

This document tracks the ongoing cleanup of Trifle's export functionality and
describes the target architecture for both data and visual exports.

## Goals
- Separate data exports (CSV/JSON) from visual exports (PNG/PDF).
- Standardise exports across dashboards, Explore, monitors, alerts, and widgets.
- Avoid reusing public-dashboard routes for internal exports while keeping public
  sharing intact.
- Centralise logic so LiveViews, controllers, and background jobs rely on the
  same APIs.

## Scope Overview

### Data Exports (CSV / JSON)
- **Input**: `Trifle.Stats.Source`, key (or nil), timeframe/granularity, segment
  filters, additional metadata.
- **Output**: structured series data plus helpers to encode CSV/JSON.
- **Consumers**: dashboard export controller, Explore LiveView, monitors/alerts,
  future scheduled export jobs.
- **Implementation sketch**:
  - `Trifle.Exports.Series` (name TBD) that wraps `SeriesFetcher` usage and
    provides `series_for_export/1`, `to_csv/1`, `to_json/1`.
  - Normalises URL params (timeframe/granularity/segments) in a single place,
    likely by reusing `TimeframeParsing`.
  - LiveViews push downloads using this module rather than re-encoding data.
  - Controllers become thin wrappers around the shared service.

### Visual Exports (PNG / PDF)
- **Input**: layout definition describing widgets/grid arrangement, theme, and
  rendering options (viewport, padding, etc).
- **Output**: rendered binary (PNG/PDF) produced by headless Chrome.
- **Consumers**: dashboards, monitors with linked dashboards, alert grid stacks,
  single widget exports, CLI mix task.
- **Implementation sketch**:
  - Define `%ExportLayout{}` struct representing a GridStack + widgets tree.
  - Provide adapters that convert dashboard/monitor/alert/widget configs into
    this struct.
  - Introduce a dedicated renderer route (e.g. `ExportLayoutLive`) that renders
    only the grid/widget section without headers, filter bars, or other page
    chrome.
  - Authenticate renderer access using signed, short-lived tokens
    (`Phoenix.Token`) issued specifically for export jobs.
  - Update `ChromeExporter` to accept layout definitions, hydrate them through
    the renderer endpoint, and keep existing CDP helpers (no removal until the
    new pipeline is proven).

## Work Plan & Checklist

- [x] Stand up data-export service module wrapping `SeriesFetcher`.
- [x] Migrate dashboard CSV/JSON controller actions to the new service.
- [x] Update DashboardLive and ExploreLive to call the shared data exporter and
      remove duplicate CSV/JSON shaping.
- [x] Define layout struct(s) and adapters for monitors, alerts, and
      single widgets. *(Dashboard + monitor builders live; alert widgets now adapt target configs into GridStack items.)*
- [x] Build minimal renderer (LiveView or controller + HEEx) that prints only
      the GridStack surface.
- [x] Create signed-token authentication for layout rendering; do not touch the
      existing public dashboard token logic.
- [x] Refactor `ChromeExporter`/`ChromeCDP` to consume layout exports while
      retaining CDP fallbacks during rollout. *(Dashboards use layout-first with legacy fallback; monitors use layout exports.)*
- [ ] Replace dashboard PDF/PNG endpoints and the mix task to use the new
      layout-based pipeline.
- [ ] Wire monitors/alerts/widget exports into the shared visual exporter. *(Monitors and widget flows now use the shared layout pipeline; alert-specific widget export still pending.)*
- [ ] Run `mix compile` after meaningful changes to ensure the app still builds. *(Blocked in sandbox by Mix.PubSub TCP `:eperm`; run locally.)*

## Notes & Constraints
- Keep the existing dashboard public-token functionality for public sharing.
  The new exporter should obtain access via dedicated signed tokens instead.
- Do not delete or substantially change `ChromeCDP` helpers until the new
  renderer is validated and regression-tested.
- Ensure both data and visual exporters remain accessible to background jobs
  (e.g. monitors sending scheduled reports).
- Mix tasks and LiveView download hooks should transition smoothly; preserve the
  existing UX (download iframe, loading states, cookie token) wherever possible.

## Progress Log

- 2025-10-27: Established refactor goals and task list; implemented shared
  series export helpers and migrated dashboard/explore CSV+JSON flows.
- 2025-10-27: Added export layout struct/storage, dashboard layout builder,
  layout LiveView route (no app layout), and wired Chrome exporter to the new
  pipeline with legacy fallback.
- 2025-10-27: Implemented monitor layout builder, monitor PNG/PDF endpoints and UI,
  plus Chrome exporter helpers for direct layout exports.
- 2025-10-27: Added dashboard widget layout exports, widget PNG/PDF routes, and
  in-app controls for per-widget downloads.
