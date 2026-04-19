# Phase 1 API Contracts: Per-Asset System Status Reporting

**Feature**: 086-per-asset-status
**Date**: 2026-04-18
**Base router**: [backend/routers/system_status.py](../../../backend/routers/system_status.py)

All changes land in the existing `system_status.py` router. The backend URL prefix is `/` (no versioning; consistent with the rest of this project).

---

## 1. `GET /system-status/today` — MODIFIED

Returns the status of every active system for a given date (default: today).

### Request

| Parameter | In | Type | Required | Notes |
|---|---|---|---|---|
| `target_date` | query | string (`YYYY-MM-DD`) | no | Defaults to server's today. |

### Response (200)

```json
{
  "date": "2026-04-18",
  "systems": [
    {
      "system_id": "3f2c0000-0000-0000-0000-000000000000",
      "system_name": "AIDA NG",
      "status": "operational",
      "active_report": null,
      "asset_issues_count": 1
    },
    {
      "system_id": "3f2c0000-0000-0000-0000-000000000001",
      "system_name": "AMHS",
      "status": "issue",
      "active_report": {
        "id": "...",
        "system_name": "AMHS",
        "asset_id": null,
        "asset_name": null,
        "report_date": "2026-04-18",
        "notes": "...",
        "reported_by": "...",
        "reported_by_name": "...",
        "created_at": "...",
        "resolved_at": null,
        "resolved_by": null,
        "resolved_notes": ""
      },
      "asset_issues_count": 0
    }
  ]
}
```

### Changes from current

- **NEW** field `asset_issues_count: int` on every system entry. Counts rows in `system_status_reports` where `system_id = system.id AND asset_id IS NOT NULL AND resolved_at IS NULL`. Drives the amber card badge on the Status grid.
- `active_report` object (when present) now includes `asset_id: uuid | null` and `asset_name: string | null` fields; both are always `null` on this endpoint because `/today` only surfaces system-level reports in the `active_report` slot. Asset-level open reports are counted but not serialized inline here; the drill-in sheet fetches them via endpoint #6.
- **NEW** field `system_id: uuid` on every system entry. Stable identifier used by the drill-in sheet to fetch assets via endpoint #6.

### Backend implementation note

The count is derived from the same open-reports query already running. Change pseudocode:

```python
# Before:
active_reports = {r["system_id"]: r for r in rows_where_resolved_at_null_and_asset_id_null}

# After:
rows = select(...).in_("system_id", system_ids).is_("resolved_at", "null").execute()
system_level = {r["system_id"]: r for r in rows if r["asset_id"] is None}
asset_counts_by_system = Counter(r["system_id"] for r in rows if r["asset_id"] is not None)
```

One round-trip to Supabase, as before.

---

## 2. `GET /system-status/history` — MODIFIED

Returns the most recent reports (system-level AND asset-level interleaved, ordered by `created_at DESC`).

### Request

| Parameter | In | Type | Required | Notes |
|---|---|---|---|---|
| `system_name` | query | string | no | If set, filters to that system's history (includes both its system-level AND its asset-level reports). |
| `limit` | query | int | no | Default 50; max 200. |

### Response (200)

```json
{
  "reports": [
    {
      "id": "...",
      "system_name": "AIDA NG",
      "asset_id": "...",
      "asset_name": "Damascus international circuit",
      "report_date": "2026-04-18",
      "notes": "line degraded",
      "reported_by": "ops@example.com",
      "reported_by_name": "Ops Tech",
      "created_at": "...",
      "resolved_at": null,
      "resolved_by": null,
      "resolved_notes": ""
    },
    {
      "id": "...",
      "system_name": "AMHS",
      "asset_id": null,
      "asset_name": null,
      "report_date": "2026-04-17",
      "...": "..."
    }
  ]
}
```

### Changes from current

- **NEW** response fields `asset_id: uuid | null` and `asset_name: string | null` on each report row. When `asset_id` is null, the row is system-level (displays as "AMHS" in the UI); when set, the row is asset-level (displays as "AIDA NG → Damascus international circuit").
- Backend joins `assets` to resolve `asset_name` when `asset_id IS NOT NULL`. Single extra join, no N+1.

---

## 3. `POST /system-status/report` — MODIFIED

Creates a new issue report (system-level OR asset-level).

### Request

```json
{
  "system_name": "AIDA NG",
  "asset_id": "550e8400-e29b-41d4-a716-446655440000",
  "report_date": "2026-04-18",
  "notes": "line degraded",
  "reported_by": "ops@example.com",
  "reported_by_name": "Ops Tech"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `system_name` | string | yes | Case-insensitive match against `systems.name`. |
| `asset_id` | uuid | **no (NEW)** | When present, the report is asset-level. Must be linked to `system_name` via `asset_system_links`. |
| `report_date` | string (`YYYY-MM-DD`) | yes | |
| `notes` | string | no | Default `""`. |
| `reported_by` | string | yes | Reporter's email. |
| `reported_by_name` | string | no | Default `""`. |

### Response (200)

```json
{
  "report": {
    "id": "...",
    "system_name": "AIDA NG",
    "asset_id": "550e8400-e29b-41d4-a716-446655440000",
    "asset_name": "Damascus international circuit",
    "report_date": "2026-04-18",
    "notes": "line degraded",
    "reported_by": "ops@example.com",
    "reported_by_name": "Ops Tech",
    "created_at": "...",
    "resolved_at": null,
    "resolved_by": null,
    "resolved_notes": ""
  }
}
```

### Error responses

| Status | When | Example message |
|---|---|---|
| 400 | `system_name` does not match any row in `systems` | `"Unknown system: <name>"` (existing behavior) |
| 400 | `asset_id` provided but not linked to `system_name` via `asset_system_links` | `"Asset <asset_name> is not linked to system <system_name>"` |
| 400 | `asset_id` provided but does not exist in `assets` | `"Unknown asset: <asset_id>"` |
| 409 | Duplicate open report for `(system_id, asset_id-or-null, report_date)` | System-level: `"An unresolved issue already exists for <system_name> on <date>"` (unchanged). Asset-level: `"An unresolved issue already exists for <asset_name> on <date>"` |

The backend performs the Python-level check first (to emit the nice message) and falls back to catching the DB unique-index violation as a safety net.

### Changes from current

- Accepts optional `asset_id`.
- Validates asset-to-system linkage when `asset_id` is present.
- 409 branch also covers asset-level duplicates.
- Response always includes `asset_id` and `asset_name` (nullable).

---

## 4. `PATCH /system-status/{report_id}/resolve` — UNCHANGED signature

Resolves an open report (system-level or asset-level). The endpoint operates by `report_id` and does not need to distinguish between levels.

### Request, response

Unchanged from current. See [backend/routers/system_status.py:161-205](../../../backend/routers/system_status.py#L161-L205).

### Note

The response's `report` object now inherits the new `asset_id` / `asset_name` fields (because it echoes the row). Frontend may use them to render the updated drill-in row.

---

## 5. `PUT /system-status/{report_id}` and `DELETE /system-status/{report_id}` — UNCHANGED signature

Edit and delete operate by `report_id`. No new body fields needed.

### Note

Edit's 409 path (duplicate-on-date-change) applies identically to asset-level reports through the new unique index. The DB constraint and the existing Python pre-check both cover it; the error message format is the same family as on POST.

---

## 6. `GET /system-status/systems/{system_id}/assets` — NEW

Returns the assets linked to a given system, each with its current status.

### Request

| Parameter | In | Type | Required | Notes |
|---|---|---|---|---|
| `system_id` | path | uuid | yes | System UUID. |

### Response (200)

```json
{
  "system_id": "...",
  "system_name": "AIDA NG",
  "assets": [
    {
      "asset_id": "...",
      "asset_name": "Damascus international circuit",
      "role": "primary",
      "site": "production",
      "status": "issue",
      "active_report": {
        "id": "...",
        "system_name": "AIDA NG",
        "asset_id": "...",
        "asset_name": "Damascus international circuit",
        "report_date": "2026-04-18",
        "notes": "line degraded",
        "reported_by": "...",
        "reported_by_name": "...",
        "created_at": "...",
        "resolved_at": null,
        "resolved_by": null,
        "resolved_notes": ""
      }
    },
    {
      "asset_id": "...",
      "asset_name": "Aleppo circuit",
      "role": "standby",
      "site": "production",
      "status": "operational",
      "active_report": null
    }
  ]
}
```

### Response semantics

- Assets are enumerated from `asset_system_links WHERE system_id = {system_id}`; joined to `assets` for name/type.
- For each asset, `status` is `"issue"` if any row in `system_status_reports` has `system_id = {system_id} AND asset_id = <asset_id> AND resolved_at IS NULL` (date-independent — matches the system-level rule at [backend/routers/system_status.py:55-62](../../../backend/routers/system_status.py#L55-L62)).
- `active_report` is the oldest such open row (same tiebreak as the existing system-level `active_report`). If multiple open reports exist for different dates on the same asset, only the oldest is surfaced here; the history endpoint shows all of them.
- Assets are ordered by `role` (primary → standby → client) then `asset_name` ASC.
- Empty array when the system has no linked assets.

### Error responses

| Status | When | Example message |
|---|---|---|
| 404 | `system_id` not found in `systems` | `"System not found"` |

### Backend implementation note

Two queries: (1) `asset_system_links` JOIN `assets` for the link list, (2) `system_status_reports` filter on `system_id AND asset_id IN (<asset ids from step 1>) AND resolved_at IS NULL`. Merge client-side into the response shape. Parallelizable with `asyncio.gather`.

---

## 7. `GET /system-status/report` — MODIFIED

Uptime report for a date range. Now always includes per-asset breakdown.

### Request

Unchanged from current:

| Parameter | In | Type | Required | Notes |
|---|---|---|---|---|
| `start_date` | query | string (`YYYY-MM-DD`) | yes | |
| `end_date` | query | string (`YYYY-MM-DD`) | yes | |
| `system_name` | query | string | no | |

### Response (200)

```json
{
  "start_date": "2026-03-18",
  "end_date": "2026-04-18",
  "systems": [
    {
      "system_name": "AIDA NG",
      "total_days": 32,
      "days_with_issues": 0,
      "uptime_pct": 100.0,
      "downtime_pct": 0.0,
      "assets": [
        {
          "asset_id": "...",
          "asset_name": "Damascus international circuit",
          "role": "primary",
          "site": "production",
          "total_days": 32,
          "days_with_issues": 3,
          "uptime_pct": 90.6,
          "downtime_pct": 9.4
        }
      ]
    }
  ]
}
```

### Response semantics

- Top-level per-system numbers (`days_with_issues`, `uptime_pct`, `downtime_pct`) are computed EXACTLY as today — they include only system-level open intervals (reports where `asset_id IS NULL`). An asset being down 3 days does not increase the system's `days_with_issues`. This preserves the top donut's meaning ("the system as a whole was down N days").
- `assets` is always present and contains one entry per asset linked to that system (even assets with zero days with issues — so the frontend can render "All assets operational" when applicable). Empty array when the system has no linked assets.
- Each per-asset entry is computed from reports where `system_id = system.id AND asset_id = asset.id`, using the same date-interval-overlap logic as the per-system computation.
- `total_days` is the requested range length; identical across system and all assets.

### Changes from current

- **NEW** additive `assets` array on every system entry. Always present.
- Does NOT change the existing top-level numbers.
- Backward-compatible — existing clients that ignore unknown fields keep working unchanged.

### Error responses

Unchanged from current (400 for malformed dates; 400 for `start_date > end_date`; 400 for unknown `system_name`).

---

## Summary of additive fields on the wire

| Endpoint | New request fields | New response fields |
|---|---|---|
| `GET /system-status/today` | — | `asset_issues_count` per system; `asset_id` / `asset_name` on embedded `active_report` (always null here) |
| `GET /system-status/history` | — | `asset_id`, `asset_name` on each report |
| `POST /system-status/report` | `asset_id` (optional) | `asset_id`, `asset_name` on returned report |
| `PATCH /system-status/{id}/resolve` | — | `asset_id`, `asset_name` on returned report (echoed) |
| `PUT /system-status/{id}` | — | `asset_id`, `asset_name` on returned report (echoed) |
| `DELETE /system-status/{id}` | — | — |
| `GET /system-status/systems/{id}/assets` | NEW endpoint | — |
| `GET /system-status/report` | — | `assets` array always present per system |

All field additions are backward-compatible — existing clients that ignore unknown fields keep working unchanged.
