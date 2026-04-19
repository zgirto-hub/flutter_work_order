# Phase 1 Quickstart: Per-Asset System Status Reporting

**Feature**: 086-per-asset-status
**Date**: 2026-04-18

Manual verification plan for a fully-deployed build. Follows the same style as prior System Status specs (055, 056, 061) — no automated test suite exists for this router.

## Prerequisites

- Backend deployed with spec 086 changes and restarted (`sudo systemctl restart document_server.service` — per memory `feedback_restart_backend_after_routes`).
- Frontend deployed with spec 086 changes (`./scripts/deploy_frontend.sh`).
- Migration `20260418000000_add_asset_id_to_system_status_reports.sql` applied to Supabase.
- A system with at least two linked assets. Example used below: `AIDA NG` with assets `Damascus international circuit` (primary, production) and `Aleppo circuit` (standby, production).
- Logged in as an operator (any role — `/system-status/*` endpoints don't enforce role, per the existing pattern).

## Happy-path verification (User Story 1 — P1)

**Goal**: Record an asset-level issue, see it propagate to grid + history, then resolve it.

1. **Open Status screen**. AIDA NG card shows 🟢 OK, no badge.
2. **Tap AIDA NG card**. Drill-in sheet opens.
   - Header shows "AIDA NG" with system-level green dot.
   - System-level section shows prominent full-width red "Report System Issue" button.
   - "Assets" section shows spinner briefly, then two rows: `Damascus international circuit` (primary · production, 🟢 OK) and `Aleppo circuit` (standby · production, 🟢 OK).
3. **Tap Damascus international circuit row**. Report Issue sheet opens, header reads "AIDA NG → Damascus international circuit".
4. **Submit with today's date + notes "line degraded"**. Sheet closes with "Issue reported" snackbar.
5. **Drill-in sheet re-renders**. Damascus row now shows 🔴 Issue. Aleppo unchanged.
6. **Close the sheet**. Back on the Status screen:
   - AIDA NG card shows 🟢 OK + amber "⚠ 1" badge (✅ **User Story 2 acceptance scenario #1**).
   - Recent Issues list at the bottom shows a new row labeled "AIDA NG → Damascus international circuit" with "Unresolved" pill.
7. **Re-open AIDA NG drill-in sheet**. Tap Damascus row. Issue Details sheet opens showing the notes. Tap **Resolve** → fill resolve notes, today's date → Confirm.
8. **After resolve**: Damascus row returns to 🟢 OK, drill-in sheet re-fetches. Close the sheet.
9. **Grid**: AIDA NG card shows 🟢 OK, no badge. History row for Damascus now shows "Resolved" pill.

✅ User Story 1 passed.

## Grid badge verification (User Story 2 — P2)

**Setup**: Reuse the scenario above — report an issue on Damascus (but don't resolve it yet).

1. **System OK + asset issue**: AIDA NG card shows 🟢 OK + amber "⚠ 1". ✅ Scenario 1.
2. **System issue + asset issue**: Open drill-in sheet, tap "Report System Issue" on the SAME system (AIDA NG) with a different note. Close sheet. AIDA NG card now shows 🔴 Issue + amber "⚠ 1". ✅ Scenario 2.
3. **No issues**: Resolve both. AIDA NG card returns to its original OK state — no badge. ✅ Scenario 3.

## Uptime Report per-asset breakdown (User Story 3 — P3)

**Setup**: Need historical data. If this is a fresh environment, either wait or seed three open-and-closed reports on `Damascus international circuit` dated within the last 30 days (e.g., reported on day N, resolved on day N+1, repeated three times).

1. **Open the Uptime Report** (pie-chart icon top-right of Status screen). The frontend calls `/system-status/report` with no extra flag; the backend now always returns a per-asset breakdown.
2. **Set range**: last 30 days → **Generate Report**.
3. **Expand AIDA NG card** by tapping the chevron.
4. **Verify**:
   - AIDA NG system-level: 100.0% uptime (it had 0 days of system-level issues).
   - Expanded body: Damascus listed first with ~90% uptime, 🔴 red indicator (since 3 days / 30 days < 95%). Aleppo listed below at 100%, 🟢 green indicator. ✅ Scenario 1.
5. **All-green shortcut**: pick a system with no issues in the range (e.g., AMHS). Expand its card. Body shows a single line "All assets operational for the period" with no per-asset rows. ✅ Scenario 2.
6. **System with no linked assets**: pick a system that has no entries in `asset_system_links`. Expand its card. Body shows "No linked assets". ✅ Scenario 3.

## Error-path verification

### Duplicate asset-level issue (FR-003)

1. On AIDA NG drill-in sheet, report an issue on Damascus today.
2. Without resolving, try to report another issue on Damascus today.
3. **Expected**: 409 response; snackbar shows `"An unresolved issue already exists for Damascus international circuit on 2026-04-18"`. No second row created.

### Asset not linked to chosen system (FR-002)

This is only reachable via the API since the UI only lists linked assets. With `curl`:

```bash
curl -X POST https://.../system-status/report \
  -H "Content-Type: application/json" \
  -d '{
    "system_name": "AMHS",
    "asset_id": "<a uuid of an asset linked only to AIDA NG>",
    "report_date": "2026-04-18",
    "notes": "test",
    "reported_by": "test@example.com",
    "reported_by_name": "Test"
  }'
```

**Expected**: 400 with message `"Asset <asset_name> is not linked to system AMHS"`.

### System-level issue coexisting with asset-level issue for same date

Covered in User Story 2 scenario 2 above. Both reports stored; grid card shows both indicators; both resolvable independently.

### Cascading delete on asset removal (FR-016, Edge case)

1. Report an open issue on Damascus (don't resolve).
2. In Infrastructure → AIDA NG → Damascus, **delete the asset** (via the existing asset delete action in the system_detail_screen sheet).
3. Return to Status screen. AIDA NG card no longer shows the "⚠ 1" badge. Damascus row is gone from drill-in sheet.
4. Confirm via Supabase SQL: the row for that open report is removed (FK `ON DELETE CASCADE`). No orphan reports remain.

### Drill-in sheet network failure

1. Open drill-in sheet while backend is up — verify it works.
2. Stop the backend (`sudo systemctl stop document_server.service`) — leave frontend running.
3. Open drill-in sheet on AIDA NG. Header + system-level section render from grid-cached data. Asset list area shows inline error with **Retry** button.
4. Restart backend. Tap **Retry**. Assets load.

### Tap a healthy system with zero assets (FR-007, Edge case)

1. Pick a system with no linked assets AND no current issues.
2. Tap its card.
3. **Expected**: Drill-in sheet opens. System-level section shows prominent "Report System Issue" button. Assets section shows "No assets linked. Link assets in Infrastructure." No dead-end.

## Performance smoke-test

1. **Grid load time** should match pre-feature baseline (< 1 s on warm backend). Verify the only new field is a per-system integer.
2. **Drill-in open time** on a warm backend should be < 500 ms (two Supabase queries in parallel).

## Rollback verification

If rolling back:

1. Revert frontend and backend code.
2. Restart backend.
3. Run rollback migration (see data-model.md § Rollback).
4. Confirm Status screen renders pre-feature (no badges, no drill-in sheet, tapping a card opens the original Report Issue sheet).
5. Existing system-level reports remain intact.

## Acceptance mapping

| Spec user story | Quickstart section | Spec acceptance scenario |
|---|---|---|
| US1 (P1) — report/resolve asset issue | Happy-path verification | Scenarios 1–4 |
| US2 (P2) — grid badge | Grid badge verification | Scenarios 1–3 |
| US3 (P3) — per-asset uptime | Uptime Report per-asset breakdown | Scenarios 1–3 |
| Edge: duplicate | Error-path — Duplicate asset-level issue | — |
| Edge: asset-not-linked | Error-path — Asset not linked | — |
| Edge: cascade delete | Error-path — Cascading delete | — |
| Edge: network failure | Error-path — Drill-in sheet network failure | — |
| Edge: healthy-system dead-end | Error-path — Tap a healthy system with zero assets | — |
