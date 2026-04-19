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
