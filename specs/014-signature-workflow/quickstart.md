# Quickstart: Signature Workflow

**Branch**: `014-signature-workflow` | **Date**: 2026-04-03

## What This Feature Does

Replaces base64 signature storage with file-based storage, adds saved (pre-registered) signatures in Settings for technicians and admins, adds a bulk status endpoint to fix N+1 performance, adds activity logging for all signature events, and adds signature status badges to the work order list.

## Key Files to Modify

### Backend
- `backend/routers/signatures.py` — Modify existing endpoints (file storage instead of base64, add `use_saved` support, add activity logging), add bulk endpoint, add user signature endpoints
- `supabase/migrations/YYYYMMDD_signature_file_storage.sql` — ALTER `work_order_signatures` (add `signature_path`, make `signature_data` nullable), ALTER `users` (add `signature_path`)

### Frontend
- `frontend/lib/models/work_order_signature.dart` — Replace `signatureData` field with `signaturePath`
- `frontend/lib/services/signature_service.dart` — Add bulk fetch, user signature CRUD methods, update `saveSignature` to handle `use_saved` flag
- `frontend/lib/screens/settings_page.dart` — Add "My Signature" section with draw/upload/preview/remove
- `frontend/lib/screens/Work_Orders/add_work_order.dart` — Update `_buildSignatureSection` to show saved signature option, fix `_approveAndSign` bug (capture canvas before approval API call)
- `frontend/lib/screens/Work_Orders/work_order_home.dart` — Replace per-WO `fetchSignatures` loop with single `fetchBulkSignatureStatus` call
- `frontend/lib/widgets/signature_canvas.dart` — No structural changes needed (already exports base64 PNG)

## Implementation Order

1. **Database migration** — Add columns first (everything depends on schema)
2. **Backend: user signature endpoints** — POST/GET/DELETE `/api/users/{user_id}/signature` (independent of WO changes)
3. **Backend: modify WO signature endpoints** — File storage, `use_saved`, activity logging
4. **Backend: bulk endpoint** — GET `/api/signatures/bulk`
5. **Frontend: model update** — `signatureData` → `signaturePath`
6. **Frontend: service update** — New methods + modified payloads
7. **Frontend: Settings signature UI** — "My Signature" section
8. **Frontend: WO detail signature section** — Saved signature flow + `_approveAndSign` fix
9. **Frontend: WO list bulk status** — Replace N+1 with single call + badges

## Testing Strategy

- **Backend**: Test each endpoint with valid/invalid inputs, verify files created in `uploaded_files/`, verify activity log entries created
- **Frontend**: Manual testing of Settings draw/upload/remove, WO signing with saved signature, admin approve/reject flow, WO list badge rendering
- **Authorization**: Verify unassigned technician gets 403, reporter gets 403, non-admin cannot approve
