# Phase 1 Data Model: Per-Asset System Status Reporting

**Feature**: 086-per-asset-status
**Date**: 2026-04-18

This feature touches one table — `system_status_reports` — via a single migration. No new tables. No renames.

## Current schema (before this migration)

```sql
-- system_status_reports (current)
-- Created in a pre-tracked migration; `system_id` FK added in
-- supabase/migrations/20260414150000_infrastructure_refactor.sql
id              uuid            PRIMARY KEY DEFAULT gen_random_uuid()
system_id       uuid            NOT NULL REFERENCES systems(id)
report_date     date            NOT NULL
notes           text            DEFAULT ''
reported_by     text            NOT NULL         -- email, not FK
reported_by_name text           DEFAULT ''
created_at      timestamptz     DEFAULT now()
resolved_at     timestamptz     NULL             -- NULL = open
resolved_by     text            NULL
resolved_notes  text            DEFAULT ''
-- (no DB-level unique index today; "one open per (system, date)" is Python-only)
```

## Target schema (after this migration)

```sql
-- system_status_reports (after 20260418000000_add_asset_id_to_system_status_reports.sql)
id              uuid            PRIMARY KEY DEFAULT gen_random_uuid()
system_id       uuid            NOT NULL REFERENCES systems(id)
asset_id        uuid            NULL REFERENCES assets(id) ON DELETE CASCADE   -- NEW
report_date     date            NOT NULL
notes           text            DEFAULT ''
reported_by     text            NOT NULL
reported_by_name text           DEFAULT ''
created_at      timestamptz     DEFAULT now()
resolved_at     timestamptz     NULL
resolved_by     text            NULL
resolved_notes  text            DEFAULT ''

-- NEW indexes
CREATE INDEX idx_system_status_reports_asset
    ON system_status_reports(asset_id)
    WHERE asset_id IS NOT NULL;

CREATE UNIQUE INDEX idx_system_status_reports_open_unique
    ON system_status_reports (
        system_id,
        COALESCE(asset_id, '00000000-0000-0000-0000-000000000000'::uuid),
        report_date
    )
    WHERE resolved_at IS NULL;
```

## Migration file

**Path**: `supabase/migrations/20260418000000_add_asset_id_to_system_status_reports.sql`

```sql
-- Spec 086: Per-Asset System Status Reporting
-- Adds an optional asset_id link to system_status_reports so issues can be
-- scoped to a specific asset (e.g., "Damascus international circuit") rather
-- than the whole parent system (e.g., "AIDA NG"). Adds DB-level uniqueness
-- for one unresolved issue per (system, asset-or-system-level, date) triple.

BEGIN;

-- 1. Add nullable asset_id column with cascading delete.
ALTER TABLE system_status_reports
    ADD COLUMN IF NOT EXISTS asset_id uuid NULL
    REFERENCES assets(id) ON DELETE CASCADE;

-- 2. Index for asset-scoped lookups (e.g., the drill-in sheet query).
CREATE INDEX IF NOT EXISTS idx_system_status_reports_asset
    ON system_status_reports(asset_id)
    WHERE asset_id IS NOT NULL;

-- 3. Partial unique index enforcing:
--    - One unresolved system-level issue per (system_id, report_date)
--      [matched when asset_id IS NULL via the COALESCE sentinel]
--    - One unresolved asset-level issue per (system_id, asset_id, report_date)
--    PostgreSQL treats NULL as distinct in unique indexes; COALESCE to the
--    all-zero UUID (never a real gen_random_uuid() output) folds NULLs into
--    a single equivalence class so system-level uniqueness is preserved.
CREATE UNIQUE INDEX IF NOT EXISTS idx_system_status_reports_open_unique
    ON system_status_reports (
        system_id,
        COALESCE(asset_id, '00000000-0000-0000-0000-000000000000'::uuid),
        report_date
    )
    WHERE resolved_at IS NULL;

COMMIT;
```

## Entity descriptions

### `system_status_reports` (modified)

One row per operator-reported availability issue. After this migration, the row is interpreted by the presence of `asset_id`:

| `asset_id` value | Interpretation |
|---|---|
| `NULL` | System-level issue (the whole system was down). Pre-existing rows are all in this state. |
| UUID | Asset-level issue scoped to the specific asset under the referenced system. |

Invariants preserved from prior behavior:
- `system_id` is NOT NULL.
- `report_date` is NOT NULL.
- `resolved_at IS NULL` ⇔ issue is open.
- `resolved_at >= report_date` when set (enforced in backend at `backend/routers/system_status.py:177-181`, untouched by this spec).

New invariants:
- For a given `(system_id, asset_id, report_date)` triple where `asset_id IS NULL` acts as a single sentinel value, at most one row may have `resolved_at IS NULL`.
- When an asset is deleted, all its asset-level reports (open and closed) are removed automatically by the FK cascade.

### `assets` (unchanged, referenced)

Existing Asset Registry table (spec 053). Referenced by the new `asset_id` column via `ON DELETE CASCADE`. No schema change.

### `asset_system_links` (unchanged, read)

Existing join table (spec 053 / 056). Read by the backend to:
1. Enumerate a system's linked assets for the new `GET /system-status/systems/{id}/assets` endpoint.
2. Validate that `asset_id` provided on `POST /system-status/report` is actually linked to the provided `system_name`.

No schema change.

### `systems` (unchanged, read)

Existing systems table (spec 056). No schema change.

## Backfill

**None required.** All existing `system_status_reports` rows keep `asset_id = NULL`, which is the correct representation of their pre-existing semantics (system-level issues).

## Rollback

Fully reversible:

```sql
BEGIN;
DROP INDEX IF EXISTS idx_system_status_reports_open_unique;
DROP INDEX IF EXISTS idx_system_status_reports_asset;
ALTER TABLE system_status_reports DROP COLUMN IF EXISTS asset_id;
COMMIT;
```

Rolling back is safe if done before any asset-level reports are written. After the backend ships, dropping `asset_id` would also drop any asset-level reports recorded in the meantime — which is acceptable rollback semantics (the operator would need to re-record current issues at the system level). No orphan rows result.

## Impact on existing queries

The single change to the existing query in `get_today_status` (at [backend/routers/system_status.py:55-62](../../backend/routers/system_status.py#L55-L62)) is the addition of a grouped count-per-system for asset-level open reports. The existing filter `is_("resolved_at", "null")` keeps system-level semantics identical; the same query is extended to count asset-id-scoped open reports alongside the system-level ones. See contracts/api.md for the exact response shape.

The existing query in `get_uptime_report` (at [backend/routers/system_status.py:336-346](../../backend/routers/system_status.py#L336-L346)) is extended only when `include_assets=true` is passed: it groups the existing interval-overlap computation by both `system_id` AND `asset_id` instead of `system_id` alone, then rolls up at the system level for the top-level response and keeps the per-asset breakdown under the new `assets` array.

No existing query is removed.
