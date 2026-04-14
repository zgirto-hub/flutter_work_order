# Phase 0 Research — Infrastructure Screen

All Technical Context items are resolved from existing project conventions. The `/speckit.clarify` session (see spec.md § Clarifications, Session 2026-04-14) resolved the five open design questions. This document records the remaining architectural decisions that shape Phase 1 artifacts.

---

## Decision 1 — Schema changes live in a single migration

**Decision**: Add `systems.has_contingency` (boolean, default false) and `asset_system_links.site` (text, CHECK IN ('production','contingency'), default 'production') in a single timestamped migration file, plus all data transformations (camera conversion, International Circuits removal, status report repointing, `has_contingency` backfill).

**Rationale**: Spec FR-013 through FR-017 mandate a one-time, idempotent migration. A single file mirrors how spec 056 (the systems table itself) was introduced. Splitting into multiple files would create partial-application states that are hard to reason about in Supabase's sequential migration model.

**Alternatives considered**:
- **Separate schema and data migrations** — rejected: adds risk of one running without the other; harder to test idempotence.
- **Application-level backfill on first launch** — rejected: constitution principle II ("Explicit Over Automatic") forbids hidden data changes at runtime; migrations are the explicit tool.

---

## Decision 2 — New endpoint `GET /api/systems/{id}/detail` does the grouping server-side

**Decision**: Introduce a single new endpoint that returns the system plus its asset links already grouped by site and role. Modify existing link endpoints to accept/return `site`. Do not add other new endpoints.

**Rationale**: The detail page needs a structured payload; building it client-side would require issuing two round-trips (system CRUD + asset links query with joins). Server-side grouping avoids N+1 patterns and keeps the client simple. Reusing existing CRUD for creation/edit/retirement keeps surface area small (constitution principle VII, YAGNI).

**Alternatives considered**:
- **Embed grouping in `GET /api/systems`** — rejected: every list view would pay the cost of the grouping query; detail view only needs it per-system.
- **Client-side join after two fetches** — rejected: more round-trips and more code paths to get consistent.

---

## Decision 3 — Conflict-demotion is migration-only; runtime uses strict validation

**Decision**: The migration's "demote to client" behavior (spec clarification Q3) applies **only** during the one-time data transform. Runtime link creation and updates strictly enforce FR-009 uniqueness via HTTP 409, surfaced in the UI as inline errors.

**Rationale**: Silent demotion at runtime would violate principle II ("Explicit Over Automatic"). The migration is a special case: it's fixing historical data where the user's intent cannot be confirmed, so preserving the link's *existence* at the cost of a weaker role is the least-bad outcome. At runtime, the admin is present and must make the choice explicitly.

**Alternatives considered**:
- **Always-demote policy** — rejected: silent data transformation violates principle II.
- **Always-fail policy** — rejected: would break the idempotent-migration requirement (FR-017) on partially-broken historical data.

---

## Decision 4 — Overview filters stay client-side

**Decision**: "Show Retired", "Needs Review", and category filtering are computed on the full system list loaded once. Only the refresh action re-fetches from the backend.

**Rationale**: Principle V ("Client-Side Computation Where Possible") and the small expected dataset (~7 systems post-migration, capped well under 100 even long-term). Zero latency on filter toggles is a real UX win over per-filter server calls.

**Alternatives considered**:
- **Server-side filtering via query params** — rejected: current endpoint already accepts `active_only` and `needs_review`; we preserve those for compatibility but the Flutter list re-filters locally for instant toggles.

---

## Decision 5 — Delete old screens rather than deprecate

**Decision**: Physically remove `systems_screen.dart`, `asset_registry_screen.dart`, and `asset_edit_screen.dart` and their Settings entries in the same change set as the new screens land.

**Rationale**: FR-019 explicitly requires removal. Per project memory feedback ("Avoid backwards-compatibility hacks"), we don't leave dead UI behind with redirects or feature flags. A single clean cutover is simpler to review and reason about.

**Alternatives considered**:
- **Keep old screens with deprecation banner** — rejected: adds two stale code paths; constitution principle VII (simplicity) and user feedback preference.
- **Feature-flag gated switch** — rejected: single-tenant app, no need for gradual rollout.

---

## Decision 6 — Performance targets anchor the "no regression" goal

**Decision**: Overview page (7 cards + badges + counts) must render in <500ms after auth; detail page must load and group in <300ms with ≤50 links. These are planning-phase targets, not spec requirements.

**Rationale**: The spec's Success Criterion SC-002 ("find primary server in under 15s") implies the UI must be responsive. We set internal targets consistent with the rest of the app's admin screens.

**Alternatives considered**: No hard SLAs — rejected because without targets we can't catch regression in testing.

---

## Open Questions

None. All spec-level clarifications are resolved and logged in [spec.md § Clarifications](./spec.md).
