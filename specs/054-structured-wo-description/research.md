# Research: Structured Work Order Description Fields

**Branch**: `054-structured-wo-description` | **Date**: 2026-04-14

## R-001: Current Description Field Implementation

**Decision**: Replace the single `TextFormField` (maxLines: 3) at `add_work_order.dart:1743` with 4 structured fields + optional Notes field.

**Rationale**: The existing field is a plain `TextFormField` with `descriptionController`, a `DictationButton` suffix, and no validator. It feeds directly into `WorkOrder.description` which is sent as a single string to `POST /work-orders`. Minimal coupling — replacement is straightforward.

**Key findings**:
- Controller: `descriptionController` (line 86)
- FocusNode: `_descriptionFocusNode` (line 77)
- Submit flow: `descriptionController.text.trim()` → `WorkOrder(description: ...)` → `WorkOrderService.addWorkOrder()` → `POST /work-orders`
- The form doubles as both create and edit screen (via `widget.workOrder` null check)
- DictationButton integration exists for voice input (must be preserved on at least one field)
- AI assist integration fills description (line 636-637) — needs adaptation

**Alternatives considered**: Multi-step wizard form — rejected as over-engineered for 4 fields.

---

## R-002: Asset Registry Access for Non-Admin Users

**Decision**: Create a new lightweight endpoint `GET /asset-registry/asset-names` that returns only asset names without requiring admin access. Client fetches once, caches in memory, filters locally.

**Rationale**: The existing `GET /asset-registry/assets` endpoint (line 115 of `asset_registry.py`) calls `_admin_check(user_email)`, blocking technicians and reporters. The full endpoint also returns system links and full asset objects — unnecessary for autocomplete. A names-only endpoint is lighter and can be role-unrestricted.

**Key findings**:
- `AssetService.fetchAssets()` requires admin → throws 403 for non-admin
- Assets table has ~tens to low hundreds of records (per N+1 optimization memory note)
- Constitution V (Client-Side Computation) favors fetching all names once and filtering locally over per-keystroke API calls

**Alternatives considered**:
1. Per-keystroke search endpoint (`?q=gen`) — rejected per Constitution V; dataset is small enough to cache client-side
2. Reuse existing `fetchAssets()` and relax admin check — rejected to avoid exposing full asset details (notes, links) to all roles

---

## R-003: Stitched Description Format

**Decision**: Use bracket-labeled line format for the stitched description string:
```
[Asset] Generator #3
[Fault] Oil leak from main seal
[Action] Replaced seal and cleaned area
[Outcome] Resolved
[Notes] Optional notes here
```

**Rationale**: This format is:
1. Human-readable as plain text (important for existing views, exports, PDFs, extraction pipeline)
2. Easily parseable with a simple regex `\[(\w+)\]\s*(.*)` for the detail view
3. Backward-compatible — old descriptions without brackets display as-is (legacy fallback)
4. The `[Notes]` line is omitted when notes are empty (per FR-010)

**Alternatives considered**:
1. Pipe-delimited (`Asset: X | Fault: Y`) — harder to read for long values, no clear line breaks
2. JSON string — not human-readable, breaks existing PDF export and notification email templates
3. Key-value with newlines (`Asset: X\nFault: Y`) — ambiguous if values contain colons

---

## R-004: Backend Stitching vs Frontend Stitching

**Decision**: Backend stitches the 4 fields. Frontend sends individual fields; backend combines them into the description column.

**Rationale**: The spec explicitly states "The backend stitches the 4 fields into a single description string before saving." Backend stitching ensures:
1. Canonical format controlled in one place
2. If format changes in the future, only backend needs updating
3. Frontend doesn't need to know the stitching format

**Implementation**: Add optional fields `asset_name`, `fault_description`, `action_taken`, `outcome`, `notes` to `CreateWorkOrderBody`. If present, stitch into `description`. If absent (backward compat), use `description` as-is.

---

## R-005: Detail View Parsing

**Decision**: Add a utility function to parse structured descriptions back into sub-fields for display on the detail screen.

**Rationale**: The `add_work_order.dart` screen serves as both create and view/detail. When viewing a work order:
- If the description starts with `[Asset]`, parse it into labeled sub-fields displayed in a structured Card layout
- If the description does not match the structured format, display as plain text (legacy fallback)

**Key findings**:
- View mode is controlled by `canEdit` flag — description shows as read-only TextFormField
- Need to replace the read-only TextFormField with a structured Card when in view mode and description is structured format

---

## R-006: AI Assist and Dictation Integration

**Decision**: Preserve DictationButton on Fault Description field (most likely to be dictated). AI Assist fills individual fields instead of the single description.

**Rationale**: The AI Assist feature (spec 020/025) currently fills `descriptionController.text`. With structured fields, the AI response should map to individual fields. However, since AI Assist generates a free-form description, the simplest approach is to have AI Assist fill the Fault Description field only, with an option to distribute across fields in a future iteration.

**Alternatives considered**: Having AI parse into all 4 fields — deferred as over-engineering for this spec; AI integration can be enhanced separately.
