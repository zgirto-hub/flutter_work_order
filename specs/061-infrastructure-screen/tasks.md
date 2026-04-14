# Tasks: Infrastructure Screen (Unify Systems + Asset Registry)

**Input**: Design documents in `specs/061-infrastructure-screen/`
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/api.md](./contracts/api.md), [quickstart.md](./quickstart.md)
**Implementer**: opencode (autonomous LLM) — **Claude Code will review the implementation afterward via the `superpowers:code-reviewer` workflow**.

**Tests**: Test tasks are **omitted** — the spec did not request TDD. Manual verification per quickstart.md is the acceptance criterion. The reviewer will flag any missing tests that should be added post-implementation.

---

## How to use this file (instructions for opencode)

1. Work through tasks **in order** within each phase. Phases are sequential; within a phase, tasks marked `[P]` may be parallelized (they touch different files).
2. **Check off each task** as you complete it (`- [x]`).
3. **Commit after each phase** (not each task). Use commit message format: `feat(spec-061): <phase summary>`.
4. Paths in task descriptions are **authoritative**. If a task says `backend/routers/systems.py`, edit that exact file.
5. If a contract or data-model detail is ambiguous, **consult the linked design docs** — do not guess.
6. Do **not** introduce patterns, abstractions, or extra features not listed here (constitution principle VII — YAGNI).
7. When done with Phase 6, stop. Claude Code will review before deployment.

---

## Phase 1: Setup

**Purpose**: Create branch-local scaffolding and confirm workspace.

- [x] T001 Verify you are on branch `061-infrastructure-screen` (run `git branch --show-current`); if not, check it out.
- [x] T002 Read every file under `specs/061-infrastructure-screen/` (spec.md, plan.md, research.md, data-model.md, contracts/api.md, quickstart.md) so the design is fully in context before you start.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Schema migration and base model updates. Every user story depends on these.

**⚠️ CRITICAL**: Phase 2 MUST complete before any user story phase begins.

- [x] T003 Create new migration file `supabase/migrations/20260414150000_infrastructure_refactor.sql` implementing every step in [data-model.md § Migration Data Transformations](./data-model.md) and [§ Tables & Columns](./data-model.md):
  - Add `systems.has_contingency` (boolean, not null, default false) — use `ADD COLUMN IF NOT EXISTS`.
  - Add `asset_system_links.site` (text, not null, default 'production', with CHECK constraint `IN ('production','contingency')`) — use `ADD COLUMN IF NOT EXISTS`.
  - Drop old unique indexes `idx_asset_system_links_unique` and `idx_asset_system_links_primary_standby`; create new site-aware versions exactly as specified in data-model.md.
  - Transformation A (INDRA CCTV cameras → assets): insert `assets` rows, create `asset_system_links` to the INDRA CCTV system with role=`client`, site=`production`, then repoint any old Camera-N links to the new camera assets, then delete the Camera-N `systems` rows.
  - Transformation B (International Circuits removal): repoint `asset_system_links` rows to AIDA-NG with site=`production`; on uniqueness conflict demote role to `client`; repoint `system_status_reports.system_id` to AIDA-NG (both open and resolved, preserve all other fields); delete the 6 International Circuit `systems` rows.
  - Transformation C (`has_contingency` backfill): set true for AIDA-NG, CADAS-ATS, CADAS-IMS, IRTOS; leave the others default false.
  - Entire migration MUST be idempotent (re-runnable without error).
  - Wrap the data transformations in a single `DO $$ ... END $$` block or use explicit transaction control so partial state is impossible.
- [x] T004 [P] Update `frontend/lib/models/system.dart`: add `hasContingency` field (bool, default false), update `fromJson`/`toJson` with key `has_contingency`. Preserve existing fields and constructor order.
- [x] T005 [P] Update `frontend/lib/models/asset.dart`: add `site` field to `AssetSystemLink` (String, default `'production'`), update `fromJson`/`toJson` with key `site`. Do not modify `Asset` class.
- [ ] T006 Apply T003 migration to the local/dev Supabase instance (run via Supabase SQL editor or `supabase db push`). Verify with the SQL checks from [quickstart.md § 1](./quickstart.md) (7 systems, 10 camera assets, zero orphan links, correct `has_contingency`).

**Checkpoint**: Schema and base models ready. User story phases can now begin.

---

## Phase 3: User Story 1 — Browse infrastructure from one place (Priority: P1) 🎯 MVP

**Goal**: Admin opens Settings → Infrastructure, sees system cards, taps one to open a detail view grouped by site and role.

**Independent Test**: Navigate Settings → Infrastructure → tap AIDA-NG. Detail page shows Production and Contingency sections with assets grouped under primary/standby/client. Billing System detail shows only Production.

### Backend

- [x] T007 [US1] Add `GET /api/systems/{id}/detail` endpoint in `backend/routers/systems.py` exactly matching the response schema in [contracts/api.md § GET /api/systems/{id}/detail](./contracts/api.md):
  - Query the `systems` row by id; 404 if missing.
  - Query all `asset_system_links` for this system with a join to `assets` to get `name`, `type`, `location`.
  - Group in Python by site then by role; return only the fields listed in the contract (`id`, `name`, `type`, `location` per asset; `link_id` for the link).
  - **Omit the `contingency` key entirely** when `system.has_contingency` is false (do not return an empty object).
  - Admin-only: reuse the same auth pattern as the other endpoints in this router (`_admin_check` via JWT/user_email).

### Frontend models and services

- [x] T008 [P] [US1] Extend `frontend/lib/services/systems_service.dart`: add method `Future<SystemDetail> fetchSystemDetail(String id)` returning a new `SystemDetail` data class. Define `SystemDetail`, `SystemDetailSite`, and `SystemDetailLink` in the same file (or a new file under `frontend/lib/models/` if cleaner — at your discretion, but keep the feature self-contained). The shape must match the contract.
- [x] T009 [P] [US1] Extend `frontend/lib/services/systems_service.dart` with `Future<System> updateSystem(...)` capable of passing `has_contingency` in the PATCH body (if the existing `updateSystem` doesn't already). Keep backward compat for other fields.

### Frontend UI

- [x] T010 [US1] Create `frontend/lib/screens/admin/infrastructure_screen.dart` — the overview screen, replacing `systems_screen.dart`:
  - Reuse the visual style of the existing `systems_screen.dart` (header, filter chips, FAB, card layout, AppColors). Pull the existing widget structure as a starting point to keep visual consistency.
  - Data source: existing `SystemsService.fetchSystems(...)`.
  - Each card shows: name, status badge (Active/Retired), category badge (if any), review left-border (if `needs_review`), asset count, and a site indicator ("Prod + Cont" if `has_contingency` else "Prod only").
  - Asset count is derived from an extra field in the system list payload — **if the existing `GET /api/systems` does not return `asset_count`, fall back to displaying the indicator without the count and leave a TODO comment pointing at a follow-up task.**
  - FAB opens the existing create-system dialog (port it from `systems_screen.dart`).
  - Filter chips: Show Retired, Needs Review (client-side filtering on the loaded list).
  - Tap a card → push `SystemDetailScreen(systemId: ...)`.
- [x] T011 [US1] Create `frontend/lib/screens/admin/system_detail_screen.dart`:
  - On mount, call `SystemsService.fetchSystemDetail(id)`.
  - Header: back button, system name, "{N} assets · Active/Retired" subtitle, overflow menu (⋮).
  - Info bar: Active/Retired chip, category (if any), sort order.
  - **Production section** always shown: green accent; rows grouped as "Primary", "Standby", "Client"; each row shows asset name, type + location subtitle, and a role badge.
  - **Contingency section** shown only if `system.hasContingency == true`: orange accent; same layout.
  - Empty role groups render a subtle "—" placeholder so the section structure is visible.
  - "+ Add" button on each site section is a stub that does nothing in this phase (US2 wires it). Make sure it is visually present.
  - Overflow menu items (non-functional stubs in this phase, wired in US3): Edit System, Toggle Has Contingency, Retire/Activate, View Status Reports. Each must show a `SnackBar("Coming in US3")` on tap to prove the menu is wired.
  - Use `AppColors` and existing shared widgets (EmptyState, etc.) where appropriate.
- [x] T012 [US1] Update `frontend/lib/screens/settings_page.dart`: replace the two separate "Systems" and "Asset Registry" entries with a single **Infrastructure** entry that pushes `InfrastructureScreen`. Remove the old entries entirely. Remove any now-unused imports.

**Checkpoint**: Admin can browse Infrastructure and open detail views. Story 1 is complete.

---

## Phase 4: User Story 2 — Manage assets for a specific system and site (Priority: P1)

**Goal**: From the detail page, admin can add/create assets per site, change role/site of existing links, and unlink.

**Independent Test**: On AIDA-NG detail, tap "+ Add" under Contingency → create new server "test-1" role=primary → appears immediately in Contingency → Primary. Attempting a second primary in the same site returns an inline conflict error. Tap an existing link → change role → UI moves it to the new role group.

### Backend

- [x] T013 [US2] Update `POST /api/asset-registry/assets/{asset_id}/links` in `backend/routers/asset_registry.py` to accept a required `site` field per [contracts/api.md](./contracts/api.md):
  - Validate `site in ('production','contingency')`.
  - Reject with 400 `{"error":"system_has_no_contingency"}` if `site='contingency'` and the target system's `has_contingency` is false.
  - Enforce the three uniqueness rules from spec FR-009 (primary per site, standby per site, one role per (asset, system, site)); on violation return 409 with an error body distinguishing the three cases (`"duplicate_primary"`, `"duplicate_standby"`, `"duplicate_link"`).
  - Persist `site` on the insert.
- [x] T014 [US2] Add `PATCH /api/asset-registry/links/{link_id}` in `backend/routers/asset_registry.py` per contract:
  - Accept optional `role` and/or `site` in body; at least one required.
  - Validate both against their enum and against the target system's `has_contingency` if `site` is changing to `contingency`.
  - Re-check uniqueness after the update; on conflict return 409 `{"error":"duplicate_link","conflict_with_link_id":"..."}` (or the appropriate duplicate_* error for primary/standby).
  - Update `updated_at` on both the link and the system (for cache-busting).

### Frontend services

- [x] T015 [P] [US2] Extend `frontend/lib/services/asset_service.dart`:
  - Add `site` parameter (required) to the existing `addLink` method and pass it in the body.
  - Add `updateLink(String linkId, {String? role, String? site})` calling `PATCH /api/asset-registry/links/{link_id}`.
  - Map backend 400/409 errors to Dart exceptions carrying the `error` code so the UI can match on it for inline messages.

### Frontend UI

- [x] T016 [US2] Create `frontend/lib/screens/admin/widgets/add_asset_to_system_sheet.dart` — a modal bottom sheet invoked from "+ Add":
  - Inputs: site (pre-filled from the calling section, read-only), mode toggle (Pick Existing / Create New), role dropdown.
  - Pick Existing mode: dropdown/search of `AssetService.fetchAssets()` results, excluding assets already linked to this system at this site.
  - Create New mode: inline form with name, type, location (same fields as the old AssetEditScreen form), plus the role dropdown. On save: first POST new asset, then POST link.
  - On 409/400 from the backend, display an inline error matching the error code text.
- [x] T017 [US2] Wire `+ Add` buttons in `system_detail_screen.dart` to open the new sheet with the correct site. On successful add, refresh the detail via `fetchSystemDetail`.
- [x] T018 [US2] In `system_detail_screen.dart`, make each asset row tappable; tapping opens a simple action sheet with three actions:
  - **Change Role** → dropdown of roles, saves via `AssetService.updateLink(linkId, role: newRole)`.
  - **Change Site** (only shown if `has_contingency=true`) → dropdown of sites, saves via `AssetService.updateLink(linkId, site: newSite)`. On 409 show inline error explaining the target already has this link.
  - **Unlink** → confirmation dialog, then `AssetService.deleteLink(linkId)`.
  - After any successful action, refresh detail.

**Checkpoint**: Admin can fully manage assets per system/site/role. Story 2 complete.

---

## Phase 5: User Story 3 — Administer systems themselves (Priority: P2)

**Goal**: Create / edit / retire / reactivate systems and toggle `has_contingency` from inside the new Infrastructure screen.

**Independent Test**: Create a new system from FAB, edit it, toggle contingency on and off (with the move-and-demote flow), retire it, confirm retired filter works.

### Backend

- [x] T019 [US3] Modify `PATCH /api/systems/{id}` in `backend/routers/systems.py`:
  - Accept optional `has_contingency` in body.
  - If `has_contingency` is being set from true → false, reject with 409 `{"error":"contingency_assets_exist","count":N}` where N is the count of existing contingency links. (Do not perform the move; the client must call the new `disable-contingency` endpoint.)
  - Otherwise pass through.
- [x] T020 [US3] Add `POST /api/systems/{id}/disable-contingency` in `backend/routers/systems.py`:
  - Admin-only, in a single transaction:
    1. For each `asset_system_links` row of this system with `site='contingency'`, attempt to set `site='production'` preserving role.
    2. If that insert/update would violate the uniqueness rules from FR-009, demote role to `client` and retry.
    3. Count moved vs demoted.
    4. Update `systems.has_contingency = false`.
  - Return 200 `{"system": {...}, "moved": N, "demoted": M}`.
  - Errors: 403 (admin), 404 (system), 409 if system already has `has_contingency=false`.

### Frontend services

- [x] T021 [P] [US3] Extend `systems_service.dart` with `disableContingency(systemId)` calling the new endpoint and returning `{system, moved, demoted}`.

### Frontend UI

- [x] T022 [US3] Wire the FAB on `infrastructure_screen.dart`: port the "create system" dialog from the old `systems_screen.dart`, add a `has_contingency` toggle to it.
- [x] T023 [US3] Replace the overflow menu stubs in `system_detail_screen.dart` with real actions:
  - **Edit System** — opens a dialog with name, category, sort_order, has_contingency; calls `updateSystem`. For setting `has_contingency` false, see next bullet.
  - **Toggle Has Contingency (off)** when current = true: if the detail response shows any contingency links, open a confirmation dialog reading "Move N contingency assets to production? (M may be demoted to client due to conflicts with existing primary/standby.)" On confirm, call `disableContingency`; after success, show a SnackBar summarizing "Moved X, demoted Y". On cancel, abort.
  - **Toggle Has Contingency (on)** when current = false: a single PATCH with `has_contingency=true`; refresh.
  - **Retire** — calls existing `retireSystem`; preserve the existing unresolved-reports warning behavior.
  - **Activate** — calls existing `activateSystem`.
  - **View Status Reports** — push the existing System Status screen (read-only for now); if that's not straightforward, leave a SnackBar "Use the System Status dashboard" and move on (do not block the phase on this).

**Checkpoint**: All system-level admin actions available from the Infrastructure screen.

---

## Phase 6: Cleanup & Cross-Cutting

**Purpose**: Remove the old screens, remove dead code, update docs.

- [x] T024 Delete `frontend/lib/screens/admin/systems_screen.dart`, `frontend/lib/screens/admin/asset_registry_screen.dart`, and `frontend/lib/screens/admin/asset_edit_screen.dart`. Search the codebase for any remaining imports or route references to these files and remove them (this should mostly be settings_page.dart which you already updated).
- [x] T025 [P] Update `CLAUDE.md` "Active Technologies" and "Recent Changes" sections to mention spec 061. Follow the format used for prior specs (one line summarizing stack changes).
- [ ] T026 Run through every step in [quickstart.md](./quickstart.md) §§ 1-6. Fix any surface bugs you discover (missing error handling, typos, etc.) but do NOT redesign. Commit fixes as a single `fix(spec-061): quickstart pass` commit.
- [x] T027 Final sanity: run `flutter analyze` (frontend) and `python -m py_compile backend/main.py backend/routers/systems.py backend/routers/asset_registry.py` (backend). Resolve any warnings introduced by this feature. Pre-existing warnings in unrelated files are NOT your concern.

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1** (Setup): no dependencies
- **Phase 2** (Foundational): depends on Phase 1; **BLOCKS** Phases 3-6
- **Phase 3** (US1): depends on Phase 2; does NOT depend on US2/US3
- **Phase 4** (US2): depends on Phase 3 (detail screen must exist before wiring + buttons)
- **Phase 5** (US3): depends on Phase 3 (overflow menu exists there); independent of US2 but realistically done after for UX continuity
- **Phase 6** (Cleanup): depends on Phases 3-5 all complete

### Within-phase dependencies

- T003 (migration SQL) must complete and be applied (T006) before T007-T026 will have a working schema to target.
- T004 and T005 are [P] relative to each other (different files).
- In Phase 3: T007 (backend endpoint) must complete before T008 (frontend service consuming it). T010 and T011 can be developed somewhat in parallel but T011 consumes the output of T008.
- In Phase 4: T013/T014 (backend) before T015 (service) before T016-T018 (UI).

### Parallelizable tasks ([P])

- T004, T005 — different model files
- T008, T009 — same file, so **not** [P]; corrected: T008 is [P] with T015 (Phase 4), T021 (Phase 5)
- T025 independent of most tasks in Phase 6

---

## Implementation Strategy

### MVP

Phases 1 → 2 → 3 (User Story 1 only). At this point the admin can already browse the cleaner, site-aware infrastructure view — this is a shippable increment even without US2/US3 wiring.

### Incremental delivery

1. Phase 1-2: foundation ready (schema + models)
2. Phase 3: Story 1 shippable — browse-only MVP
3. Phase 4: Story 2 shippable — full asset management inside the screen
4. Phase 5: Story 3 shippable — full system admin inside the screen
5. Phase 6: cleanup; old screens deleted

Commit after each phase so the reviewer can inspect logical checkpoints.

---

## Review handoff (for Claude Code)

After Phase 6 is complete, you (Claude Code) will be invoked via `superpowers:code-reviewer`. Focus your review on:

1. **Migration correctness and idempotency** — does re-running T003's SQL produce no changes on a migrated DB? Are all three transformations (cameras, circuits, has_contingency) actually complete? Did the uniqueness index changes drop the old indexes before creating new ones?
2. **Contract adherence** — does `GET /systems/{id}/detail` omit `contingency` when `has_contingency=false`? Does `POST /links` reject `site='contingency'` with the exact error code specified?
3. **FR-009 enforcement** — all three uniqueness rules (primary per site, standby per site, one link per (asset, system, site)) must be enforced both in DB (via indexes) and in backend (via pre-insert check with proper 409 error codes).
4. **Spec Q3 / Q4 semantics** — the migration's demote-to-client must preserve links; the `disable-contingency` endpoint must return accurate `moved`/`demoted` counts; no silent data changes elsewhere.
5. **Deletion completeness** — T024 should leave no dead imports, no stale route references, no leftover `asset_edit_screen.dart` import.
6. **Audit log entries** — every system/link mutation should call `log_activity` per constitution VI.
7. **Constitution re-check** — quick pass to confirm no YAGNI violations slipped in.

If any issue is critical, reviewer will open a fix request. If the review passes, Claude Code will create the PR.

---

## Notes

- Tasks deliberately do **not** pre-write tests. If the reviewer's pass reveals that one or more code paths would be dramatically safer with a unit or integration test, the reviewer will add a follow-up task for that specific case. Blanket TDD was not requested for this feature.
- Any ambiguity in a task should be resolved by re-reading the design docs first, and only escalated if the docs conflict.
- Avoid touching files not listed here. If you discover a genuine cross-cutting bug while implementing, leave a TODO with spec-061 reference and flag it in your handoff, do not fix it in this branch.
