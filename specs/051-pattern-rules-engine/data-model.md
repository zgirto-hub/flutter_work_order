# Data Model: Pattern Rules Engine

**Date**: 2026-04-13 | **Branch**: `051-pattern-rules-engine`

## Entities

### pattern_rules

Stores pattern detection rules (both built-in and custom).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | uuid | PK, default gen_random_uuid() | Unique rule identifier |
| name | text | NOT NULL | Human-readable rule name |
| description | text | | Detailed description of what the rule detects |
| severity | text | NOT NULL, CHECK (low/medium/high) | Alert severity level |
| detection_type | text | NOT NULL, CHECK (one of 6 types) | Detection function identifier |
| threshold_count | integer | DEFAULT 3 | Occurrence count threshold (used by count-based rules) |
| threshold_days | integer | DEFAULT 180 | Time window in days (used by time-based rules) |
| target_field | text | DEFAULT 'equipment_id' | Primary field to match on from work_order_entities |
| group_by_field | text | | Optional secondary grouping field |
| enabled | boolean | NOT NULL, DEFAULT true | Whether rule is active |
| is_built_in | boolean | NOT NULL, DEFAULT false | Marks the 6 seeded rules (informational only) |
| created_at | timestamptz | NOT NULL, DEFAULT now() | Creation timestamp |
| updated_at | timestamptz | NOT NULL, DEFAULT now() | Last modification timestamp |

**Detection type CHECK values**: `recurring_fault`, `technician_recurring`, `procedure_deviation`, `seasonal_pattern`, `long_resolution`, `parts_replaced_recurrence`

### pattern_alerts

Stores fired alert instances with lifecycle tracking.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | uuid | PK, default gen_random_uuid() | Unique alert identifier |
| rule_id | uuid | NOT NULL, FK → pattern_rules(id) ON DELETE CASCADE | Rule that triggered this alert |
| work_order_ids | uuid[] | NOT NULL | Array of work order IDs involved in the pattern |
| equipment_id | text | | Equipment identifier from the matched entity |
| fault_type | text | | Fault type from the matched entity |
| technician_id | text | | Technician ID (for technician-related rules) |
| severity | text | NOT NULL, CHECK (low/medium/high) | Copied from rule at detection time |
| status | text | NOT NULL, DEFAULT 'new', CHECK (new/acknowledged/resolved) | Alert lifecycle status |
| message | text | NOT NULL | Human-readable alert description |
| dedup_key | text | | Composite key for full-scan dedup: `{rule_id}:{equipment_id}:{fault_type}:{YYYY-MM}` |
| detected_at | timestamptz | NOT NULL, DEFAULT now() | When the pattern was detected |
| updated_at | timestamptz | NOT NULL, DEFAULT now() | Last status change timestamp |

**Indexes**:
- `idx_pattern_alerts_rule_id` on `rule_id`
- `idx_pattern_alerts_status` on `status`
- `idx_pattern_alerts_dedup_key` UNIQUE on `dedup_key` WHERE `dedup_key IS NOT NULL` (partial unique index — only applies to full-scan alerts that have a dedup_key; triggered-mode alerts have NULL dedup_key and are not constrained)
- `idx_pattern_alerts_detected_at` on `detected_at DESC` (for newest-first sorting)

## Relationships

```text
pattern_rules (1) ──────< (many) pattern_alerts
    │                         │
    │ id ←── rule_id          │ work_order_ids[] ──→ work_orders(id)
    │                         │
    └── detection_type        └── dedup_key (composite, for full scan only)
         maps to evaluation
         function in Python

work_order_entities ──→ evaluated by pattern_engine
    │
    │ Existing table (spec 049), not modified
    │ Columns used: work_order_id, equipment_id, equipment_type,
    │   fault_type, action_taken, procedure_followed, parts_replaced,
    │   technician_id, date
```

## State Transitions

### Alert Lifecycle

```text
  ┌─────┐      acknowledge      ┌──────────────┐      resolve      ┌──────────┐
  │ new │ ──────────────────→ │ acknowledged │ ──────────────→ │ resolved │
  └─────┘                      └──────────────┘                  └──────────┘
```

- **new**: Alert just fired, awaiting admin review
- **acknowledged**: Admin has seen and noted the alert
- **resolved**: Admin has taken action or dismissed the alert
- No backwards transitions permitted

### Rule Enabled/Disabled

```text
  ┌─────────┐      toggle      ┌──────────┐
  │ enabled │ ←──────────────→ │ disabled │
  └─────────┘                  └──────────┘
```

- Bidirectional toggle via admin UI
- Disabled rules are skipped during both triggered and full-scan evaluation

## Validation Rules

- Rule name: non-empty, max 200 characters
- Severity: must be one of `low`, `medium`, `high`
- Detection type: must be one of 6 valid type identifiers
- threshold_count: >= 1 (enforced in API)
- threshold_days: >= 1 (enforced in API)
- Alert status transitions: new→acknowledged→resolved only (enforced in API)
- dedup_key: constructed server-side, never user-supplied
