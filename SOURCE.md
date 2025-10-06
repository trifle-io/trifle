# Source Unification Plan

## Overview
- Goal: make ExploreLive and DashboardLive operate on a polymorphic analytics source (Database or Project) sharing the same behaviours and UI components.
- Driver construction differs by source today; plan introduces a behaviour to encapsulate driver/timeframe logic while keeping LiveViews identical.
- Dashboards currently belong to databases only; we need a polymorphic association so a dashboard can target either source type without duplicating views.

## Guiding Principles
- Maintain a single ExploreLive and DashboardLive implementation.
- Keep LiveViews responsible for state, routing, and permissions; push rendering into reusable components where practical.
- Encapsulate source-specific details (driver, defaults, transponders) behind a unified behaviour to eliminate branching inside LiveViews.

## Milestones (status)
1. **Define Source Behaviour** — ✅ done
   - `Trifle.Stats.Source` wraps shared behaviour with concrete Database and Project implementations.
   - Helper functions expose source references, grouping, and lookups for LiveViews/components.

2. **Refactor Data Fetching** — ✅ done
   - `Trifle.Stats.SeriesFetcher` and `TrifleWeb.ExportController` accept any Source implementation (shims handle legacy database calls).
   - Transponders, config, and granularities now flow through the behaviour.

3. **LiveView Adaptation** — ✅ initial pass complete
   - ExploreLive and DashboardLive resolve sources at mount/param time, propagate them through FilterBar, and persist `source_type`/`source_id` in URLs.
   - FilterBar exposes a grouped “Source” selector instead of a database-only dropdown.
   - Follow-up: finish cleaning database-specific helpers and polish project UX.

4. **Dashboard Polymorphism** — ⬜ not started
   - Next: introduce `source_type`/`source_id` fields, migrate data, and keep compatibility with `database_id` during rollout.

5. **Component Extraction (Optional)** — ⬜ not started

6. **Project Routing Integration** — ⬜ pending

## Recent Progress
- Added `Trifle.Stats.Source.Project` and expanded helper APIs (`list_for_membership/1`, grouping, sorting) so databases and projects appear uniformly.
- Refactored FilterBar to accept polymorphic sources, emit typed selections, and group options by type.
- ExploreLive now manages source-aware state, URL params, and data loading (including fallbacks when no source is available).
- DashboardLive initializes/persists source context, feeds the new selector, and keeps source metadata in URLs.
- SeriesFetcher, ExportController, and related utilities operate solely via the Source abstraction.

## Dependencies & Sequencing Notes
- Complete Milestones 1–3 before migrating dashboard data; LiveViews must already understand generic sources prior to schema changes.
- Milestone 4 requires coordinated migration (Ecto migration + code deploy). Ensure backwards compatibility or feature-flag during rollout.
- Component extraction can happen in parallel but should align with behaviour refactor to avoid thrash.

## Testing & Verification
- Extend existing LiveView tests to run against both database and project sources (shared test helper that instantiates each source).
- Add unit tests for the Source behaviour implementations and SeriesFetcher integration.
- After dashboard migration, create regression tests ensuring dashboards load for both source types and permissions remain intact.

## Open Questions
- Do we need to support dashboards referencing both a database and project simultaneously? (Current plan assumes exactly one source per dashboard.)
- Projects currently surface with no transponders—do we need project-scoped transform semantics?
- Are there project-specific transponder differences that require additional behaviour callbacks?

## Risks & Mitigations
- **Migration risk**: incorrect `source_type/source_id` data could orphan dashboards. Mitigate with data verification scripts pre/post migration.
- **Behaviour drift**: future changes to Database/Project structs must update Source implementations; add documentation and tests to catch omissions.
- **Authorization gaps**: ensure source loader checks membership/token access for both databases and projects before exposing data.

## Status Tracking
- [x] Behaviour defined and implemented for both sources
- [x] SeriesFetcher updated to accept Source
- [x] LiveViews source-aware with no direct database/project branching (first pass)
- [ ] Dashboard schema migrated to polymorphic source
- [ ] UI components extracted (if pursued)
- [ ] Project routes switched to shared LiveViews; legacy view removed

