# Source Unification Plan

## Overview
- Goal: make ExploreLive and DashboardLive operate on a polymorphic analytics source (Database or Project) sharing the same behaviours and UI components.
- Driver construction differs by source today; plan introduces a behaviour to encapsulate driver/timeframe logic while keeping LiveViews identical.
- Dashboards currently belong to databases only; we need a polymorphic association so a dashboard can target either source type without duplicating views.

## Guiding Principles
- Maintain a single ExploreLive and DashboardLive implementation.
- Keep LiveViews responsible for state, routing, and permissions; push rendering into reusable components where practical.
- Encapsulate source-specific details (driver, defaults, transponders) behind a unified behaviour to eliminate branching inside LiveViews.

## Milestones
1. **Define Source Behaviour**
   - Create `Trifle.Stats.Source` behaviour describing capabilities required by Explore/Dashboard.
   - Implement modules for `Database` and `Project` sources that satisfy the behaviour.
   - Provide helper(s) to load a concrete source by `{type, id}` with authorization.

2. **Refactor Data Fetching**
   - Update `Trifle.Stats.SeriesFetcher` and related helpers to accept any `Source` implementation instead of raw database structs.
   - Ensure transponder lookups and granularities flow through the behaviour to stay consistent for both source types.

3. **LiveView Adaptation**
   - Refactor ExploreLive/DashboardLive to resolve a `Source` at mount/param handling time.
   - Replace direct database/project field access with behaviour calls (`stats_config`, `default_timeframe`, etc.).
   - Keep FilterBar and existing components; ensure database/project switching uses the generic source loader.

4. **Dashboard Polymorphism**
   - Migrate dashboards to store `source_type` + `source_id` instead of `database_id`.
   - Backfill existing rows with `source_type = "database"` and update changesets/contexts to enforce one of the allowed types.
   - Adjust Organizations context APIs to return the resolved source alongside dashboard records.

5. **Component Extraction (Optional but Recommended)**
   - Extract presentation-heavy markup from LiveViews into `TrifleApp.Components.Explore` and `TrifleApp.Components.Dashboard` to reduce duplication and simplify future maintenance.
   - Ensure components remain UI-only; LiveViews continue to own events and asynchronous tasks.

6. **Project Routing Integration**
   - Introduce project-based routes that reuse the existing LiveViews by passing a project source identifier.
   - Remove legacy `ProjectLive` explore view once parity is confirmed.

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
- How should we expose source selection in the UI (single dropdown with type grouping vs separate navigation)?
- Are there project-specific transponder differences that require additional behaviour callbacks?

## Risks & Mitigations
- **Migration risk**: incorrect `source_type/source_id` data could orphan dashboards. Mitigate with data verification scripts pre/post migration.
- **Behaviour drift**: future changes to Database/Project structs must update Source implementations; add documentation and tests to catch omissions.
- **Authorization gaps**: ensure source loader checks membership/token access for both databases and projects before exposing data.

## Status Tracking
- [ ] Behaviour defined and implemented for both sources
- [ ] SeriesFetcher updated to accept Source
- [ ] LiveViews source-aware with no direct database/project branching
- [ ] Dashboard schema migrated to polymorphic source
- [ ] UI components extracted (if pursued)
- [ ] Project routes switched to shared LiveViews; legacy view removed

