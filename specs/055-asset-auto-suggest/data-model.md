# Data Model: Auto-Suggest Asset Registry Additions (055)

**Date**: 2026-04-14 | **Branch**: `055-asset-auto-suggest`

## Entities

### No New Tables

This feature uses existing tables only. No migration needed.

### Existing Tables Used

**1. `pattern_alerts`** (read-only)
- `equipment_id` (text) — grouped to find distinct unregistered equipment
- `fault_type` (text) — aggregated to show common fault types per suggestion

**2. `assets`** (read-only for matching)
- `name` (text) — compared case-insensitively against alert equipment_ids

**3. `work_order_entities`** (read-only for metadata inference)
- `equipment_id` (text) — matched to suggestion equipment_id
- `equipment_type` (text) — most common value becomes inferred type

**4. `system_settings`** (read + write for dismissed list)
- Existing key-value table from spec 052
- Key: `dismissed_asset_suggestions`
- Value: JSON array of dismissed equipment_id strings, e.g. `["AN816-12 fitting...", "Room KCMC-S-65"]`
- Created on first dismiss if not exists; appended on subsequent dismisses

---

## Computed Entity: Asset Suggestion

Not stored in any table — computed at query time by the suggestions endpoint.

| Field | Source | Description |
|-------|--------|-------------|
| equipment_id | `pattern_alerts.equipment_id` | The unregistered equipment name |
| alert_count | COUNT of `pattern_alerts` rows | How many alerts reference this equipment |
| fault_types | DISTINCT `pattern_alerts.fault_type` | List of fault types from alerts |
| inferred_type | MODE of `work_order_entities.equipment_type` | Most common equipment type from extractions (nullable) |

**Filtering logic** (applied server-side):
1. Group `pattern_alerts` by `equipment_id`, count >= 2
2. Exclude equipment_ids that match any `assets.name` (case-insensitive)
3. Exclude equipment_ids in the `dismissed_asset_suggestions` setting
4. For each remaining equipment_id, query `work_order_entities` for inferred type

---

## Data Flow

```
pattern_alerts.equipment_id
    │
    ├── EXCLUDE: assets.name (case-insensitive match)
    ├── EXCLUDE: system_settings['dismissed_asset_suggestions']
    ├── FILTER: alert_count >= 2
    │
    └── ENRICH: work_order_entities.equipment_type (most common)
          │
          └── Asset Suggestion (returned to frontend)
```
