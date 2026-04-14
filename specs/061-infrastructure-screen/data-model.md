# Data Model — Infrastructure Screen

## Tables & Columns

### `systems` (existing — one column added)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | uuid | no | `gen_random_uuid()` | PK |
| `name` | text | no | — | UNIQUE on `LOWER(name)` |
| `category` | text | yes | null | Free-form tag; e.g., null for top-level systems |
| `sort_order` | integer | no | 0 | |
| `is_active` | boolean | no | true | Soft-delete flag (retired = false) |
| `needs_review` | boolean | no | false | |
| **`has_contingency`** | **boolean** | **no** | **false** | **NEW — true for AIDA-NG, CADAS-ATS, CADAS-IMS, IRTOS** |
| `created_at` | timestamptz | no | `now()` | |
| `updated_at` | timestamptz | no | `now()` | |

Indexes: unchanged (`idx_systems_name_lower`, `idx_systems_active`, `idx_systems_sort`).

### `asset_system_links` (existing — one column added, constraints updated)

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | uuid | no | `gen_random_uuid()` | PK |
| `asset_id` | uuid | no | — | FK → `assets.id`, ON DELETE CASCADE |
| `system_id` | uuid | no | — | FK → `systems.id` |
| `role` | text | no | — | CHECK IN ('primary','standby','client') |
| **`site`** | **text** | **no** | **'production'** | **NEW — CHECK IN ('production','contingency')** |
| `created_at` | timestamptz | no | `now()` | |

**Constraints (post-migration)**:
- `UNIQUE(asset_id, system_id, site)` — one role per (asset, system, site) per spec Q2.
- `UNIQUE(system_id, role, site) WHERE role IN ('primary','standby')` — one primary and one standby per system per site.

**Dropped constraints (pre-migration state)**:
- `UNIQUE(asset_id, system_id, role)` — replaced by the site-aware version above.
- `UNIQUE(system_id, role) WHERE role IN ('primary','standby')` — replaced.

### `assets` (existing — unchanged)

| Column | Type | Nullable | Notes |
|---|---|---|---|
| `id` | uuid | no | PK |
| `name` | text | no | UNIQUE |
| `type` | text | no | CHECK IN ('workstation','server','camera','router','switch','media_converter','power_adapter') |
| `location` | text | no | |
| `notes` | text | no (default '') | |
| `created_at`/`updated_at` | timestamptz | no | |

### `system_status_reports` (existing — no schema change)

The migration touches rows (repoints `system_id` from removed International Circuits to AIDA-NG) but does not modify columns. Both open and resolved reports are repointed; original `report_date`, description, and resolution text are preserved verbatim. See spec clarification Q1.

---

## Entity Relationships

```
assets  1 ──── *  asset_system_links  * ──── 1  systems
                       │
                       ├── role: primary | standby | client
                       └── site: production | contingency
```

- An **Asset** may link to **multiple Systems** (real workstations serve both AIDA-NG and CADAS-ATS).
- An **Asset** may link to the **same System at different sites** (e.g., `as1-prod` in production and `as1-cont` in contingency are distinct assets, but the pattern holds for workstations that physically serve both sites).
- A **System** links to **many Assets**, each with exactly one role per site.

---

## Validation Rules

| Rule | Source | Enforced by |
|---|---|---|
| One role per (asset, system, site) | Spec Q2 / FR-009c | DB unique index + backend 409 |
| One primary per (system, site) | FR-009a | DB partial unique index + backend 409 |
| One standby per (system, site) | FR-009b | DB partial unique index + backend 409 |
| `has_contingency=false` rejects site='contingency' links | FR-006 / FR-012 | Backend validator on POST/PATCH link |
| Site change conflicts are blocked with 409 + inline error | Spec Q5 / FR-010 | Backend 409 → frontend toast |
| `has_contingency` off while contingency links exist → confirm dialog moves+demotes | Spec Q4 / FR-012 | Frontend flow; backend transaction moves & demotes |

---

## Migration Data Transformations

### A. INDRA CCTV cameras (system rows → assets)

1. For each existing system row matching `name ~ 'INDRA CCTV - Camera \d+'`:
   - Insert `assets` row with `name='Camera N'`, `type='camera'`, `location='TBD (admin review)'`, `notes=''`.
   - Find/create single target system `name='INDRA CCTV'` (already seeded in spec 056).
   - Insert `asset_system_links` row linking new camera → INDRA CCTV, role=`client`, site=`production`.
2. Repoint any existing `asset_system_links` pointing to Camera-N systems → new camera assets (role becomes `client`, site becomes `production`; demote applied if duplicate).
3. Delete Camera-N system rows.

### B. International Circuits (system rows → removed)

1. Identify 6 International Circuit system rows by `name ~ 'International Circuits - '`.
2. **Asset links**: For each `asset_system_links` row pointing to an International Circuit system, repoint to AIDA-NG with `site='production'` preserving the original role. If the repoint would violate the uniqueness constraints, demote role to `client` (spec Q3).
3. **Status reports**: For each `system_status_reports` row pointing to an International Circuit system, repoint `system_id` to AIDA-NG; preserve all other fields (spec Q1).
4. Delete the 6 International Circuit system rows.

### C. `has_contingency` backfill

```
UPDATE systems SET has_contingency = true
  WHERE LOWER(name) IN ('aida-ng','cadas-ats','cadas-ims','irtos');
```

All other rows keep the default `false`.

---

## Idempotency

- Migration uses `IF NOT EXISTS` on column adds and `ON CONFLICT DO NOTHING` on seed inserts.
- Data transformations check for the presence of Camera-N and International Circuit rows before acting; a second run finds nothing to do.
- Unique-index creation uses `CREATE UNIQUE INDEX IF NOT EXISTS` after dropping the old indexes.

---

## Frontend Models

### Dart: `System` (`frontend/lib/models/system.dart`)

Add field:

```dart
final bool hasContingency;
```

JSON keys: `has_contingency`. Default false when missing.

### Dart: `AssetSystemLink` (`frontend/lib/models/asset.dart`)

Add field:

```dart
final String site;  // 'production' | 'contingency'
```

JSON keys: `site`. Default `'production'` when missing (for backward compat with any cached payloads).
