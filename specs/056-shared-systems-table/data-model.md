# Data Model: Shared Systems Table

**Branch**: `056-shared-systems-table` | **Date**: 2026-04-14

## New Table: `systems`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | uuid | PK, DEFAULT gen_random_uuid() | Unique identifier |
| name | text | NOT NULL | Canonical system name (e.g., "CADAS-ATS") |
| category | text | DEFAULT NULL | Optional grouping label (e.g., "INDRA CCTV", "International Circuits") |
| sort_order | integer | NOT NULL DEFAULT 0 | Display ordering for UI lists |
| is_active | boolean | NOT NULL DEFAULT true | Soft-delete flag; false = retired |
| needs_review | boolean | NOT NULL DEFAULT false | Flagged for admin review (migration-created unknowns) |
| created_at | timestamptz | NOT NULL DEFAULT now() | Row creation time |
| updated_at | timestamptz | NOT NULL DEFAULT now() | Last modification time |

**Indexes**:
- `UNIQUE INDEX idx_systems_name_lower ON systems(LOWER(name))` — case-insensitive uniqueness
- `INDEX idx_systems_active ON systems(is_active) WHERE is_active = true` — fast active-only queries
- `INDEX idx_systems_sort ON systems(sort_order)` — ordered listing

## Modified Table: `asset_system_links`

| Change | Column | Type | Details |
|--------|--------|------|---------|
| ADD | system_id | uuid | NOT NULL, FK → systems(id) |
| DROP | system | text | Replaced by system_id FK |

**Updated indexes** (replace text-based):
- `UNIQUE INDEX idx_asset_system_links_unique ON asset_system_links(asset_id, system_id, role)`
- `UNIQUE INDEX idx_asset_system_links_primary_standby ON asset_system_links(system_id, role) WHERE role IN ('primary', 'standby')`

## Modified Table: `system_status_reports`

| Change | Column | Type | Details |
|--------|--------|------|---------|
| ADD | system_id | uuid | NOT NULL, FK → systems(id) |
| DROP | system_name | text | Replaced by system_id FK |

## Unchanged Tables (out of scope)

- `work_order_entities.system` — remains text (AI-extracted, per clarification)
- `pattern_alerts.system` — remains text (populated from extraction output)

## Seed Data

The migration seeds 24 rows into `systems` from the current ALLOWED_SYSTEMS list:

| sort_order | name | category |
|------------|------|----------|
| 1 | AIDA-NG | NULL |
| 2 | CADAS-ATS | NULL |
| 3 | CADAS-IMS | NULL |
| 4 | Billing System | NULL |
| 5 | UPS | NULL |
| 6 | Permissions | NULL |
| 7 | IRTOS | NULL |
| 8 | International Circuits - Beirut | International Circuits |
| 9 | International Circuits - Damascus | International Circuits |
| 10 | International Circuits - Karachi | International Circuits |
| 11 | International Circuits - Tehran | International Circuits |
| 12 | International Circuits - Baghdad | International Circuits |
| 13 | International Circuits - Bahrain | International Circuits |
| 14 | INDRA CCTV - Camera 1 | INDRA CCTV |
| 15 | INDRA CCTV - Camera 2 | INDRA CCTV |
| 16 | INDRA CCTV - Camera 3 | INDRA CCTV |
| 17 | INDRA CCTV - Camera 4 | INDRA CCTV |
| 18 | INDRA CCTV - Camera 5 | INDRA CCTV |
| 19 | INDRA CCTV - Camera 6 | INDRA CCTV |
| 20 | INDRA CCTV - Camera 7 | INDRA CCTV |
| 21 | INDRA CCTV - Camera 8 | INDRA CCTV |
| 22 | INDRA CCTV - Camera 9 | INDRA CCTV |
| 23 | INDRA CCTV - Camera 10 | INDRA CCTV |
| 24 | *(any unrecognized free-text values)* | NULL, needs_review=true |

## Entity Relationships

```
systems (1) ←── (N) asset_system_links (N) ──→ (1) assets
systems (1) ←── (N) system_status_reports
```

## State Transitions

**System lifecycle**: `active` → `retired` (one-way soft-delete via `is_active = false`)
- Retired systems are excluded from selection dropdowns (`GET /api/systems?active_only=true`)
- Retired systems remain visible in historical records via JOINs
- No hard delete permitted while FK references exist
