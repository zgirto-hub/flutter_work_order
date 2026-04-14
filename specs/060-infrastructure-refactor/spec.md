# Spec 060 — Infrastructure Screen (Unify Systems + Asset Registry)

**Status:** Draft
**Date:** 2026-04-14
**Type:** Refactor + new feature

## Summary

Replace the separate **Systems admin** and **Asset Registry** screens with a single **Infrastructure** screen organized system-first. Introduce the concept of **sites** (Production / Contingency) so that each system can show its physical assets grouped by deployment location. Clean up the `systems` seed data to reflect real-world topology: INDRA CCTV cameras become assets, International Circuits are removed as systems.

## Problem

Today, infrastructure management is split across two screens:
- **Systems** — a flat list of systems, used for System Status and tagging.
- **Asset Registry** — a flat list of assets, each with loose "system links" (role-only, no site awareness).

This doesn't match the actual topology. A system like AIDA-NG has **production** and **contingency** deployments, each with its own set of servers and client workstations. Users currently can't see "what runs AIDA-NG at contingency" without piecing it together from the flat asset list.

Additionally, the seed data has modeling errors:
- **INDRA CCTV Cameras 1-10** are modeled as 10 separate systems, but they are actually cameras (assets) attached to a single INDRA CCTV system.
- **International Circuits (6 entries)** are modeled as systems, but they are logical endpoints inside AIDA-NG, not infrastructure we manage.

## Goals

1. Single system-centric entry point for infrastructure (replaces both old screens).
2. Make site topology (Production / Contingency) explicit and visible.
3. Clean up seed data to match real-world mapping.
4. Keep existing backend endpoints where possible; add only what's needed.
5. Preserve System Status and other downstream consumers of `systems` table.

## Non-Goals

- Modeling International Circuits as a first-class concept. (Out of scope; may return as a separate feature.)
- Adding custom sites beyond Production/Contingency. (Deferred.)
- Changing how System Status reports are created.
- Touching work order → asset linking behavior.

## Final Data Model

### `systems` table — add one column

```sql
ALTER TABLE systems
  ADD COLUMN has_contingency boolean NOT NULL DEFAULT false;
```

### `asset_system_links` table — add one column

```sql
ALTER TABLE asset_system_links
  ADD COLUMN site text NOT NULL DEFAULT 'production'
    CHECK (site IN ('production', 'contingency'));
```

### Update unique constraints

Drop old constraints and recreate to include `site`:

```sql
DROP INDEX IF EXISTS idx_asset_system_links_unique;
CREATE UNIQUE INDEX idx_asset_system_links_unique
  ON asset_system_links(asset_id, system_id, role, site);

DROP INDEX IF EXISTS idx_asset_system_links_primary_standby;
CREATE UNIQUE INDEX idx_asset_system_links_primary_standby
  ON asset_system_links(system_id, role, site)
  WHERE role IN ('primary', 'standby');
```

### Data migration (one-time)

1. **Convert INDRA CCTV cameras to assets:**
   - For each "INDRA CCTV - Camera N" row in `systems`, create an asset: `name='Camera N'`, `type='camera'`, `location='TBD (admin review)'`.
   - Create `asset_system_links` row linking each new camera asset to the INDRA CCTV system with `role='client'`, `site='production'`.
   - Migrate any existing `asset_system_links` rows that point to the old Camera-N system rows: repoint them to the INDRA CCTV system.
   - Delete the Camera-N system rows.

2. **Remove International Circuits systems:**
   - For each `asset_system_links` row pointing to an International Circuit system, repoint it to AIDA-NG (same role/site).
   - Remove any `system_status_reports` rows for International Circuit systems (or repoint to AIDA-NG — to be confirmed; default: delete old stale reports).
   - Delete the 6 International Circuit system rows.

3. **Set `has_contingency` flag:**
   - `true` for AIDA-NG, CADAS-ATS, CADAS-IMS, IRTOS
   - `false` for Permissions, Billing System, INDRA CCTV

The migration is idempotent (uses `IF NOT EXISTS` / `ON CONFLICT`) and runs in a single SQL file.

## Backend

### New endpoint

- `GET /api/systems/{id}/detail` → returns system + its assets grouped by site and role.
  ```json
  {
    "system": { "id": "...", "name": "AIDA-NG", "has_contingency": true, ... },
    "production": {
      "primary": [{ "asset": {...}, "link_id": "..." }],
      "standby": [...],
      "client":  [...]
    },
    "contingency": { ... }
  }
  ```

### Modified endpoints

- `POST /api/asset-registry/assets/{id}/links` — accepts new `site` field (default 'production').
- `PATCH /api/systems/{id}` — accepts `has_contingency`.

### Unchanged

- System CRUD (`GET/POST/PATCH /api/systems`, retire/activate)
- Asset CRUD (`GET/POST/PUT/DELETE /api/asset-registry/assets`)
- System Status endpoints

## Frontend

### New screens

- **`infrastructure_screen.dart`** — replaces `systems_screen.dart` and `asset_registry_screen.dart` as the Settings entry point.
  - Top: search, filter chips (Show Retired, Needs Review, Category)
  - Body: scrollable list of **system cards** (name, status/category/review badges, asset count, site indicator)
  - FAB: add new system
  - Tap card → push `SystemDetailScreen`

- **`system_detail_screen.dart`** — detail view for one system.
  - Header: system name, asset count, status
  - Info bar: active/retired, category, sort order
  - **Production section** (always shown): assets grouped by role (primary / standby / client), "+ Add" action
  - **Contingency section** (shown only if `has_contingency=true`): same layout, "+ Add" action
  - Overflow menu (⋮): Edit System, Toggle Has Contingency, Retire/Activate, View Status Reports

- **`add_asset_to_system_sheet.dart`** — bottom sheet used from detail page's "+ Add":
  - Either pick an existing asset or create a new one inline
  - Pick role (primary / standby / client) — primary/standby disabled if already assigned for this site
  - Site is pre-filled from the section the user tapped "+ Add" on

### Removed screens

- `systems_screen.dart`, `asset_registry_screen.dart`, `asset_edit_screen.dart` — deleted.
- Their routes and navigation entries in `settings_page.dart` collapse into a single **Infrastructure** item.

### Kept screens / services

- `SystemsService` and `AssetService` stay; gain a couple of methods (`fetchSystemDetail`, `addLinkWithSite`).
- `System` model gains `hasContingency` field.
- `AssetSystemLink` model gains `site` field.

## UX Flows

### Browse
1. Settings → Infrastructure → sees list of 7 system cards
2. Tap "AIDA-NG" → sees Production (as1-prod primary, as2-prod standby, ws-01 client) and Contingency (as1-cont primary, as2-cont standby, ws-03 client)

### Add an asset to a site
1. From AIDA-NG detail, tap "+ Add" under Contingency
2. Bottom sheet: choose "Create new asset" or "Link existing"
3. Fill name/type/location (new) or select (existing); pick role
4. Save → asset appears in Contingency section

### Mark a system as having contingency
1. In detail page, tap ⋮ → "Toggle Has Contingency"
2. Contingency section appears (empty); add assets as needed

### Retire a system
1. ⋮ → Retire → confirmation dialog (warning about unresolved status reports)
2. System moves to "Show Retired" filter; asset links remain intact for historical reference

## Error Handling

- Creating a link with duplicate primary/standby for the same site → backend returns 409, UI shows inline error in sheet.
- Retiring a system with unresolved status reports → warning banner (existing behavior preserved).
- Deleting an asset with links → cascade (existing behavior).

## Testing

- Migration: unit test runs on a clean DB snapshot, verifies the 7 final systems, ~10 camera assets, and all old seed cleaned up.
- Backend: test `/systems/{id}/detail` returns correct grouping; test site-aware unique constraint rejects duplicate primary in same site but allows across sites.
- Frontend: smoke test the detail page renders Production only when `has_contingency=false`, both sections when true.

## Rollout

1. Ship migration first (backward-compatible — old endpoints still work with site defaulting to 'production').
2. Deploy backend changes.
3. Deploy frontend changes (new screens, remove old).
4. No data loss path — migration is reversible by re-running original 056 seed.

## Open Questions

None at design time. Any edge cases (e.g., existing asset with role=primary that conflicts with the new constraint on insert) will be caught in migration testing.
