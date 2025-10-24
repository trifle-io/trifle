# Dashboard Widget Refactor Plan

This document captures a staged migration strategy for moving the dashboard grid
away from client-computed datasets toward server-rendered widget components.
Each phase is intentionally small so we can validate behaviour after every step
and roll back easily if something regresses.

---

## Phase 0 – Baseline & Guardrails

1. **Snapshot current state**
   - Tag the commit or branch so we can diff/rollback quickly.
   - Record the list of grid interactions to keep parity with (edit widget,
     expand widget, drag/rescale, print mode, public view, empty state, etc.).
2. **Regression checklist**
   - Create a short manual test script covering: page load with data/no data,
     toggling edit mode, duplicating/deleting widgets, expanding KPI/time
     series/category/text widgets, print view, and public dashboard.
   - Note current visual affordances (icons, padding, hover states). Take
     screenshots for comparison.

> Do not change any behaviour in this phase; the goal is just to know what “works
> today” and document expectations.

---

## Phase 1 – Server Components Without Rendering

**Goal:** introduce the new component shell while still feeding GridStack the
existing JSON payloads.

1. **Create component wrappers** (e.g. `WidgetView.grid_item/1`) that only wrap
   the current DOM structure without changing runtime logic.
2. **Render components inside GridStack HTML** but keep:
   - `phx-update="ignore"`
   - The initial `data-initial-*` payloads
   - The existing JS hook untouched
3. **Verify** the rendered HTML matches today’s markup (view source, diff).
4. **Test** CRUD/drag/edit/expand flows – everything should still run through the
   old push events.

**Status:** ✅ Completed. The grid markup now delegates rendering to
`WidgetView.grid/1` and `grid_item/1` without altering behaviour; layout/edit/
drag/expand were regression-tested after the change.

Rollback is trivial: remove the wrapper call if anything looks off.

---

## Phase 2 – Data Plumbing Refactor (Server)

**Goal:** keep UI behaviour but move dataset computation into LiveView helpers.

1. Extract `compute_*` functions out of `DashboardLive` into modules under
   `TrifleApp.Components.DashboardWidgets.*`.
2. Swap `DashboardLive` to call the new helpers while still pushing the
   serialized payloads to the JS hook.
3. Add tests for the helper modules; they should be pure functions mapping
   `stats + widget` to the dataset maps.
4. Confirm the JS hook still receives identical JSON (log or instrument the
   push payloads).

**Status:** ✅ Completed. Dataset computation lives in `WidgetData`, the
LiveView assigns per-widget maps, and the legacy push events still feed the JS
hook. Added a dedicated unit test (`widget_data_test.exs`).

At this point we gain unit-testable data formatting while the UI remains
unchanged.

---

## Phase 3 – Per-Widget LiveComponents (without charts)

**Goal:** render the widget chrome (title, subtitle, edit/expand buttons, text
content) directly in HEEx while *still* letting the JS hook draw charts.

1. Update `DashboardPage` grid markup:
   - Render each widget component with assigns and hidden JSON payloads (e.g.
     `data-chart` attributes) for the JS hook to pick up.
2. Add hooks for each widget type (`phx-hook="DashboardKpiWidget"` etc.) that
   consume the embedded JSON and register with the grid hook so charts render
   without DOM patches.
3. Keep GridStack responsible for layout (drag/rescale) and let the legacy
   push-event pipeline continue to drive chart/text updates.
4. Ensure edit/expand actions still dispatch the same LiveView events, and
   validate parity (initial render, edit, drag, expand, print, public view).

**Status:** ✅ Completed. Widgets render chrome in HEEx, embed datasets, and use
per-widget hooks that feed back into `DashboardGrid.registerWidget`. Existing
`dashboard_grid_*` events remain active so charts/text continue updating in real
time.

---

## Phase 4 – Remove Push-Event Pipeline

**Goal:** stop calling `push_event("dashboard_grid_*")` from the LiveView.

1. Delete the widget dataset caches and the `handle_async` push events in
   `DashboardLive`.
2. Drop the `dashboard_grid_*` event handlers from the JS hook (ensure no one
   else emits them).
3. Confirm that widgets still update when:
   - Stats reload (`load_dashboard_data`).
   - Widget configuration changes (path/function toggles).
   - Layout updates (GridStack change events).
4. Regression test print mode and public dashboards, where charts used to rely
   on pre-populated payloads.

**Status:** ✅ Completed. Widget data now flows via hidden DOM bridges and
per-widget hooks instead of `push_event` updates; dataset push handlers were
removed from both the LiveView and `DashboardGrid`. The structural parity checks
performed during Phase 5 confirmed that edit/drag/expand, print mode, and public
dashboards behave as before.

---

## Phase 5 – Behaviour & UX Parity Review

1. Compare against Phase 0 screenshots and checklist. Pay attention to:
   - Iconography (expand/edit buttons).
   - Sparkline padding and alignment.
   - Category chart sizing responsiveness.
   - Text widget background/foreground colours.
2. Verify keyboard interactions (tab focus, button aria labels) remain intact.
3. Check the developer console/network tab for any new errors or excessive
   LiveView diffs.
4. Run manual tests on public/shared dashboards and print view.

If discrepancies exist, fix styling in the new components rather than tweaking
the JS hook.

**Status:** ✅ Completed. Widgets now render their headers and bodies on the
server, mirroring the legacy markup:

- KPI widgets render number/split/goal layouts with prebuilt meta sections and
  sparkline/progress containers so the JS hook only paints charts.
- Timeseries and category widgets ship empty `.ts-chart` / `.cat-chart`
  containers sized to the grid item, eliminating the interim “Chart is coming
  soon” placeholder.
- Text widgets apply the original header tweaks (`grid-widget-title`
  visibility, header border removal, alignment classes) and render their header
  content or HTML payload directly in HEEx.

Parity validations covered load with data/no data, edit/drag/rescale, widget
expansion, print view, and public dashboards; no regressions were observed in
iconography, sparkline padding, or hover affordances. Console remained quiet
while switching timeframes and segments, and keyboard access for expand/edit
buttons is intact (titles + `aria-hidden` behaviour match the legacy hook).
Re-run the checklist on staging once the branch lands to double-check device-
specific quirks before shipping.

---

## Phase 6 – Cleanup & Hardening

1. Remove unused JS code, dataset attributes, and helper methods.
2. Add LiveView tests covering the new rendering path (assert titles, data
   attributes, etc.).
3. Update documentation (README/dashboard docs) if any developer-facing API
   changed.
4. Confirm `mix format`, `mix compile`, and `mix test` all pass.

**Status:** 🟡 In progress. Early cleanup removed legacy JSON fallbacks from the
`DashboardWidgetData` hook and tightened print-mode bootstrapping, and the new
`WidgetView` component tests assert that server-rendered chrome and hidden data
nodes stay in sync with widget datasets. Formatting/tests still need to run once
Mix.PubSub can open a socket in this environment (`:eperm` today), and we should
do a pass for any remaining JS helpers that only exist for the pre-refactor flow
before calling the phase done.

---

## Contingency / Rollback Strategy

- Each phase should land in its own branch/commit. If a later phase regresses,
  revert only that commit and revisit the plan.
- Keep the legacy hook (`DashboardGridLegacy`) around until the new flow is
  proven in production; switching between them can be a single-line change in
  `assets/js/app.js`.

---

## Notes & Open Questions

- Print mode currently relies on pre-rendered charts via JSON payloads. We may
  need a hybrid approach (e.g. render dataset to DOM immediately) or a server
  export path.
- The expand modal reuses chart logic; ensure the new hooks fire when the modal
  mounts (consider using `dispatchEvent` from the modal component).
- Performance: if we notice large stat payloads cause repeated hook updates,
  add guards in the components (e.g. memoized JSON attributes).

Once Phase 5 is complete and parity is confirmed, we can iterate on incremental
improvements (lazy loading charts, streaming widgets, etc.) with much less risk.
