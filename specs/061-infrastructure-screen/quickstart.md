# Quickstart — Infrastructure Screen

A checklist for implementing, running, and verifying this feature end-to-end.

## Prerequisites

- Branch `061-infrastructure-screen` checked out (created by `/speckit.specify`).
- Backend running locally (`uvicorn backend.main:app --reload`) and connected to a Supabase instance.
- Flutter web dev environment (`flutter run -d chrome`).
- Current DB has the spec 056 systems seed (24 rows) so the migration has something to transform.

## 1. Apply the migration

```bash
# Copy the migration body into the Supabase SQL editor, or apply via CLI:
supabase db push
```

After migration, verify:

```sql
-- 7 real systems remain (no Camera-N, no International Circuits)
SELECT count(*) FROM systems;  -- expect 7

-- has_contingency set correctly
SELECT name, has_contingency FROM systems ORDER BY sort_order;

-- No orphan links
SELECT count(*) FROM asset_system_links al
  LEFT JOIN systems s ON s.id = al.system_id
  WHERE s.id IS NULL;   -- expect 0

-- All cameras are now assets
SELECT count(*) FROM assets WHERE type = 'camera';  -- expect 10
```

## 2. Restart backend

```bash
sudo systemctl restart document_server.service
```

New endpoints available:
- `GET /api/systems/{id}/detail`
- `POST /api/systems/{id}/disable-contingency`
- `PATCH /api/asset-registry/links/{link_id}`

## 3. Smoke test with curl

```bash
# Replace TOKEN with an admin JWT
export TOKEN="..."

# Overview still works
curl -H "Authorization: Bearer $TOKEN" http://localhost:8000/api/systems?active_only=true

# New detail endpoint (AIDA-NG has_contingency=true)
AIDA_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/api/systems?active_only=true \
  | jq -r '.systems[] | select(.name=="AIDA-NG") | .id')
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8000/api/systems/$AIDA_ID/detail" | jq .

# Expect JSON with system, production{primary,standby,client}, contingency{primary,standby,client}

# Billing System (no contingency)
BILL_ID=$(... same pattern, name=="Billing System")
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8000/api/systems/$BILL_ID/detail" | jq .
# Expect no `contingency` key at all
```

## 4. Run Flutter

```bash
cd frontend
flutter run -d chrome
```

Steps:
1. Log in as admin.
2. Settings → tap the single **Infrastructure** entry.
3. Confirm 7 system cards render.
4. Tap **AIDA-NG** → detail page shows Production and Contingency sections.
5. Tap **Billing System** → detail page shows only Production.
6. On INDRA CCTV detail → Production → Client group should list 10 cameras.

## 5. Exercise flows

- **Add asset to contingency**: on AIDA-NG detail, tap "+ Add" under Contingency → create a new server `test-server-1`, role=primary. Verify it appears and another "primary" attempt in contingency returns 409 inline.
- **Move asset between sites**: open an existing link → change site → confirm uniqueness block surfaces as inline error if target is occupied.
- **Toggle has_contingency off**: open AIDA-NG overflow menu → toggle off. Confirm dialog lists N contingency assets, offers move, and on confirm all links moved to production (any conflicts demoted to `client`).
- **Retire system**: overflow → Retire. Confirm the existing warning appears if there are unresolved status reports.

## 6. Verification commands (for spec SC checks)

- **SC-001** (7 real systems): `SELECT count(*) FROM systems;` → `7`.
- **SC-003** (no circuit-orphaned links): `SELECT count(*) FROM asset_system_links al JOIN systems s ON s.id=al.system_id WHERE s.name ~ 'International Circuits';` → `0`.
- **SC-004** (System Status still works): load the System Status dashboard in the app and confirm all 7 systems render without error.
- **SC-006** (no CRUD regressions): run through create/edit/retire/reactivate/mark-review from the Infrastructure screen and confirm each succeeds.

## 7. Cleanup (if rolling back during dev)

```sql
-- Restore original constraints
DROP INDEX IF EXISTS idx_asset_system_links_unique;
DROP INDEX IF EXISTS idx_asset_system_links_primary_standby;
CREATE UNIQUE INDEX idx_asset_system_links_unique
  ON asset_system_links(asset_id, system_id, role);
CREATE UNIQUE INDEX idx_asset_system_links_primary_standby
  ON asset_system_links(system_id, role) WHERE role IN ('primary','standby');

ALTER TABLE asset_system_links DROP COLUMN site;
ALTER TABLE systems DROP COLUMN has_contingency;
```
Note: rollback does **not** restore the Camera-N and International Circuit system rows. If you need the old seed back, re-run migration 20260414124125 after dropping the current data.
