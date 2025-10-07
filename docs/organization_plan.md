# Organization Feature Implementation Plan

## Goals & Scope Alignment
- Introduce a first-class `Organization` (aka `Company`) entity that owns Databases, Dashboards, DashboardGroups, and Transponders so user data is siloed per organization.
- Support both SaaS (multi-organization, user-created) and self-hosted (single-organization, auto-provisioned) deployment modes without touching `Trifle.Admin` yet.
- Provide organization management UI (profile + members + invites) accessible from the existing user dropdown, re-using visual patterns from Transponders tabs.
- Deliver invitation workflows that existing or new users can use to join an organization, with role management (member/admin) controlled by org admins.
- Ensure all read/write paths in the app respect organization boundaries while keeping future data migrations manageable.
- Design schema and APIs with eventual multi-organization-per-user support in mind, even though phase 1 enforces a single active organization per user.

## Phase 1 – Data Modeling & Database Migrations
1. Add new tables:
   - `organizations` with fields for `name`, `slug`, `address_line1`, `address_line2`, `city`, `state`, `postal_code`, `country`, `timezone`, `vat_number`, `registration_number`, `metadata` JSON, plus timestamps.
   - `organization_memberships` (join table) with `organization_id`, `user_id`, `role` enum (`owner`, `admin`, `member`), `invited_by_user_id`, `last_active_at`; enforce unique constraint on `user_id` for now to keep one-organization-per-user semantics while leaving room to relax later.
   - `organization_invitations` storing `organization_id`, `email`, `role`, `token`, `status`, `expires_at` (default `now + 3 days`), `invited_by_user_id`, `accepted_user_id`.
2. Add `organization_id` FK (binary_id) with appropriate indexes to:
   - `databases`, `dashboards`, `dashboard_groups`, `transponders`, and any dependent tables (e.g., project tokens if they are org-scoped).
3. Update existing migrations if needed for defaults (allow null during rollout); since we ignore historical data migration now, set `null: true` with plan to backfill later.
4. Create Ecto schemas for `Organization`, `OrganizationMembership`, `OrganizationInvitation` under `lib/trifle/organizations/` with changesets for CRUD + validation (unique membership, invite token generation, etc.).
5. Wire migration helpers for generating invitation tokens (unique index) and ensuring cascading deletes where appropriate (e.g., deleting org cascades to child entities in future, but default to restrict for safety now).

## Phase 2 – Context & Domain Layer Updates
1. Extend `Trifle.Organizations` context (or split into sub-context if preferred) to expose:
   - CRUD for organizations (create, update profile fields) with role checks.
   - Membership helpers (`list_members/1`, `add_member/3`, `remove_member/2`, `change_role/3`) that assume a single membership per user today but keep API surface adaptable for multi-membership later.
   - Invitation workflows (`create_invitation/4`, `get_invitation_by_token!/1`, `accept_invitation/2`, `cancel_invitation/2`).
   - Query helpers that scope databases/dashboards/groups/transponders by organization.
2. Update existing context functions to require either `organization_id` or authenticated user and enforce membership within queries:
   - Replace global `list_databases/0` etc. with org-scoped variants (`list_databases_for_org/1`, `get_database!/2`). Provide wrappers that take `current_user` to infer active organization.
   - Ensure creation/update functions automatically set `organization_id` (from context or from associated parent).
3. Introduce a notion of “active organization” selection per session (likely stored in session assigns). Provide helper to fetch membership + default organization for current user.
4. Add guard clauses to prevent cross-organization access in `get_*` functions (e.g., `Repo.one!` with both `id` and `organization_id`).

## Phase 3 – Authentication, Membership, and Invite Flow Integration
1. Decide configuration flag for deployment mode (`:trifle, :deployment_mode` with values `:self_hosted | :saas`); expose helper to check mode.
2. On user registration:
   - Self-hosted: ensure default org exists (seed on boot) and automatically create membership with role `owner` for first user, `admin` thereafter.
   - SaaS: allow optional `invite_token` parameter. Without invite, create a new organization named from signup input (wizard) and assign user as `owner`. With invite, attach to invited organization and respect invited role.
3. Add acceptance endpoint/controller for invitation tokens supporting:
   - Existing users (authenticate, then `accept_invitation` -> membership).
   - New users (preserve invite token through registration, automatically link after registration success).
4. When generating invitation emails, include copy that the link expires in 3 days and handle resend by issuing a new token/expiry.
5. Implement ability to switch active organization when user belongs to multiple (dropdown or modal) – leave hooks/placeholders but defer actual multi-membership UI until phase 2.
6. Update session/plug logic (likely in `TrifleApp.UserAuth` and LiveView mount hooks) to load memberships and enforce presence of active organization before loading app routes; keep assumption of single membership while architecting for future multi-org selection.

## Phase 4 – LiveView & UI Additions
1. Add “Organization” entry to the user dropdown (desktop + mobile) pointing to `/organization` LiveView; ensure consistent styling with existing menu.
2. Create `TrifleApp.OrganizationLive` (tabs) mirroring Transponders layout:
   - Tab 1: “Profile” (editable fields for org name, address, VAT/registration identifiers, timezone).
   - Tab 2: “Users” (table of members with role badges, remove action, role toggle).
   - Tab 3: “Invitations” (list pending invites, re-send/cancel, form to invite by email + role, show expiry countdown).
   - Tab 4: “Billing” (placeholder for future subscription management, hidden or disabled in self-hosted mode unless licensed).
   - Use existing design system components for forms, tables, buttons.
3. Ensure LiveView uses `current_user` + `active_org` assigns; redirect if user lacks admin rights for admin-only actions.
4. Add LiveComponents for modal/confirmations if needed (remove member, change role) using existing patterns.
5. Localize flash and validation messages consistent with current copy.

## Phase 5 – Access Control Across Existing Screens
1. Update all LiveViews / controllers that currently call unscoped `Organizations` functions to pass the active organization:
   - Dashboards (`DashboardsLive`, `DashboardLive`, forms, duplication, group tree loading).
   - Databases listing/config (`DatabasesLive`, transponders, explore, etc.).
   - Any API endpoints under `TrifleApi` that expose dashboards/data – ensure they check `organization_id` from auth context.
2. Adjust navigation breadcrumbs/links to include `organization_id` if necessary (or rely on global active org).
3. Add pattern-matching clauses for 404/403 when a resource belongs to different organization.
4. Ensure query preloads respect organization boundaries (e.g., `list_dashboards_for_user_or_visible/2` filters by `organization_id`).

## Phase 6 – Deployment Mode Specific Behavior
1. Implement startup hook (in `application.ex` or a dedicated task) that, when in self-hosted mode, ensures default organization record exists (`ACME, Inc.`) and marks it locked (non-deletable) if needed.
2. In self-hosted mode, hide UI for creating additional organizations and invitations outside the single org context; limit features to editing profile + managing members while leaving the Billing tab present but disabled/with explanatory copy.
3. In SaaS mode, expose organization creation flow (either on signup or via UI for multi-org future) and allow invites.
4. Provide configuration documentation (README or `docs/deployment.md`) describing new env vars (`TRIFLE_DEPLOYMENT_MODE`, default timezone, etc.).

## Phase 7 – Testing & QA
1. Add Ecto schema tests for new models (changesets, role validations, token uniqueness, expiration logic).
2. Write context tests covering membership CRUD, invitation acceptance (existing/new user), and access guard helpers.
3. Add LiveView tests for Organization UI flows (profile update, invite send, role toggle) using existing test helpers.
4. Add tests ensuring invitation creation sets a 3-day expiry and that expired tokens are rejected; verify reminder/resend generates a new expiry.
5. Update existing LiveView/controller tests to include organization fixtures and ensure resource scoping works.
6. Add integration tests for registration with invite vs without, plus self-hosted bootstrap scenario.

## Phase 8 – Follow-up & Tech Debt
- Plan future migration script to backfill `organization_id` for existing data.
- Decide on background job for expired invitation cleanup.
- Revisit `Trifle.Admin` later to surface organization management once admin module is addressed.
- Evaluate whether `Project`/`ProjectToken` should also be org-scoped (likely yes) and schedule as follow-up if out of immediate scope.
- Add audit logging trail for membership changes, invitation acceptance, and role assignments in phase 2.

## Open Questions / Clarifications Needed
- None for now; revisit once billing scope or multi-organization support timelines are clearer.
