# Phase 1 — Data Model: System Status Infra Compatibility

## Scope

No schema changes. No new entities. No new migrations. This document exists to make that explicit.

## Entities consumed (unchanged)

### `SystemStatus` (in-memory model, `frontend/lib/models/system_status.dart`)

| Field | Type | Notes |
|-------|------|-------|
| `systemName` | `String` | Canonical system name. After spec 061, there are 7 of these. This spec renders it verbatim (FR-003). |
| `hasIssue` | `bool` | Drives OK / Issue display. Unchanged. |
| *(other existing fields)* | — | Untouched. |

### `SystemStatusReport` (history row)

| Field | Type | Notes |
|-------|------|-------|
| `systemName` / `system_name` | `String` | Name as recorded at report time. Repointed rows read "AIDA-NG". Rendered by `_HistoryCard` unchanged. |
| *(other existing fields)* | — | Untouched. |

## Database

No changes to `systems`, `system_status_reports`, `assets`, `asset_system_links`, or any other table. No migrations under `supabase/migrations/`.

## Service layer

`SystemStatusService` methods called by this screen — `fetchSystems()`, `fetchHistory()`, `reportIssue(...)`, `resolveIssue(...)`, `editIssue(...)`, `deleteIssue(...)` — are all invoked with identical arguments and consume identical responses. No signature change, no new call, no removed call.

## State that disappears (client-side only)

These fields in `_SystemStatusScreenState` are removed; they hold no persisted data:

- `_mainSystems: List<SystemStatus>` — derivable as `_systems`.
- `_groupedSystems: Map<String, List<SystemStatus>>` — always empty post-061; dead.
- `_expandedGroups: Set<String>` — UI-only toggle state; no UI consumes it after `_ExpandableGroup` is deleted.

No SharedPreferences key, no secure storage entry, no server state is involved.
