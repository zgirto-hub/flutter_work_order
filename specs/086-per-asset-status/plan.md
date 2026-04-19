# Implementation Plan: Per-Asset System Status Reporting

**Branch**: `086-per-asset-status` | **Date**: 2026-04-18 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/086-per-asset-status/spec.md`

## Summary

Extend the existing System Status feature (24 canonical systems from spec 056) to support per-asset issue reporting in addition to the existing system-level flow. Both levels coexist — one unresolved issue per `(system, asset, date)` triple, where `asset = NULL` represents a system-level issue. Users continue to interact with the Status screen; a new drill-in bottom sheet replaces the direct "tap a card → report issue" path, lists each system's linked assets (from `asset_system_links`), and lets users report/resolve at either level. System cards gain an amber "⚠ N" badge when assets have open issues. Uptime Report gains optional per-asset breakdown inside `ExpansionTile`s with deterministic integer-based severity thresholds.

**Technical approach**: single-column migration adding nullable `asset_id` FK to `system_status_reports`; one new `GET /system-status/systems/{id}/assets` endpoint; additive fields on the existing today/history/report endpoints; reuse of the existing report/resolve/edit/delete bottom sheets parametrized with optional `asset_id`. No new packages, no new services, no schema changes beyond the single migration.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend, web target)
**Primary Dependencies**: FastAPI, Supabase Python client (backend, existing); `http`, `fl_chart`, `supabase_flutter`, Flutter Material (frontend, existing). **No new dependencies on either side.**
**Storage**: Supabase (PostgreSQL). Existing `system_status_reports`, `systems`, `assets`, `asset_system_links` tables. One migration adds `asset_id` column + adjusts partial unique index on `system_status_reports`.
**Testing**: Manual verification via `quickstart.md` against the live backend (same pattern as prior System Status specs — this project does not have automated backend tests for `system_status` endpoints).
**Target Platform**: Flutter Web PWA (primary, served via Nginx on Zorin OS server); backend is FastAPI on Uvicorn on the same server.
**Project Type**: Web application (FastAPI backend + Flutter frontend, monorepo layout).
**Performance Goals**: Sheet open-to-render under 500 ms on a warm backend; Status grid re-render within one animation frame when `asset_issues_count` arrives (the only new field on the today payload is a single integer per system).
**Constraints**: Status screen already loads under 1 s; this feature must not regress that (new field is a single int, no extra query on `/system-status/today` — counts are derived from the same open-reports query already running there, grouped by `system_id`).
**Scale/Scope**: 24 active systems today; typical asset count per system is single-digit (confirmed via `asset_system_links` usage pattern). Drill-in sheet payload stays well under 10 KB in the realistic case.

## Constitution Check

Evaluating against the 7 principles from `.specify/memory/constitution.md` (v1.0.0):

- **I. Full-Stack Ownership** — ✅ Feature spans every layer: Supabase migration, FastAPI router change + new endpoint, Flutter model update (`SystemStatus`, `SystemStatusReport`, `SystemUptimeReport`, new `AssetStatusEntry`, `AssetUptimeReport`), Flutter service (`SystemStatusService` gains asset methods; new `reportIssue`/`resolveIssue`/`updateIssue` accept optional asset id), Flutter screen changes (`system_status_screen.dart` + new `system_status_sheet.dart`), and docs updates (AGENT.md / this plan / quickstart). No layer skipped.

- **II. Explicit Over Automatic** — ✅ Asset-level issue transitions are explicit operator actions (identical flow to today's system-level flow). No silent state changes. Cascading removal on asset delete is an explicit PostgreSQL `ON DELETE CASCADE` — documented here and in the migration, visible in schema, not hidden behavior.

- **III. Role-Based Access Control** — ⚠️ Pre-existing gap (see Complexity Tracking). The current `/system-status/*` endpoints have no role enforcement (they rely on the reporter-provided email in the body). This spec preserves the existing pattern and does not introduce NEW role enforcement gaps — every behavior added here inherits the same access profile as the existing system-level flow. Closing this gap is out of scope and would affect multiple specs beyond 086.

- **IV. Server-First File Storage** — ✅ N/A. Feature touches no files.

- **V. Client-Side Computation Where Possible** — ✅ Asset uptime calculation lives server-side (consistent with existing per-system computation in `get_uptime_report`). Rationale: the uptime math reads unresolved-interval data already scoped on the server; shipping raw reports to the client to recompute would duplicate logic and increase payload. Client-side only handles sort-by-worst-uptime and rendering — both trivially cheap.

- **VI. Audit Everything** — ⚠️ Pre-existing gap (see Complexity Tracking). The current `/system-status/*` endpoints do not call `log_activity`. This spec preserves that existing pattern — no new audit behavior is added, and nothing existing is removed. Closing this gap would require a broader cross-spec refactor.

- **VII. Simplicity & YAGNI** — ✅ Minimal delta: one nullable column, one new endpoint, one additive field on today's payload, one new query param on the uptime endpoint, one new Flutter widget, two modified widgets. No configurability, no abstraction layers, no future-proofing. The drill-in sheet reuses the four existing bottom sheets (report/edit/resolve/delete) parametrized with an optional asset — not a rewrite.

**Gate result (initial)**: ✅ PASS with two pre-existing gaps (III, VI) noted in Complexity Tracking. No new violations introduced.

**Gate result (post-Phase-1 re-check)**: ✅ PASS. One YAGNI smell caught during re-check — an earlier draft had `include_assets=true` as an optional query param on `GET /system-status/report`, guarding against a non-existent future consumer. Per principle VII, this was removed; the endpoint now always returns the `assets` array. See research.md Decision 5 for the full rationale. No other violations discovered during Phase 1 design.

## Project Structure

### Documentation (this feature)

```text
specs/086-per-asset-status/
├── plan.md              # This file
├── research.md          # Phase 0 — design decisions and rationale
├── data-model.md        # Phase 1 — the one migration, schema diff, unique-index logic
├── quickstart.md        # Phase 1 — manual verification steps per user story
├── contracts/
│   └── api.md           # Phase 1 — request/response shapes for all affected endpoints
├── checklists/
│   └── requirements.md  # Spec quality checklist (already written)
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── system_status.py          # Modified: accept asset_id on POST/PUT; join assets on GET; add GET /systems/{id}/assets; always include per-asset array on GET /report
└── (no new files)

frontend/
├── lib/
│   ├── models/
│   │   └── system_status_report.dart    # Modified: add assetId/assetName to SystemStatusReport; add assetIssuesCount to SystemStatus; add AssetStatusEntry; add AssetUptimeReport
│   ├── services/
│   │   └── system_status_service.dart   # Modified: optional assetId params; new fetchSystemAssets(systemId) method
│   ├── screens/
│   │   └── system_status_screen.dart    # Modified: card renders asset_issues_count badge; tap always opens drill-in sheet (replaces direct-report-sheet flow); uptime cards become ExpansionTiles with per-asset rows
│   └── widgets/
│       └── system_status_sheet.dart     # NEW: drill-in bottom sheet widget
└── (no new files beyond system_status_sheet.dart)

supabase/
└── migrations/
    └── 20260418000000_add_asset_id_to_system_status_reports.sql   # NEW: one migration
```

**Structure Decision**: Existing monorepo web-app layout (backend/, frontend/, supabase/). No new top-level directories. All changes land in known locations for the System Status feature. The Infrastructure screen and its related files (spec 061 territory — `frontend/lib/screens/admin/infrastructure_screen.dart`, `system_detail_screen.dart`, `systems_service.dart`) are NOT modified by this feature (per FR-015).

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Preserving pre-existing RBAC gap on `/system-status/*` endpoints (no role enforcement; caller-supplied `reported_by` email) | Adding role enforcement here would require either adding a middleware layer used nowhere else in the router, or a wider refactor across all system_status endpoints (GET today, GET history, POST, PATCH, PUT, DELETE) which is out of scope for this spec and would risk destabilizing existing behavior. | A partial fix (role on just the new asset-level writes) would be inconsistent and confusing. A full fix is a separate spec. |
| Preserving pre-existing audit gap on `/system-status/*` endpoints (no `log_activity` calls) | Same reasoning: the existing router never audits. Introducing audit only on the new asset-level paths would create asymmetric behavior (system-level writes unaudited, asset-level writes audited). A consistent fix is a cross-spec refactor. | Partial audit would mislead anyone reading the log — they'd see asset reports but not system reports and assume system-level reports are silent. |
