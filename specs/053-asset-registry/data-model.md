# Data Model: Asset Registry (053)

**Date**: 2026-04-14 | **Branch**: `053-asset-registry`

## Entities

### 1. Asset

A physical device at DGCA (workstation, server, camera, router, switch, media converter, power adapter).

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | UUID | PK, auto-generated | Unique identifier |
| name | text | NOT NULL, UNIQUE | Asset name (e.g., "WS-01", "SRV-CADAS-01") |
| type | text | NOT NULL, CHECK in allowed values | One of: workstation, server, camera, router, switch, media_converter, power_adapter |
| location | text | NOT NULL | Physical location (e.g., "ACC Tower - Room 3") |
| notes | text | DEFAULT '' | Optional freeform notes |
| created_at | timestamptz | NOT NULL, DEFAULT now() | Record creation timestamp |
| updated_at | timestamptz | NOT NULL, DEFAULT now() | Last modification timestamp |

**Validation rules**:
- `name` must be unique across all assets (enforced by unique index)
- `type` must be one of the 7 predefined values (enforced by CHECK constraint)
- `name` and `location` must be non-empty

**Indexes**:
- `UNIQUE INDEX ON assets(name)` — name lookup for extraction matching
- `INDEX ON assets(type)` — type filtering

---

### 2. Asset-System Link

A many-to-many relationship between assets and systems, qualified by role.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | UUID | PK, auto-generated | Unique identifier |
| asset_id | UUID | NOT NULL, FK → assets(id) ON DELETE CASCADE | Parent asset |
| system | text | NOT NULL | System name (e.g., "CADAS-ATS", "AIDA-NG") |
| role | text | NOT NULL, CHECK in ('primary', 'standby', 'client') | Role of the asset within the system |
| created_at | timestamptz | NOT NULL, DEFAULT now() | Record creation timestamp |

**Validation rules**:
- `(asset_id, system, role)` must be unique — no duplicate associations
- For `primary` and `standby` roles: each system may have at most one asset per role (enforced by partial unique index)
- `client` role has no uniqueness constraint on system — multiple workstations can be clients of the same system
- Deleting an asset cascades to delete all its system links

**Indexes**:
- `UNIQUE INDEX ON asset_system_links(asset_id, system, role)` — prevent duplicate associations
- `UNIQUE INDEX ON asset_system_links(system, role) WHERE role IN ('primary', 'standby')` — enforce one primary + one standby per system
- `INDEX ON asset_system_links(asset_id)` — fast lookup by asset

---

### 3. Pattern Alert (MODIFIED — existing table)

The existing `pattern_alerts` table gains an optional `asset_context` field.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| asset_context | jsonb | DEFAULT NULL | Enrichment data: `{"name": "WS-01", "type": "workstation", "location": "ACC Tower - Room 3", "systems": [{"system": "CADAS-ATS", "role": "client"}, ...]}` |

This field is populated at alert creation time when `equipment_id` matches an asset name.

---

## Relationships

```
assets (1) ──── (N) asset_system_links
                     │
                     └── system (string, not FK — no systems table)

pattern_alerts.equipment_id ···· assets.name (soft lookup, not FK)
```

## Seed Data

The migration seeds the known DGCA systems as a SQL comment for reference (not a table). The following systems are used as frontend suggestions:

- CADAS-ATS
- CADAS-IMS
- AIDA-NG
- INDRA CCTV

### Pre-seeded Assets

AIDA-NG international circuits should be registered as individual assets (type: `router`) with a system link to AIDA-NG (role: `client`):

- Bahrain
- Karachi
- Tehran
- Doha
- Damascus
- Beirut

This ensures the extractor can map references like "Bahrain circuit down" to the correct system (AIDA-NG).

## State Transitions

Assets have no formal state machine. They exist or are deleted (hard delete with cascade).

Pattern alerts with `asset_context` are immutable after creation — the context is a snapshot at detection time.
