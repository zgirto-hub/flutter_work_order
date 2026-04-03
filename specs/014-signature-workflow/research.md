# Research: Signature Workflow

**Branch**: `014-signature-workflow` | **Date**: 2026-04-03

## Findings

### 1. Existing Signature Implementation (Current State)

**Decision**: Modify the existing implementation rather than building from scratch.

**Rationale**: A partial signature feature already exists — backend router (`backend/routers/signatures.py`), frontend service (`frontend/lib/services/signature_service.dart`), model (`frontend/lib/models/work_order_signature.dart`), canvas widget (`frontend/lib/widgets/signature_canvas.dart`), and a DB migration (`supabase/migrations/20260403_work_order_signatures.sql`). The existing code already handles authorization (technician assignment check, admin-only approve/reject), notification dispatch, and the core sign → approve/reject flow. The changes are incremental: swap base64 for file storage, add bulk endpoint, add saved-signature endpoints, add activity logging, add Settings UI.

**Alternatives considered**:
- Full rewrite: Rejected — existing code is clean and well-structured; rewriting would be wasteful.

### 2. File Storage Pattern for Signatures

**Decision**: Use the existing `uploaded_files/` directory and `/files/<filename>` static serving, matching the attachment upload pattern in `work_orders.py`.

**Rationale**: The project already stores uploaded files via UUID-based filenames in `backend/uploaded_files/` served by FastAPI's `StaticFiles` at `/files/`. Constitution Principle IV (Server-First File Storage) mandates this approach. The signature canvas currently exports to base64 PNG via `controller.toPngBytes()` — the frontend will continue sending base64 in the request body, and the backend will decode and write to file (simpler than multipart for a single image).

**Alternatives considered**:
- Multipart form-data upload from frontend: Rejected — the canvas produces in-memory bytes, so sending base64 JSON is simpler and the backend can decode+save. Multipart is only needed for file picker uploads (saved signature from image file).
- Store in Supabase Storage: Rejected — violates Constitution Principle IV.

### 3. Schema Migration Strategy

**Decision**: Create an ALTER migration that: (a) adds `signature_path` column to `work_order_signatures`, (b) adds `signature_path` column to `users`, (c) keeps `signature_data` temporarily for backward compat (mark nullable). A separate follow-up can drop `signature_data`.

**Rationale**: The existing `signature_data TEXT NOT NULL` column has live data. Making it nullable and adding `signature_path` allows incremental migration. New code writes to `signature_path` only; old `signature_data` is ignored. Per clarification, migrating existing base64 data is out of scope.

**Alternatives considered**:
- Drop `signature_data` immediately: Rejected — would break any reads of existing signatures.
- Rename column: Rejected — riskier than adding a new column.

### 4. Bulk Signature Status Endpoint

**Decision**: Add `GET /api/signatures/bulk?work_order_ids=id1,id2,...` that returns a map of `{work_order_id: {has_technician: bool, has_admin: bool, technician_status: str}}`.

**Rationale**: The current frontend (`work_order_home.dart`) loops through closed WO IDs making individual `fetchSignatures()` calls — classic N+1. A single bulk endpoint with comma-separated IDs is simple, matches REST conventions, and the Supabase `.in_()` operator handles the query efficiently.

**Alternatives considered**:
- GraphQL batch query: Rejected — project doesn't use GraphQL.
- Embed signature status in work order list response: Rejected — would require modifying the existing WO list endpoint which is stable and used elsewhere.

### 5. Activity Logging Integration

**Decision**: Use existing `log_activity()` from `backend/utils/activity.py` with category `'work_order'` for WO signature events and `'admin'` for saved signature management.

**Rationale**: Constitution Principle VI (Audit Everything) requires activity logging. The existing fire-and-forget `log_activity()` function is the established pattern. Using `'work_order'` category keeps signature events grouped with their parent work order actions.

### 6. Admin Countersignature Status

**Decision**: Admin countersignature records are created with status `'approved'` immediately (auto-approved).

**Rationale**: Per clarification session — the admin IS the approver, so their own signature needs no further review. This simplifies querying "fully signed" status: both records have `status = 'approved'`.

### 7. Frontend Signature Submission Flow

**Decision**: For drawn signatures, continue sending base64 in JSON body (backend decodes to file). For uploaded image files in Settings, use multipart/form-data (matching existing file upload pattern).

**Rationale**: Two distinct flows: (a) canvas drawing produces in-memory PNG bytes → base64 JSON is simplest, (b) file picker produces a file reference → multipart is the established pattern. The backend handles both and saves to `uploaded_files/`.
