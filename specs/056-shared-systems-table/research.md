# Research: Shared Systems Table

**Branch**: `056-shared-systems-table` | **Date**: 2026-04-14

## Decision 1: Case-insensitive uniqueness strategy

**Decision**: Use a `UNIQUE INDEX ON LOWER(name)` functional index on a regular `text` column.

**Rationale**: Supabase (PostgreSQL) supports `citext` via extension, but a functional index is simpler — no extension to enable, no implicit magic. The application stores the canonical casing (e.g., "CADAS-ATS") while the index prevents "cadas-ats" from being inserted as a duplicate. All comparisons in migration and validation use `LOWER()`.

**Alternatives considered**:
- `citext` extension — works but requires `CREATE EXTENSION IF NOT EXISTS citext`, adds implicit behavior that may confuse contributors unfamiliar with PostgreSQL extensions.
- Application-level check only — fragile, race-condition-prone without DB constraint.

## Decision 2: FK migration strategy for existing text columns

**Decision**: Add new `system_id uuid` FK columns alongside existing text columns. Populate via UPDATE-from-JOIN. Drop old text columns only after verification.

**Rationale**: Two-step migration is safer — the old text columns remain as rollback safety until the next release cycle. The migration:
1. Creates the `systems` table and seeds it.
2. Adds `system_id` columns to `asset_system_links` and `system_status_reports`.
3. Populates `system_id` by matching existing text values to `systems.name`.
4. Adds FK constraints and NOT NULL after population.
5. Old text columns (`system`, `system_name`) are dropped in a follow-up or at the end of the same migration once verified.

**Alternatives considered**:
- In-place rename — risky, no rollback path if migration fails mid-way.
- Deferred FK enforcement — adds complexity without safety benefit.

## Decision 3: Sort order implementation

**Decision**: Integer `sort_order` column, default 0. Migration seeds values 1–24 matching the current ALLOWED_SYSTEMS list order. Admin UI allows drag-reorder or manual number entry.

**Rationale**: The System Status screen renders systems in the order defined by ALLOWED_SYSTEMS. Users rely on this grouping (INDRA CCTV cameras together, International Circuits together). An integer sort order preserves this while allowing future reordering without code changes.

**Alternatives considered**:
- Sort by category + name alphabetically — would scatter INDRA CCTV cameras and reorder International Circuits differently than users expect.
- No sort order — would default to insertion order or alphabetical, breaking existing UX.

## Decision 4: `needs_review` flag for unknown free-text values

**Decision**: Add a `needs_review boolean DEFAULT false` column to the `systems` table. The migration sets `needs_review = true` for any system name found in `asset_system_links.system` that doesn't match a canonical ALLOWED_SYSTEMS entry.

**Rationale**: Asset Registry allows free-text system names. The migration must handle unknown values gracefully — creating them as active systems flagged for admin review. The admin UI can filter on `needs_review` to surface these for cleanup.

**Alternatives considered**:
- Logging only — not actionable from the UI, easy to miss.
- Rejecting unknowns — would break FK constraint population, data loss risk.

## Decision 5: Unique constraint changes on asset_system_links

**Decision**: The existing unique indexes `idx_asset_system_links_unique (asset_id, system, role)` and `idx_asset_system_links_primary_standby (system, role)` must be recreated to use `system_id` instead of `system` text after migration.

**Rationale**: The old indexes reference the `system` text column. After migration to `system_id`, new unique indexes on `(asset_id, system_id, role)` and `(system_id, role) WHERE role IN ('primary', 'standby')` must replace them to maintain the same business rules.

## Decision 6: pattern_alerts.system and work_order_entities.system — out of scope

**Decision**: These text columns remain as-is. They are NOT migrated to FK the systems table.

**Rationale**: Per clarification, `work_order_entities.system` stores AI-extracted values that may not perfectly match canonical names. `pattern_alerts.system` is populated from entity extraction output and follows the same pattern. Both are better left as free text with the extraction prompt guiding toward canonical names.

## Decision 7: Admin UI placement

**Decision**: Standalone admin screen at "Systems" in the settings admin section, between "Asset Registry" and "Department Routing".

**Rationale**: Consistent with how other admin features (User Management, Departments, Asset Registry, Department Routing, Settings) are structured in `settings_page.dart` lines 311–396. Each admin feature has its own SettingsRow with icon, label, subtitle, and MaterialPageRoute navigation.
