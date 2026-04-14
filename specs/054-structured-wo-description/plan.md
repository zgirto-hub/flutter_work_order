# Implementation Plan: Structured Work Order Description Fields

**Branch**: `054-structured-wo-description` | **Date**: 2026-04-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/054-structured-wo-description/spec.md`

## Summary

Replace the single free-text description field on the Add Work Order screen with 4 structured sub-fields (Asset Name with autocomplete from Asset Registry, Fault Description, Action Taken, Outcome dropdown) plus optional Notes. The backend stitches fields into a bracket-labeled description string before saving — no database schema changes. The detail view parses structured descriptions into visually separated labeled sub-fields with legacy fallback.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI, Supabase Python client (backend); http, supabase_flutter, Flutter Material (frontend)  
**Storage**: Supabase (PostgreSQL) — existing `work_orders` table, existing `assets` table; no schema changes  
**Testing**: Manual PWA testing (no automated test framework in project)  
**Target Platform**: Web (PWA) — Flutter web with canvaskit renderer  
**Project Type**: Full-stack web application (Flutter PWA + FastAPI backend)  
**Performance Goals**: Autocomplete suggestions within 1 second; form submission comparable to current workflow  
**Constraints**: Asset names list must be fetched once and cached client-side (Constitution V); no admin restriction on autocomplete endpoint  
**Scale/Scope**: ~tens to low hundreds of assets; Add Work Order screen only (Edit screen out of scope)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Backend endpoint changes + frontend form + detail view. No migration needed (no schema change). Documented why migration is excluded (existing description column reused). |
| II. Explicit Over Automatic | PASS | All 4 structured fields require explicit user input. Outcome is explicit dropdown, not inferred. |
| III. Role-Based Access Control | PASS | New `GET /asset-registry/asset-names` endpoint is read-only and accessible to all authenticated users. Does not expose sensitive asset details (notes, links). |
| IV. Server-First File Storage | N/A | No file uploads involved. |
| V. Client-Side Computation | PASS | Asset names fetched once, cached in widget state, filtered client-side. No per-keystroke API calls. |
| VI. Audit Everything | PASS | Work order creation already logged via `log_activity()` at line 772 of work_orders.py. No new auditable action introduced. |
| VII. Simplicity & YAGNI | PASS | Minimal changes: 2 backend files, 4 frontend files. No new abstractions, no configuration UI for outcomes. |

**Post-Phase 1 Re-check**: All gates remain PASS. The bracket-labeled format is the simplest parseable format (R-003). Backend stitching is per spec requirement, not over-engineering.

## Project Structure

### Documentation (this feature)

```text
specs/054-structured-wo-description/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 research findings
├── data-model.md        # Data model documentation
├── quickstart.md        # Implementation quickstart guide
├── contracts/
│   └── api-contracts.md # API contract definitions
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   ├── asset_registry.py   # + GET /asset-registry/asset-names endpoint
│   └── work_orders.py      # + structured fields on CreateWorkOrderBody + stitching logic

frontend/
├── lib/
│   ├── models/
│   │   └── work_order.dart         # No changes (description stays string)
│   ├── services/
│   │   ├── asset_service.dart      # + fetchAssetNames() method
│   │   └── work_order_service.dart # + send structured fields in addWorkOrder()
│   └── screens/
│       └── Work_Orders/
│           └── add_work_order.dart  # Replace description field + add detail view parsing
```

## Implementation Phases

### Phase 1: Backend — Asset Names Endpoint

**Files**: `backend/routers/asset_registry.py`

1. Add `GET /asset-registry/asset-names` endpoint:
   - No admin check — any authenticated request can call it
   - Query `assets` table, select only `name` column, order by name
   - Return `{"names": ["name1", "name2", ...]}`
   - Simple, lightweight, cacheable

### Phase 2: Backend — Structured Fields & Stitching

**Files**: `backend/routers/work_orders.py`

1. Extend `CreateWorkOrderBody` with 5 optional fields:
   - `asset_name: Optional[str] = None`
   - `fault_description: Optional[str] = None`
   - `action_taken: Optional[str] = None`
   - `outcome: Optional[str] = None`
   - `notes: Optional[str] = None`

2. Add `VALID_OUTCOMES` constant: `{"Resolved", "Pending Parts", "Escalated", "Monitoring"}`

3. In the create handler (before payload construction at line 742):
   - If all 4 structured fields are non-empty:
     - Validate `outcome` is in `VALID_OUTCOMES`
     - Stitch into description using bracket-labeled format
     - Set `payload["description"]` to stitched string
   - Else: use `body.description` as-is (backward compat)

### Phase 3: Frontend — Asset Service Extension

**Files**: `frontend/lib/services/asset_service.dart`

1. Add `fetchAssetNames()` method:
   - `GET /asset-registry/asset-names` (no user_email param needed)
   - Returns `List<String>` of asset names
   - Handles errors gracefully (returns empty list on failure)

### Phase 4: Frontend — Work Order Service Update

**Files**: `frontend/lib/services/work_order_service.dart`

1. Update `addWorkOrder()` to accept and send structured fields:
   - Add optional parameters or extend the request body to include `asset_name`, `fault_description`, `action_taken`, `outcome`, `notes`
   - Send as additional JSON fields alongside existing fields

### Phase 5: Frontend — Structured Form (Add Mode)

**Files**: `frontend/lib/screens/Work_Orders/add_work_order.dart`

1. Add new controllers and state:
   - `assetNameController`, `faultController`, `actionController`, `notesController`
   - `selectedOutcome` (String?)
   - `_assetNames` (List<String>) — cached from `fetchAssetNames()`
   - Corresponding FocusNodes

2. Load asset names in `initState()`:
   - Call `AssetService().fetchAssetNames()` asynchronously
   - Store in `_assetNames`; on error, leave empty (graceful fallback)

3. Replace description `TextFormField` (line 1743-1762) with:
   - **Asset Name**: `Autocomplete<String>` widget using `_assetNames` as options
     - Filter case-insensitively on typed text
     - Allow free-text entry (no forced selection)
     - Validator: required
   - **Fault Description**: `TextFormField` (maxLines: 3)
     - DictationButton suffix (moved from old description field)
     - Validator: required
   - **Action Taken**: `TextFormField` (maxLines: 2)
     - Validator: required
   - **Outcome**: `DropdownButtonFormField<String>`
     - Items: Resolved, Pending Parts, Escalated, Monitoring
     - Validator: required
   - **Notes**: `TextFormField` (maxLines: 2)
     - Optional, no validator
     - Hint text indicating Arabic or English

4. Update submit handler (line 1097-1115):
   - Pass structured field values to `WorkOrderService.addWorkOrder()`
   - Remove `descriptionController.text.trim()` usage for new WOs

5. Update AI Assist integration (line 636-637):
   - Route AI-generated description to `faultController`

6. Dispose new controllers and focus nodes in `dispose()`

### Phase 6: Frontend — Structured Detail View (View Mode)

**Files**: `frontend/lib/screens/Work_Orders/add_work_order.dart`

1. Add a description parser utility:
   - Detect structured format: `description.startsWith('[Asset] ')`
   - Parse bracket-labeled lines into a `Map<String, String>`
   - Return null if format doesn't match (legacy fallback)

2. In the view mode section (where `canEdit` is false):
   - If description is structured format:
     - Display a Card with labeled rows (Asset Name, Fault, Action, Outcome, Notes)
     - Each row: bold label + value text
     - Omit Notes row if not present
   - If description is legacy format:
     - Display existing read-only TextFormField (unchanged)

## Complexity Tracking

No constitution violations — table not needed.
