---

description: "Per-Asset System Status Reporting — implementation tasks for opencode"
---

# Tasks: Per-Asset System Status Reporting (Spec 086)

**Input**: Design documents in `C:\Development\flutter_work_order\specs\086-per-asset-status\`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/api.md](contracts/api.md), [quickstart.md](quickstart.md)

**Tests**: This project has no automated test suite for the `system_status` router (manual verification via [quickstart.md](quickstart.md)). **No test tasks are generated.** Verification is a manual pass of quickstart.md after implementation, handled in the Polish phase.

**Organization**: Tasks grouped by user story per spec.md priorities. Every task has a clear file path and is scoped tightly enough for direct execution.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks).
- **[Story]**: Which user story this task belongs to (US1, US2, US3). Foundational/Polish phases have no story label.
- Every task description names the exact file path to edit or create.

---

## Phase 1: Setup

**Purpose**: No project setup needed — all tooling, dependencies, and directories already exist. Spec 086 introduces no new dependencies.

_(No Phase 1 tasks. Skip directly to Phase 2.)_

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Database migration and backend API changes. Every frontend user story depends on these endpoints being live.

**⚠️ CRITICAL**: No frontend user-story work (US1, US2, US3) can begin until this phase is complete AND the backend is restarted.

- [x] T001 Create migration file `supabase/migrations/20260418000000_add_asset_id_to_system_status_reports.sql` with the exact SQL given in [data-model.md § Migration file](data-model.md). Add nullable `asset_id` column (FK → `assets(id)` ON DELETE CASCADE), partial index on `asset_id`, and partial unique index `idx_system_status_reports_open_unique` using the `COALESCE(asset_id, '00000000-0000-0000-0000-000000000000'::uuid)` sentinel. Do NOT drop any existing index — grep confirmed there is no prior unique index on this table.

- [ ] T002 Apply the migration to Supabase (via Supabase MCP `apply_migration` or by running it against the production DB per project convention). Verify the column and both indexes exist via `list_tables` or a quick `\d system_status_reports`.

- [x] T003 In [backend/routers/system_status.py](../../backend/routers/system_status.py), extend `GET /system-status/today` (function `get_today_status`): run a single query pulling ALL open rows for the active systems (both `asset_id IS NULL` and `asset_id IS NOT NULL`), split client-side in Python into `system_level` dict (by `system_id`, only `asset_id IS NULL` rows) and `asset_counts_by_system` (Counter over rows where `asset_id IS NOT NULL`). Return each system with new field `asset_issues_count: int` (default 0 if absent from the counter). Existing `active_report` shape stays but also echo `asset_id`/`asset_name` as `null` (see T007 for the join helper). Preserve response otherwise.

- [x] T004 In [backend/routers/system_status.py](../../backend/routers/system_status.py), extend `GET /system-status/history` (function `get_history`): join `assets(id, name)` alongside the existing `systems(name)` join (use Supabase's `.select("*, systems(name), assets(name)")`). In the post-processing loop, surface `asset_id` (already a column) and `asset_name` (from `assets.name`, or `null` if `asset_id` is NULL) on each returned row. Delete the joined `assets` sub-object before returning, matching the existing pattern used for the `systems` join.

- [x] T005 In [backend/routers/system_status.py](../../backend/routers/system_status.py), extend `POST /system-status/report` (function `report_issue` + `ReportIssueBody`): add optional `asset_id: Optional[str] = None` field to the Pydantic model. When present: (1) verify the asset exists (`assets` lookup by id) — else HTTPException 400 `"Unknown asset: <id>"`. (2) Verify the `(system_id, asset_id)` pair exists in `asset_system_links` (any role, any site) — else HTTPException 400 `"Asset <asset_name> is not linked to system <system_name>"`. (3) Extend the existing duplicate-check query to filter on `asset_id` equality (including the IS NULL case for system-level). (4) Include `asset_id` in the INSERT payload. (5) Resolve `asset_name` from the asset lookup and include in the response object (or `null` when no asset).

- [ ] T006 In [backend/routers/system_status.py](../../backend/routers/system_status.py), extend `PUT /system-status/{report_id}` (function `update_issue`) and `PATCH /system-status/{report_id}/resolve` (function `resolve_issue`): when fetching the existing row, also fetch `asset_id`. In the duplicate-check query inside `update_issue` (when `report_date` changes), add `asset_id` equality (both NULL and non-NULL cases). The returned `report` object should carry `asset_id` and `asset_name` — use the shared helper from T007.

- [x] T007 In [backend/routers/system_status.py](../../backend/routers/system_status.py), add a helper `_attach_asset_name(report: dict, assets_by_id: dict) -> dict` that given a raw row and a pre-fetched `{asset_id: asset_name}` map populates `asset_id` (keep the column) and `asset_name` (looked up or None). Use this helper wherever a report row is returned (endpoints from T003, T004, T005, T006). This keeps the response shape consistent and avoids N+1 asset lookups — each endpoint pre-fetches all involved asset ids in one Supabase query.

- [x] T008 In [backend/routers/system_status.py](../../backend/routers/system_status.py), add the new endpoint `GET /system-status/systems/{system_id}/assets` (new async function `get_system_assets`). Behavior: (1) Look up system by id — 404 `"System not found"` if missing. (2) Fetch all `asset_system_links` rows where `system_id = {system_id}`, joining `assets(id, name)` — include `role` and `site` columns from the link row. (3) Fetch open reports: `system_status_reports` where `system_id = {system_id} AND asset_id IN (<asset ids>) AND resolved_at IS NULL`. Convert to `{asset_id: oldest_open_report}` dict (order by `created_at ASC`, keep first). (4) Build response: `{"system_id", "system_name", "assets": [{asset_id, asset_name, role, site, status: 'issue' if open else 'operational', active_report: {...} | null}]}` ordered by role (primary → standby → client) then asset_name ASC. See full contract in [contracts/api.md § 6](contracts/api.md).

- [x] T009 In [backend/routers/system_status.py](../../backend/routers/system_status.py), extend `GET /system-status/report` (function `get_uptime_report`): after computing the existing per-system numbers (which stay unchanged — system-level `asset_id IS NULL` only), additionally compute per-asset breakdowns for every active system. Algorithm: (a) Fetch `asset_system_links` joined to `assets` for all active systems. (b) Fetch reports with `asset_id IS NOT NULL` overlapping the range, grouped by `(system_id, asset_id)` with the same interval-overlap math currently applied per system. (c) For each system entry in the response, add `assets: [{asset_id, asset_name, role, site, total_days, days_with_issues, uptime_pct, downtime_pct}]` — always present, possibly empty array. No new query param.

- [ ] T010 After T001–T009: restart the backend with `sudo systemctl restart document_server.service` on the deployment server (per memory `feedback_restart_backend_after_routes`). Smoke-test by hitting `GET /system-status/today` and `GET /system-status/systems/<a real system id>/assets` via curl and confirming the expected new fields.

**Checkpoint**: Backend supports asset-level reporting end-to-end. Frontend user stories can now begin in parallel.

---

## Phase 3: User Story 1 - Report and resolve an issue on a specific asset (Priority: P1) 🎯 MVP

**Goal**: Operator can open an issue on a specific asset (linked via Infrastructure) and later resolve it — all without marking the parent system down. Delivers the MVP value of this feature.

**Independent Test**: After Phase 2, with a system like AIDA NG that has linked assets, open the Status screen → tap the AIDA NG card → the new drill-in sheet opens → tap an asset → the Report Issue sheet opens with `"AIDA NG → Damascus international circuit"` header → submit → row reflects the new status and resolving it reverts the row.

### Implementation for User Story 1

- [x] T011 [P] [US1] In [frontend/lib/models/system_status_report.dart](../../frontend/lib/models/system_status_report.dart), add two optional fields to `SystemStatusReport`: `final String? assetId` and `final String? assetName`. Parse from `asset_id` / `asset_name` in `fromJson`; include in `toJson` only when non-null. Update the constructor. Preserve all existing fields and defaults.

- [x] T012 [P] [US1] In [frontend/lib/models/system_status_report.dart](../../frontend/lib/models/system_status_report.dart), add a new class `AssetStatusEntry` with fields: `final String assetId`, `final String assetName`, `final String role`, `final String site`, `final String status` (`'operational'` or `'issue'`), `final SystemStatusReport? activeReport`. Implement `fromJson`. Also add a convenience getter `bool get hasIssue => status == 'issue';`. This entry represents one row in the drill-in sheet's asset list.

- [x] T013 [P] [US1] In [frontend/lib/services/system_status_service.dart](../../frontend/lib/services/system_status_service.dart), add new method `Future<SystemAssetsResponse> fetchSystemAssets({required String systemId})` hitting `GET /system-status/systems/$systemId/assets`. Define a small response wrapper `SystemAssetsResponse` with `{systemId, systemName, List<AssetStatusEntry> assets}` (put it in the models file alongside `AssetStatusEntry` or inline in the service — opencode's choice, follow existing file's style).

- [x] T014 [P] [US1] In [frontend/lib/services/system_status_service.dart](../../frontend/lib/services/system_status_service.dart), extend `reportIssue(...)` to accept `String? assetId` as an optional named parameter; include `asset_id` in the JSON body when non-null. Handle the new 400 case: when response body contains a message starting with `"Asset "` or `"Unknown asset"`, throw an `Exception` with that message (reuse the existing error pattern — do not invent a new exception class).

- [x] T015 [P] [US1] In [frontend/lib/services/system_status_service.dart](../../frontend/lib/services/system_status_service.dart), update `updateIssue(...)`: no signature change needed (operates by report id). Just ensure the response is parsed with the new `SystemStatusReport.fromJson` (which already handles `asset_id`/`asset_name`). Same for `resolveIssue(...)`.

- [x] T016 [US1] Create new file [frontend/lib/widgets/system_status_sheet.dart](../../frontend/lib/widgets/system_status_sheet.dart) defining a `SystemStatusSheet` `StatefulWidget` that takes: `final SystemStatus system` (for header + system-level card data already in memory), callbacks for report/edit/resolve/delete (for both system- and asset-level actions — passed from the parent so the sheet can reuse the existing bottom sheets on the screen), and a `VoidCallback? onChange` fired after any mutation so the parent can re-load the grid. The widget:
  1. Renders header with system name + system-level status dot (from `widget.system`) and a close button.
  2. Renders system-level section: open report detail + Edit/Delete/Resolve buttons when `system.activeReport != null`, otherwise a prominent full-width red "Report System Issue" button.
  3. Starts loading assets in `initState` via `SystemStatusService().fetchSystemAssets(systemId: ...)`. While loading, the asset-list area (NOT the header/system section) shows a `CircularProgressIndicator`.
  4. On error, the asset-list area shows an inline "Couldn't load assets" + Retry button (text-only, not full-screen).
  5. On success, lists each asset row: dot (green/red), name, subtitle `"<role> · <site>"`, tap handler. Tap → if `activeReport != null`, invokes the asset-issue-details callback; else invokes the report-asset-issue callback. Empty list → shows `"No assets linked. Link assets in Infrastructure."`.
  6. Mutations inside the sheet: after a callback resolves, re-invoke `fetchSystemAssets` AND call `widget.onChange?.call()`.

  Layout: `DraggableScrollableSheet` sized at ~85% initial, 0.95 max. Reuse `AppColors`/`AppShadows` styling from [frontend/lib/theme/app_theme.dart](../../frontend/lib/theme/app_theme.dart). No new theme tokens.

- [x] T017 [US1] In [frontend/lib/screens/system_status_screen.dart](../../frontend/lib/screens/system_status_screen.dart), refactor the existing `_showReportIssueSheet(system)` tap handler on `_SystemCard` to instead invoke a new `_showDrillInSheet(SystemStatus system)` method that opens the new `SystemStatusSheet` via `showModalBottomSheet(isScrollControlled: true, builder: (_) => SystemStatusSheet(...))`. Pass callbacks that invoke the EXISTING `_showReportIssueSheet`, `_showIssueDetailsSheet`, `_showEditIssueSheet`, `_showResolveSheet`, `_confirmDelete` methods. Set `onChange: _load` so the parent grid reloads after sheet mutations. Keep the old methods in place — they are reused by the sheet's callbacks, now parametrized (T018).

- [x] T018 [US1] In [frontend/lib/screens/system_status_screen.dart](../../frontend/lib/screens/system_status_screen.dart), parametrize the FIVE existing bottom-sheet methods with optional asset parameters:
  - `_showReportIssueSheet(SystemStatus system, {AssetStatusEntry? asset})` — when `asset` non-null, header becomes `"<system name> → <asset.assetName>"` and the call to `_service.reportIssue(...)` passes `assetId: asset.assetId`.
  - `_showIssueDetailsSheet(SystemStatus system, {AssetStatusEntry? asset})` — same header change; action buttons operate on `asset.activeReport` when asset is set (else `system.activeReport`).
  - `_showEditIssueSheet(SystemStatusReport report)` — no signature change needed (operates on the report that already knows its asset via `report.assetId`/`assetName`). If `report.assetName != null`, header reads `"<system name> → <asset name>"`.
  - `_showResolveSheet(SystemStatusReport report)` — same header tweak as above.
  - `_confirmDelete(SystemStatusReport report)` — update the confirmation text to include asset name when present (e.g., `"Delete the issue report for <system> → <asset> on <date>?"`).

  Do NOT duplicate these methods for asset-specific flows — reuse.

**Checkpoint**: User Story 1 is fully functional. Reporter can open the Status screen, drill into a system, report on a specific asset, and resolve it. History shows the `"System → Asset"` label. US2 and US3 can now proceed in parallel.

---

## Phase 4: User Story 2 - At-a-glance awareness of asset issues on the grid (Priority: P2)

**Goal**: On the Status grid, systems with asset-level open issues show an amber "⚠ N" badge alongside their system-level dot, without losing the system-vs-asset visual distinction.

**Independent Test**: With one asset-level issue open (from US1), load the Status screen. Confirm the parent system's card shows green dot + "OK" label + amber "⚠ 1" badge. Confirm that when the system itself also has an open report, the card shows red dot + "Issue" + amber badge (both visible). Confirm that a system with zero issues at any level is unchanged.

### Implementation for User Story 2

- [x] T019 [P] [US2] In [frontend/lib/models/system_status_report.dart](../../frontend/lib/models/system_status_report.dart), add `final int assetIssuesCount` field (default 0) to `SystemStatus`. Parse from `asset_issues_count` in `fromJson` with `json['asset_issues_count'] ?? 0`. Update constructor.

- [x] T020 [US2] In [frontend/lib/screens/system_status_screen.dart](../../frontend/lib/screens/system_status_screen.dart), modify the `_SystemCard` widget to render an amber badge when `system.assetIssuesCount > 0`. Badge content: `"⚠ ${system.assetIssuesCount}"` (use `Icons.warning_amber_rounded` with size 10 + the count text, or a Unicode `⚠` — opencode's choice, match [system_status_screen.dart:1131-1193](../../frontend/lib/screens/system_status_screen.dart#L1131) style). Colors: background `Color(0xFFFEF3C7)` (amber-100), foreground `Color(0xFFD97706)` (amber-700). Place the badge immediately after the OK/Issue label, before the status dot — so the layout becomes `[name] [OK/Issue label] [⚠ N badge?] [dot]`. The badge must NOT replace the system's own status dot or label; both must be visible simultaneously when both conditions apply.

**Checkpoint**: User Stories 1 AND 2 both work. Grid gives at-a-glance visibility of both levels.

---

## Phase 5: User Story 3 - Uptime report reveals which assets caused downtime (Priority: P3)

**Goal**: The Uptime Report's per-system card becomes an `ExpansionTile` that reveals per-asset uptime underneath, sorted worst-first, with green/amber/red severity indicators based on deterministic integer thresholds.

**Independent Test**: Generate an uptime report over a 30-day window where one asset had 3 days of issues and its parent system had 0 system-level issues. Confirm the top-level system card reads 100% uptime, expanding reveals the asset at 90% with a red indicator, and sibling assets at 100% with green indicators. Confirm the all-green shortcut works on a system where no issues exist in the period.

### Implementation for User Story 3

- [x] T021 [P] [US3] In [frontend/lib/models/system_status_report.dart](../../frontend/lib/models/system_status_report.dart), add a new class `AssetUptimeReport` with fields: `final String assetId`, `final String assetName`, `final String role`, `final String site`, `final int totalDays`, `final int daysWithIssues`, `final double uptimePct`, `final double downtimePct`. Implement `fromJson` parsing `asset_id`, `asset_name`, etc.

- [x] T022 [P] [US3] In [frontend/lib/models/system_status_report.dart](../../frontend/lib/models/system_status_report.dart), add `final List<AssetUptimeReport> assets` field (default `const []`) to `SystemUptimeReport`. In `fromJson`, parse `(json['assets'] as List? ?? []).map((j) => AssetUptimeReport.fromJson(j)).toList()`.

- [x] T023 [US3] In [frontend/lib/services/system_status_service.dart](../../frontend/lib/services/system_status_service.dart), `fetchUptimeReport(...)` needs NO signature change — the endpoint always returns the `assets` field now. Just ensure the response parse picks up the new `assets` field via the updated `SystemUptimeReport.fromJson` (automatic if T022 is correct).

- [x] T024 [US3] In [frontend/lib/screens/system_status_screen.dart](../../frontend/lib/screens/system_status_screen.dart), convert the `_SystemUptimeCard` widget from a plain `Container` into an `ExpansionTile` (or wrap with `Theme` + `ExpansionTile` to preserve styling). Collapsed body matches today's card (mini donut, system name, summary line). Expanded body:
  1. If `report.assets.isEmpty` → render one row: `"No linked assets"`.
  2. Else if `report.daysWithIssues == 0 AND report.assets.every((a) => a.daysWithIssues == 0)` → render one row: `"All assets operational for the period"`.
  3. Else: sort `report.assets` by `uptimePct` ASC (worst first), then render one compact row per asset:
     - 4px left border whose color matches the severity indicator.
     - Small dot of the same color.
     - Asset name bold, subtitle `"<role> · <site>"` lighter.
     - Right-side `"${uptimePct.toStringAsFixed(1)}%"` label.
     Severity thresholds (inline helper):
     - `daysWithIssues == 0` → green `Color(0xFF15803D)`
     - `daysWithIssues > 0 && uptimePct >= 95.0` → amber `Color(0xFFD97706)`
     - `uptimePct < 95.0` → red `Color(0xFFB91C1C)`

  The existing overall donut at the top of the report (`_OverallUptimeChart`) stays unchanged — it remains system-level only.

**Checkpoint**: All three user stories independently functional. Feature complete for manual verification.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Deploy, verify, document.

- [ ] T025 Deploy frontend with `./scripts/deploy_frontend.sh` (per existing convention). Bump version via `./scripts/bump_version.sh` if required by local practice.

- [ ] T026 Execute every section of [quickstart.md](quickstart.md) against the deployed build:
  - Happy-path User Story 1
  - User Story 2 grid badge verification
  - User Story 3 uptime per-asset breakdown (plus all-green and no-assets shortcuts)
  - All five error-path cases (duplicate, asset-not-linked, coexistence, cascade delete, network failure, healthy-system tap)
  - Performance smoke-test

  Record any failures as follow-up tasks — do NOT mark the spec complete until every quickstart section passes.

- [ ] T027 [P] Update [AGENT.md](../../AGENT.md) (if a System Status section exists — otherwise skip) to reference the new drill-in sheet and the new `GET /system-status/systems/{id}/assets` endpoint. This is documentation-only.

- [ ] T028 [P] Update [ARCHITECTURE.md](../../ARCHITECTURE.md) (if a System Status section exists — otherwise skip) with a short note on per-asset reporting and the `asset_id` column + partial unique index. Documentation-only.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: Empty — no tasks.
- **Phase 2 (Foundational, T001–T010)**: Must complete before ANY frontend work. Within this phase: T002 depends on T001; T003–T009 depend on T002; T007 (helper) should land before T003/T004/T005/T006 reference it, but they can be written in the same commit. T010 (restart) depends on all of T003–T009.
- **Phase 3 (US1, T011–T018)**: Starts after T010. T011/T012/T013/T014/T015 can run in parallel (different files or different methods of one file). T016 depends on T012 + T013. T017 depends on T016. T018 depends on T011, T012 (references `AssetStatusEntry`).
- **Phase 4 (US2, T019–T020)**: Can start in parallel with Phase 3 once Phase 2 is done. T020 depends on T019.
- **Phase 5 (US3, T021–T024)**: Can start in parallel with Phases 3 and 4 once Phase 2 is done. T024 depends on T021, T022.
- **Phase 6 (Polish, T025–T028)**: T025 + T026 depend on all prior phases. T027 + T028 are documentation-only and can run in parallel with each other.

### User Story Dependencies

- **US1 (P1)** is the MVP — delivers the core capability of reporting per-asset issues. All other stories build on top of the same foundation (Phase 2) but US1 is NOT a prerequisite for US2 or US3.
- **US2 (P2)** only requires Phase 2 (backend already returns `asset_issues_count`). It could ship standalone — the badge would light up when an issue is recorded via API.
- **US3 (P3)** only requires Phase 2 (backend already returns `assets` array on uptime report). It could ship standalone.

### Parallel Opportunities

- **Within Phase 2**: T003/T004/T005/T006/T008/T009 all modify the SAME file ([backend/routers/system_status.py](../../backend/routers/system_status.py)) — they should be sequenced (one commit per task or grouped) to avoid merge conflict. Only T001 (new migration file) and T007 (helper addition) are truly parallelizable.
- **Within Phase 3**: T011/T012 both edit the same models file — sequence them. T013/T014/T015 all edit the service file — sequence them. T016 creates a new widget file (parallel to model/service work). T017 and T018 edit the same screen file — sequence them.
- **Across phases**: Once Phase 2 is done, Phases 3, 4, 5 are all on independent frontend files and can run in parallel if multiple agents are working.

---

## Parallel Execution Example: Phase 3 (US1)

After Phase 2 is complete:

```bash
# Agent A (models):
#   T011 → T012 (same file; serial)
# Agent B (service):
#   T013 → T014 → T015 (same file; serial)
# Agent C (widget, independent):
#   T016 (wait for T012 + T013 to land before compiling)
# Agent D (screen wiring):
#   T017 → T018 (same file; serial, wait for T016)
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Complete Phase 2 (backend + migration) — T001 through T010.
2. Complete Phase 3 (US1 — drill-in sheet + asset reporting) — T011 through T018.
3. **STOP and VALIDATE** via the User Story 1 section of [quickstart.md](quickstart.md).
4. At this point the feature's core value is deliverable and demo-able.

### Incremental delivery after MVP

1. Add US2 (T019–T020) → grid badge visible → verify scenario 1–3 of US2 quickstart.
2. Add US3 (T021–T024) → uptime breakdown visible → verify scenario 1–3 of US3 quickstart.
3. Polish phase (T025–T028).

---

## Notes for opencode

- **Read before writing**: every file named above already exists except [frontend/lib/widgets/system_status_sheet.dart](../../frontend/lib/widgets/system_status_sheet.dart) (new) and the migration file (new). For all other paths, `Read` the existing file first to match code style (indentation, AppColors usage, async patterns).
- **No new packages.** Do not add entries to `pubspec.yaml` or `requirements.txt`.
- **Preserve existing tests and demos.** This project has no system_status tests but has manual demo flows — don't break them.
- **Do not modify the Infrastructure screen or its related files** ([frontend/lib/screens/admin/infrastructure_screen.dart](../../frontend/lib/screens/admin/infrastructure_screen.dart), [frontend/lib/screens/admin/system_detail_screen.dart](../../frontend/lib/screens/admin/system_detail_screen.dart), [frontend/lib/services/systems_service.dart](../../frontend/lib/services/systems_service.dart)). Spec 086 is explicitly scoped to Status screen only.
- **Do NOT commit `backend/version.json`** (per memory `feedback_backend_version_json`).
- **Backend restart is mandatory after any change in [backend/routers/system_status.py](../../backend/routers/system_status.py)** (per memory `feedback_restart_backend_after_routes`).
- **Preserve the existing Python-level duplicate check** in POST/PUT — it produces friendly 409 messages. The DB unique index is defense-in-depth, not a replacement.
- **Ask before deviating from the API contract in [contracts/api.md](contracts/api.md)** — the frontend is built against that exact shape.
- **Commit strategy**: one commit per task (or tight logical group) with a message like `spec 086: T00X — <short description>`. This makes the Claude Code review (next step) easier to walk through.

---

## After opencode finishes

The user (Claude Code, via the superpowers:code-reviewer agent) will:

1. Review every commit against this tasks.md list and the spec/plan artifacts.
2. Verify all three user stories via the quickstart.md scenarios.
3. Flag any deviations from the API contract, the migration shape, or the UX specifications.
4. Flag any new dependencies introduced, any scope creep (e.g., Infrastructure screen modifications), or any skipped error handling.

**Deliverable from opencode**: a branch with all tasks checked off in this file, a clean `git log`, and a passing manual run of [quickstart.md](quickstart.md).
