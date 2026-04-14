# Quickstart: Structured Work Order Description Fields

**Branch**: `054-structured-wo-description` | **Date**: 2026-04-14

## What This Feature Does

Replaces the single free-text description field on the Add Work Order screen with 4 structured sub-fields (Asset Name with autocomplete, Fault Description, Action Taken, Outcome dropdown) plus an optional Notes field. The backend stitches them into a single description string. The detail view parses structured descriptions back into labeled sub-fields.

## Files to Modify

### Backend (2 files)
1. **`backend/routers/asset_registry.py`** — Add `GET /asset-registry/asset-names` endpoint (no admin check)
2. **`backend/routers/work_orders.py`** — Extend `CreateWorkOrderBody` with 5 new optional fields; add stitching logic before insert

### Frontend (4 files)
1. **`frontend/lib/services/asset_service.dart`** — Add `fetchAssetNames()` method calling new endpoint
2. **`frontend/lib/screens/Work_Orders/add_work_order.dart`** — Replace description TextFormField with 4 structured fields + Notes; add structured detail view display
3. **`frontend/lib/models/work_order.dart`** — No changes needed (description remains a single string)
4. **`frontend/lib/services/work_order_service.dart`** — Update `addWorkOrder()` to send structured fields

## Key Implementation Notes

- **Asset autocomplete**: Fetch all names once via `GET /asset-registry/asset-names`, cache in state, filter client-side using Flutter's `Autocomplete` widget
- **Outcome dropdown**: `DropdownButtonFormField` with 4 fixed values
- **Stitching**: Backend builds `[Asset] ...\n[Fault] ...\n[Action] ...\n[Outcome] ...\n[Notes] ...`
- **Detail view parsing**: When `canEdit` is false and description starts with `[Asset] `, render structured Card instead of read-only TextFormField
- **AI Assist**: Route AI description output to Fault Description field
- **DictationButton**: Attach to Fault Description field (primary dictation target)
- **Backward compat**: If structured fields are absent in request, use `description` as-is
