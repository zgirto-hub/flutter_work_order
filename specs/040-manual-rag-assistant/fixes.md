# Fix Manifest: 040-manual-rag-assistant

**For**: the implementing LLM doing the second pass.
**Source of findings**: code review dated 2026-04-12 (see the chat history for full reasoning).
**Prerequisites**: [spec.md](./spec.md), [plan.md](./plan.md), [contracts/manuals-api.md](./contracts/manuals-api.md), [data-model.md](./data-model.md), [research.md](./research.md), [tasks.md](./tasks.md).

---

## ⚠️ Read this before touching any fix

1. **This is a fix pass, not a rewrite.** The scaffolding (file layout, migration, models, nav wiring, dialog structure) is correct. Do not refactor things that work. Every change below is surgical.
2. **Follow the fix order exactly.** The order is chosen so each fix is verifiable in isolation and later fixes don't re-break earlier ones.
3. **After each fix: self-verify against the Verification section.** If verification fails, stop and diagnose — do not barrel forward.
4. **Never invent conventions.** When a fix asks you to match `files.py` or `work_orders.py`, open those files and copy the exact pattern — do not guess.
5. **Never modify `backend/version.json`.** Do not touch [CLAUDE.md](../../CLAUDE.md) by hand.
6. **Commit after each fix or logical group of ≤3 fixes.** Use conventional-commit style (e.g. `fix(manuals): match log_activity signature (F2)`).
7. **If any fix description conflicts with the spec/contracts, the spec wins.** Flag it and stop.

---

## Feasibility

**Can this be done?** Yes, with high confidence.

- Every CRITICAL fix is a small localized patch (5–40 lines), except F8 (vector search RPC) which is ~25 lines of SQL + ~10 lines of Python.
- No new dependencies are introduced except `http_parser` on the Flutter side (which is already a transitive dep of `http`, so no pubspec change needed).
- No design decisions are required — every fix has a single correct answer already pinned down in the spec, plan, or contracts.
- The fixes are independently verifiable. You don't need the whole feature working to verify F1, F2, F3, etc.

**Risk areas** (where you need to be careful, not where the design is shaky):
- **F8 (vector search)** requires re-applying the migration. Make sure you add to the *existing* migration file rather than creating a new one, since the feature's current migration has not shipped to any environment other than dev.
- **F3 (auth via Form field)** touches four routes and four Flutter service methods. Do all four on both sides in the same commit so neither side is half-migrated.
- **F13 (chunker rewrite)** is the biggest change but it's algorithmic, not architectural. The tests will tell you if it's wrong.

---

## Dependency graph

```text
F1 (storage path)           ─┐
F2 (audit signature)         │─── standalone, run first
F4 (router prefix)           │
F5 (MIME contentType)        │
F7 (created_at / updated_at) │
F9 (DELETE 204)              ─┘

F3 (auth via Form field) ── touches router + Flutter service; do in one commit

F6 (real file_name) ── depends on F3's signature refactor

F8 (vector search RPC) ── large but isolated; affects migration + rag_service.ask

F10 (upload txn rollback)   ─┐
F11 (stats RPC)              │─── bundle together; depend on F8 being in place
                              │   (they extend the same migration)
F12 (users!inner → users)    ─┘

F13 (chunker rewrite) ── isolated; can be done any time after F1
F14 (listManuals auth)  ── one-line, low priority
F15 (typed exceptions)  ── M-series cleanup; optional but recommended
F16 (M-series nits)     ── optional cleanup pass

F17 (Phase 6 — highlighting)  ── depends on F8 producing real sources
F18 (Phase 7 — tests + docs)  ── depends on everything above
```

**Recommended execution order**: F1 → F2 → F4 → F5 → F7 → F9 → F3 → F6 → F8 → F10 → F11 → F12 → F13 → F14 → F15 → F16 → F17 → F18.

---

## F1 — Fix storage base path (was C6)

**Severity**: 🔴 CRITICAL
**Files**: [backend/services/manual_storage_service.py](../../backend/services/manual_storage_service.py)
**Depends on**: none

### Problem

The current base path `Path("backend") / "uploaded_files" / "manuals"` is evaluated relative to the backend's working directory, which (per existing `files.py` convention) already *is* `backend/`. So the resolved path becomes `backend/backend/uploaded_files/manuals/`, which does not match the StaticFiles mount at `/files/<filename>` (constitution IV violation). Also, `BASE_DIR.mkdir(...)` runs at module import time, which is a filesystem side-effect.

### Exact fix

Replace the current file contents with:

```python
import logging
from pathlib import Path
from uuid import UUID


class StorageError(Exception):
    pass


# Match files.py convention: paths are relative to the backend working directory.
BASE_DIR = Path("uploaded_files") / "manuals"


def _ensure_base_dir() -> None:
    BASE_DIR.mkdir(parents=True, exist_ok=True)


def path_for(manual_id: UUID, file_extension: str) -> Path:
    return BASE_DIR / f"{manual_id}.{file_extension}"


def save(manual_id: UUID, file_bytes: bytes, file_extension: str) -> Path:
    _ensure_base_dir()
    file_path = path_for(manual_id, file_extension)
    try:
        with open(file_path, "wb") as f:
            f.write(file_bytes)
        return file_path
    except Exception as e:
        raise StorageError(f"Failed to save file {file_path}: {e}") from e


def delete(manual_id: UUID, file_extension: str) -> None:
    file_path = path_for(manual_id, file_extension)
    if not file_path.exists():
        return
    try:
        file_path.unlink()
    except Exception as e:
        logging.warning(f"Failed to delete file {file_path}: {e}")
```

### Verification

1. `grep -n "Path(\"backend\")" backend/services/manual_storage_service.py` → no matches.
2. Start the backend from its normal working directory (`cd backend && uvicorn main:app`). The process must not create a `backend/backend/` directory.
3. After a successful upload (later fixes), the file must land at `backend/uploaded_files/manuals/<uuid>.<ext>` — accessible at `http://localhost:8000/files/manuals/<uuid>.<ext>` (the existing StaticFiles mount).

---

## F2 — Fix `log_activity` signature mismatch (was C5)

**Severity**: 🔴 CRITICAL
**Files**: [backend/routers/manuals.py](../../backend/routers/manuals.py)
**Depends on**: none

### Problem

The manuals router calls `log_activity(user_id=..., category=..., action=..., details={...})`, but the real helper in [backend/utils/activity.py](../../backend/utils/activity.py) takes `(user_email: str, category: str, action: str, target_label="", target_id="", detail="")` — no `user_id`, no `details`. Every audit call raises `TypeError`, silently swallowed by the outer `try/except: pass`. Zero audit rows land. Constitution VI violation.

### Exact fix

Three places in [backend/routers/manuals.py](../../backend/routers/manuals.py).

**Upload success path** — replace the existing `log_activity(...)` block in `upload_manual` (around [L158-169](../../backend/routers/manuals.py#L158-L169)) with:

```python
try:
    log_activity(
        uploaded_by,  # user_email / positional
        "file",
        "uploaded_manual",
        target_label=title,
        target_id=result["manual_id"],
        detail=f"{result['chunk_count']} chunks, {file_size} bytes",
    )
except Exception:
    pass
```

(`uploaded_by` is the new form parameter introduced in F3. If you are applying F2 before F3, temporarily pass `current_user.get("id", "")` — but apply F3 immediately after.)

**Delete success path** — replace around [L200-207](../../backend/routers/manuals.py#L200-L207):

```python
try:
    log_activity(
        user_email,  # form param added in F3
        "file",
        "deleted_manual",
        target_label=deleted_title,  # NEW: looked up before the delete — see F3 + F6
        target_id=str(manual_uuid),
        detail="",
    )
except Exception:
    pass
```

**Ask success path** — replace around [L258-271](../../backend/routers/manuals.py#L258-L271):

```python
try:
    log_activity(
        user_email,  # form param
        "file",
        "asked_manual",
        target_label=question[:200],
        target_id=str(manual_id_filter) if manual_id_filter else "all",
        detail=f"grounded={result.get('grounded', False)}, sources={len(result.get('sources', []))}",
    )
except Exception:
    pass
```

### Verification

1. `grep -n "user_id=" backend/routers/manuals.py` → no matches.
2. `grep -n "details=" backend/routers/manuals.py` → no matches.
3. After a successful upload, `SELECT user_email, category, action, target_label, target_id, detail FROM user_activity_log WHERE action='uploaded_manual' ORDER BY id DESC LIMIT 1;` returns a row with the uploading user's email and the correct target fields.
4. Same for `asked_manual` and `deleted_manual`.

---

## F4 — Fix router double-prefix (was C2)

**Severity**: 🔴 CRITICAL
**Files**: [backend/routers/manuals.py](../../backend/routers/manuals.py)
**Depends on**: none

### Problem

`APIRouter(prefix="/api/manuals", tags=["manuals"])` combined with `app.include_router(manuals.router, prefix="/api")` in [backend/main.py:89](../../backend/main.py#L89) produces paths like `/api/api/manuals/upload`. Every other router in the repo uses `APIRouter()` (no prefix) and relies on `main.py` adding `/api`. Match that convention.

### Exact fix

**Step 1** — [backend/routers/manuals.py](../../backend/routers/manuals.py) line 12, change from:

```python
router = APIRouter(prefix="/api/manuals", tags=["manuals"])
```

to:

```python
router = APIRouter(tags=["manuals"])
```

**Step 2** — Update the four route decorators in the same file:

- `@router.get("/")` → `@router.get("/manuals/")`
- `@router.post("/upload")` → `@router.post("/manuals/upload")`
- `@router.delete("/{manual_id}")` → `@router.delete("/manuals/{manual_id}")`
- `@router.post("/ask")` → `@router.post("/manuals/ask")`

**Do NOT touch [backend/main.py](../../backend/main.py)** — the `include_router(..., prefix="/api")` line stays as-is.

### Verification

1. Start the backend.
2. `curl http://localhost:8000/api/manuals/` → 200 with `{"manuals": [], ...}` (pre-F3 — will return 422 or 200 anonymous).
3. `curl http://localhost:8000/openapi.json | python -c "import sys, json; paths = list(json.load(sys.stdin)['paths']); print('\n'.join(p for p in paths if 'manuals' in p))"` should list exactly:
   ```
   /api/manuals/
   /api/manuals/upload
   /api/manuals/{manual_id}
   /api/manuals/ask
   ```
   **No** `/api/api/manuals/...` entries.

---

## F5 — Flutter MultipartFile contentType (was C3)

**Severity**: 🔴 CRITICAL
**Files**: [frontend/lib/services/manual_assistant_service.dart](../../frontend/lib/services/manual_assistant_service.dart)
**Depends on**: none

### Problem

`http.MultipartFile.fromBytes` defaults to `application/octet-stream` when no `contentType` is supplied. The backend's MIME whitelist rejects that, so every upload returns 415. The `mimeType` argument currently threaded through the method is ignored.

### Exact fix

At the top of [manual_assistant_service.dart](../../frontend/lib/services/manual_assistant_service.dart), add:

```dart
import 'package:http_parser/http_parser.dart';
```

(`http_parser` is already a transitive dep of `http` — no `pubspec.yaml` change needed.)

In `uploadManual` around [L67-71](../../frontend/lib/services/manual_assistant_service.dart#L67-L71), replace the file-add block with:

```dart
request.files.add(http.MultipartFile.fromBytes(
  'file',
  fileBytes,
  filename: fileName,
  contentType: MediaType.parse(mimeType),
));
```

### Verification

1. `flutter analyze` on the frontend → no errors.
2. In a dev build, upload a small PDF via the UploadDialog. The backend logs should show `file.content_type = 'application/pdf'`, not `'application/octet-stream'`. Simple way: temporarily add `print(file.content_type)` to `upload_manual` in the router.
3. Upload should no longer return 415. (It may still fail for other reasons until F3/F6/F8 are applied — that's expected.)

---

## F7 — Real timestamps instead of `"now()"` string (was C9)

**Severity**: 🔴 CRITICAL
**Files**: [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py)
**Depends on**: none

### Problem

`"updated_at": "now()"` on [L138](../../backend/services/manual_rag_service.py#L138) and [L319](../../backend/services/manual_rag_service.py#L319) sends the literal string `"now()"` to Supabase, which will try to coerce it into a `TIMESTAMPTZ` column and fail (or in some driver versions store the literal string). Also `"created_at": "now()"` in the return value on [L159](../../backend/services/manual_rag_service.py#L159) is parsed by Flutter's `DateTime.parse` and throws `FormatException`, which the UploadDialog's generic `catch` surfaces as "An unexpected error occurred" — *after* the upload has actually succeeded.

### Exact fix

At the top of [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py), add:

```python
from datetime import datetime, timezone
```

Add a helper near the top (after imports, before `PROMPT_TEMPLATE`):

```python
def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()
```

Then **three replacements** in this file:

1. In `upload_manual`, around [L138](../../backend/services/manual_rag_service.py#L138), replace `"updated_at": "now()"` with `"updated_at": _now_iso()`.
2. In `upload_manual`, around [L159](../../backend/services/manual_rag_service.py#L159), replace `"created_at": "now()"` with `"created_at": _now_iso()`.
3. In `delete_manual`, around [L319](../../backend/services/manual_rag_service.py#L319), replace `"updated_at": "now()"` with `"updated_at": _now_iso()`.

**Note**: After F11 (stats RPC), the two `updated_at` assignments go away — the RPC sets `now()` inside the SQL where it's valid. For now this is a bridging fix.

### Verification

1. `grep -n '"now()"' backend/services/manual_rag_service.py` → no matches.
2. After upload, the returned JSON's `created_at` is a valid ISO-8601 string (e.g. `2026-04-12T10:15:32.123456+00:00`).
3. `DateTime.parse(createdAtString)` in Dart succeeds.

---

## F9 — DELETE returns 204 (was C7)

**Severity**: 🔴 CRITICAL
**Files**: [backend/routers/manuals.py](../../backend/routers/manuals.py)
**Depends on**: F4 (router prefix) — so the route exists at the right path

### Problem

The delete handler ends with `return None`, which FastAPI renders as HTTP 200 with body `null`. The Flutter `deleteManual` service checks for 204 and treats 200 as failure — so successful deletes surface as "Failed to delete manual".

### Exact fix

In [backend/routers/manuals.py](../../backend/routers/manuals.py), change the decorator on `delete_manual`:

```python
@router.delete("/manuals/{manual_id}", status_code=204)
async def delete_manual(
    manual_id: str,
    user_email: str = Query(...),  # from F3
):
    ...
    # At the end:
    return Response(status_code=204)
```

Add `from fastapi import Response` to the imports if not already there.

### Verification

1. `curl -i -X DELETE "http://localhost:8000/api/manuals/<valid-uuid>?user_email=test@example.com"` → `HTTP/1.1 204 No Content`, empty body.
2. In the Flutter UI, deleting a manual now shows the "Manual deleted" SnackBar and the row disappears.

---

## F3 — Authentication via Form/query parameters (was C4)

**Severity**: 🔴 CRITICAL
**Files**:
- [backend/routers/manuals.py](../../backend/routers/manuals.py) — all 4 endpoints
- [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py) — signatures
- [frontend/lib/services/manual_assistant_service.dart](../../frontend/lib/services/manual_assistant_service.dart) — all 4 methods
- [frontend/lib/screens/manual_assistant/manuals_tab.dart](../../frontend/lib/screens/manual_assistant/manuals_tab.dart)
- [frontend/lib/screens/manual_assistant/chat_tab.dart](../../frontend/lib/screens/manual_assistant/chat_tab.dart)
- [frontend/lib/screens/manual_assistant/widgets/upload_dialog.dart](../../frontend/lib/screens/manual_assistant/widgets/upload_dialog.dart)

**Depends on**: F4 (router prefix fixed) so the routes exist at the right path.

### Problem

The router uses a hard-coded `get_current_user` that returns `{"id": "anonymous"}`. Consequences:
- `manuals.uploaded_by` is typed `UUID REFERENCES users(id)` — inserting the string `"anonymous"` will error.
- Audit logs have no real user attribution.
- The repo's actual convention (verified in `files.py`, `work_orders.py`, `document_registry.py`, `signatures.py`) is that the client passes the user's email as a Form field (`uploaded_by` or `user_email`). Backend uses the service-role key; no JWT dependency.

### Exact fix

**Backend side** — in [backend/routers/manuals.py](../../backend/routers/manuals.py):

1. **Delete** the `get_current_user` placeholder function and the `security = HTTPBearer(...)` line.
2. **Delete** every `current_user: dict = Depends(get_current_user)` parameter from the four endpoints.
3. **Add** form/query parameters:

   - `POST /manuals/upload`:
     ```python
     @router.post("/manuals/upload")
     async def upload_manual(
         file: UploadFile = File(...),
         title: str = Form(...),
         uploaded_by: str = Form(...),   # NEW — user's email per repo convention
     ):
     ```
     And pass `uploaded_by` through to `manual_rag_service.upload_manual(...)`.

   - `GET /manuals/`:
     ```python
     @router.get("/manuals/")
     async def list_manuals():   # no auth — read-only list is public to any signed-in user via the frontend
         ...
     ```
     (The existing `files.py` patterns do the same for read endpoints.)

   - `DELETE /manuals/{manual_id}`:
     ```python
     @router.delete("/manuals/{manual_id}", status_code=204)
     async def delete_manual(
         manual_id: str,
         user_email: str = Query(...),   # NEW — audit attribution only
     ):
     ```
     (Query param because DELETE bodies are awkward; matches how other delete endpoints in the repo do audit.)

   - `POST /manuals/ask` — add `user_email` to the Pydantic `AskRequest`:
     ```python
     class AskRequest(BaseModel):
         question: str
         manual_id: Optional[str] = None
         user_email: str   # NEW — required
     ```

4. **Replace** every `current_user.get("id", "")` in the audit log calls (F2) with the new form/query parameter.

**Service side** — in [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py):

The `upload_manual` signature already takes `uploaded_by: str` — good. But look up the user's `id` (UUID) from `uploaded_by` (email) before the insert. The `manuals.uploaded_by` column is a UUID FK to `users(id)`, NOT an email column:

```python
# Step 4.5 (new, between "Allocate manual_id" and "Compute projected_bytes"):
user_row = (
    supabase.table("users")
    .select("id")
    .eq("email", uploaded_by)
    .limit(1)
    .execute()
)
user_uuid = user_row.data[0]["id"] if user_row.data else None  # SET NULL if not found
```

Then in the insert dict, change `"uploaded_by": uploaded_by` to `"uploaded_by": user_uuid`.

`ask` and `delete_manual` do not need the user id in the DB — they only need it for audit logging, which is done in the router.

**Frontend side** — in [frontend/lib/services/manual_assistant_service.dart](../../frontend/lib/services/manual_assistant_service.dart):

1. Add a `userEmail` parameter to every method:
   ```dart
   Future<Map<String, dynamic>> listManuals() async { ... }           // no change — list is open
   Future<Manual> uploadManual(
     String title, Uint8List fileBytes, String fileName, String mimeType,
     {required String userEmail}) async { ... }
   Future<ManualQaAnswer> askQuestion(
     String question, String? manualIdFilter,
     {required String userEmail}) async { ... }
   Future<void> deleteManual(String manualId, {required String userEmail}) async { ... }
   ```

2. In `uploadManual`, add the form field:
   ```dart
   request.fields['title'] = title;
   request.fields['uploaded_by'] = userEmail;  // NEW
   ```

3. In `askQuestion`, include it in the JSON body:
   ```dart
   final body = <String, dynamic>{
     'question': question,
     'user_email': userEmail,
   };
   if (manualIdFilter != null) body['manual_id'] = manualIdFilter;
   ```

4. In `deleteManual`, append it as a query param:
   ```dart
   final uri = Uri.parse(
     '${AppConfig.baseUrl}/api/manuals/$manualId?user_email=${Uri.encodeComponent(userEmail)}',
   );
   final res = await http.delete(uri, headers: headers);
   ```

5. **Remove** the `Authorization: Bearer` header logic from all three mutating methods — it was never read by the backend and confuses the convention. Keep `Content-Type` headers.

**Call sites** — the three widgets that invoke the service need to pass `userEmail`:

- [upload_dialog.dart](../../frontend/lib/screens/manual_assistant/widgets/upload_dialog.dart): get the email from `Supabase.instance.client.auth.currentUser?.email` and pass as `userEmail:`. If the user is not logged in, refuse to upload with an error message (shouldn't happen — screen is behind auth).
- [manuals_tab.dart](../../frontend/lib/screens/manual_assistant/manuals_tab.dart) `_showDeleteDialog`: same.
- [chat_tab.dart](../../frontend/lib/screens/manual_assistant/chat_tab.dart) `_sendQuestion`: same.

The cleanest place to resolve the email is a helper at the top of each widget:

```dart
String _currentUserEmail() {
  final email = Supabase.instance.client.auth.currentUser?.email;
  if (email == null || email.isEmpty) {
    throw Exception('Not signed in');
  }
  return email;
}
```

### Verification

1. Upload a manual as a signed-in user. `SELECT uploaded_by FROM manuals ORDER BY created_at DESC LIMIT 1;` returns the user's UUID (not `anonymous`, not NULL unless the user was deleted).
2. `SELECT user_email FROM user_activity_log WHERE action='uploaded_manual' ORDER BY id DESC LIMIT 1;` returns the correct email.
3. Delete, ask, list all succeed with the same attribution.
4. `grep -n "get_current_user\|anonymous" backend/routers/manuals.py` → no matches.

---

## F6 — Preserve the real uploaded file name (was C8)

**Severity**: 🔴 CRITICAL
**Files**:
- [backend/routers/manuals.py](../../backend/routers/manuals.py)
- [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py)

**Depends on**: F3 (router signature is already being modified).

### Problem

The service synthesizes `"file_name": f"{title}.{file_extension}"` ([L104](../../backend/services/manual_rag_service.py#L104)) instead of using the real uploaded filename. FR-007 says the original filename must be preserved for display.

### Exact fix

**Router** — in `upload_manual` (after F3 is applied), capture the real filename from `UploadFile` and pass it into the service:

```python
@router.post("/manuals/upload")
async def upload_manual(
    file: UploadFile = File(...),
    title: str = Form(...),
    uploaded_by: str = Form(...),
):
    content_type = file.content_type
    file_extension = ALLOWED_MIME_TYPES.get(content_type)
    if not file_extension:
        raise HTTPException(status_code=415, detail={"error": "unsupported_media_type", "message": "Only PDF, DOCX, TXT, and MD files are supported."})

    file_bytes = await file.read()
    file_size = len(file_bytes)
    file_name = file.filename or f"untitled.{file_extension}"  # NEW

    # ... size / title validation as before ...

    try:
        result = await manual_rag_service.upload_manual(
            title=title.strip(),
            file_bytes=file_bytes,
            file_name=file_name,            # NEW
            file_extension=file_extension,
            file_size_bytes=file_size,
            uploaded_by=uploaded_by,
        )
    except ...:
        ...
```

**Service** — in [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py), update `upload_manual` signature:

```python
async def upload_manual(
    title: str,
    file_bytes: bytes,
    file_name: str,              # NEW parameter, before file_extension
    file_extension: str,
    file_size_bytes: int,
    uploaded_by: str,
) -> dict:
    ...
```

Then in the manual_record dict on [L101-109](../../backend/services/manual_rag_service.py#L101-L109):

```python
manual_record = {
    "id": str(manual_id),
    "title": title,
    "file_name": file_name,       # ← use the real filename
    "file_extension": file_extension,
    "file_size_bytes": file_size_bytes,
    "uploaded_by": user_uuid,     # resolved from email in F3
    "chunk_count": len(chunks),
}
```

Also update the return dict so the Flutter UI shows the real name:

```python
return {
    "manual_id": str(manual_id),
    "title": title,
    "file_name": file_name,       # ← not f"{title}.{ext}"
    "file_extension": file_extension,
    "file_size_bytes": file_size_bytes,
    "chunk_count": len(chunks),
    "created_at": _now_iso(),     # from F7
}
```

### Verification

1. Upload a file named `acme_d11_hyd_manual.pdf` with title `Caterpillar D11 Hydraulics`. `SELECT title, file_name FROM manuals ORDER BY created_at DESC LIMIT 1;` returns `Caterpillar D11 Hydraulics | acme_d11_hyd_manual.pdf`.
2. The Manuals tab subtitle shows `acme_d11_hyd_manual.pdf · ...`.

---

## F8 — Vector search via Supabase RPC (was C1)

**Severity**: 🔴 CRITICAL
**Files**:
- [supabase/migrations/20260411000000_create_manuals.sql](../../supabase/migrations/20260411000000_create_manuals.sql)
- [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py)

**Depends on**: none (but the migration needs to be re-run — see verification).

### Problem

`ask` currently ignores the question embedding and returns 5 arbitrary chunks. This breaks the entire RAG loop. [research.md §1](./research.md) and [contracts/manuals-api.md §4](./contracts/manuals-api.md) both call for a cosine-distance query, which cannot be expressed through the Supabase PostgREST client — it has to be a SQL function called via `.rpc(...)`.

### Exact fix

**Step 1** — Append to [supabase/migrations/20260411000000_create_manuals.sql](../../supabase/migrations/20260411000000_create_manuals.sql) (at the bottom, before any existing `INSERT` seed):

```sql
-- Vector search RPC for manual_chunks.
-- Returns top-k nearest chunks by cosine distance, optionally scoped to a single manual.
CREATE OR REPLACE FUNCTION search_manual_chunks(
    q_embedding vector(768),
    manual_id_filter uuid DEFAULT NULL,
    match_count int DEFAULT 5
)
RETURNS TABLE (
    id uuid,
    manual_id uuid,
    chunk_index int,
    source_page int,
    content text,
    manual_title text,
    distance float
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        mc.id,
        mc.manual_id,
        mc.chunk_index,
        mc.source_page,
        mc.content,
        m.title AS manual_title,
        (mc.embedding <=> q_embedding) AS distance
    FROM manual_chunks mc
    JOIN manuals m ON m.id = mc.manual_id
    WHERE manual_id_filter IS NULL OR mc.manual_id = manual_id_filter
    ORDER BY mc.embedding <=> q_embedding
    LIMIT match_count;
$$;
```

**Step 2** — Re-apply the migration against the dev Supabase project. Since this feature's migration has not shipped to production yet, the simplest correct path is:

```bash
# If you have migrations set up to apply incrementally:
supabase db push

# If not, copy the appended function block and run it directly in the Supabase SQL editor.
```

**Step 3** — Rewrite the retrieval block in [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py) `ask` function, replacing everything from the `# Retrieve top 5 chunks` comment through the end of `chunks_data = ...` (roughly [L187-204](../../backend/services/manual_rag_service.py#L187-L204)) with:

```python
# Retrieve top-5 nearest chunks via the pgvector RPC.
rpc_response = supabase.rpc(
    "search_manual_chunks",
    {
        "q_embedding": question_embedding,
        "manual_id_filter": str(manual_id_filter) if manual_id_filter else None,
        "match_count": 5,
    },
).execute()
chunks_data = rpc_response.data or []
```

**Step 4** — Simplify the source-building loop ([L214-232](../../backend/services/manual_rag_service.py#L214-L232)) since `manual_title` now comes directly from the RPC:

```python
retrieved_chunks = ""
sources = []
for i, chunk in enumerate(chunks_data):
    manual_title = chunk.get("manual_title", "Unknown")
    source_page = chunk.get("source_page")
    content = chunk.get("content", "")
    retrieved_chunks += (
        f"[Source {i + 1}: {manual_title}, page {source_page or '—'}]\n{content}\n---\n"
    )
    sources.append({
        "manual_id": chunk.get("manual_id"),
        "manual_title": manual_title,
        "chunk_index": chunk.get("chunk_index", 0),
        "source_page": source_page,
        "content_preview": content[:500],
    })
```

### Verification

1. `grep -n "Full vector search" backend/services/manual_rag_service.py` → no matches (the old TODO comment must be gone).
2. Seed at least one manual via the upload flow. In the Supabase SQL editor:
   ```sql
   SELECT manual_title, source_page, distance
   FROM search_manual_chunks(
     (SELECT embedding FROM manual_chunks LIMIT 1),
     NULL,
     5
   );
   ```
   Should return up to 5 rows with ascending `distance`.
3. Ask a question via the Chat tab whose answer is in the uploaded manual — the answer should now reflect the manual's content and `sources[0].manual_title` should NOT be `"Unknown"`.
4. Ask a question whose answer is NOT in any manual — the sentinel `"This information is not in the available manuals."` is returned with `sources: []`.

---

## F10 — Upload transaction rollback (was H1)

**Severity**: 🟠 HIGH (FR-019b violation)
**Files**:
- [supabase/migrations/20260411000000_create_manuals.sql](../../supabase/migrations/20260411000000_create_manuals.sql)
- [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py)

**Depends on**: F8 (RPC pattern is established).

### Problem

The upload's three separate REST writes (`manuals` insert → `manual_chunks` insert → `manual_corpus_stats` update) leave orphan rows if any step after the first fails. The compensating `delete_file` on exception only cleans the disk file, not the orphan `manuals` row. FR-019b requires full rollback.

### Exact fix

**Step 1** — Add a second RPC to the same migration file:

```sql
-- Atomic upload of a manual and its chunks, plus stats update.
-- Does everything in one SQL transaction so partial failures roll back cleanly.
CREATE OR REPLACE FUNCTION create_manual_with_chunks(
    p_id uuid,
    p_title text,
    p_file_name text,
    p_file_extension text,
    p_file_size_bytes bigint,
    p_uploaded_by uuid,
    p_chunks jsonb,              -- array of {chunk_index, source_page, content, embedding}
    p_projected_bytes bigint
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_chunk jsonb;
BEGIN
    INSERT INTO manuals (id, title, file_name, file_extension, file_size_bytes, uploaded_by, chunk_count)
    VALUES (p_id, p_title, p_file_name, p_file_extension, p_file_size_bytes, p_uploaded_by, jsonb_array_length(p_chunks));

    FOR v_chunk IN SELECT * FROM jsonb_array_elements(p_chunks) LOOP
        INSERT INTO manual_chunks (manual_id, chunk_index, source_page, content, embedding)
        VALUES (
            p_id,
            (v_chunk->>'chunk_index')::int,
            NULLIF(v_chunk->>'source_page', '')::int,
            v_chunk->>'content',
            (v_chunk->>'embedding')::vector(768)
        );
    END LOOP;

    UPDATE manual_corpus_stats
    SET total_bytes = total_bytes + p_projected_bytes,
        manual_count = manual_count + 1,
        updated_at = now()
    WHERE id = 1;

    RETURN p_id;
END;
$$;
```

**Step 2** — Replace the step-8 DB-insert block in `manual_rag_service.upload_manual` ([L98-140](../../backend/services/manual_rag_service.py#L98-L140)) with a single RPC call:

```python
# Step 8: Atomic DB write via RPC (rollback on any error)
try:
    chunk_payload = [
        {
            "chunk_index": i,
            "source_page": chunks[i].source_page,
            "content": chunks[i].content,
            "embedding": embeddings[i],
        }
        for i in range(len(chunks))
    ]
    supabase.rpc(
        "create_manual_with_chunks",
        {
            "p_id": str(manual_id),
            "p_title": title,
            "p_file_name": file_name,
            "p_file_extension": file_extension,
            "p_file_size_bytes": file_size_bytes,
            "p_uploaded_by": user_uuid,
            "p_chunks": chunk_payload,
            "p_projected_bytes": projected_bytes,
        },
    ).execute()
except Exception as e:
    # Compensating cleanup: the file is on disk but the DB transaction failed.
    try:
        delete_file(manual_id, file_extension)
    except Exception:
        pass
    raise ManualUploadError("upload_failed: database transaction failed") from e
```

The nested sub-query for `manual_count` and the literal `"now()"` string are gone — both lived in the old step 8 block.

### Verification

1. In a dev database, deliberately break the RPC call by passing a malformed embedding (wrong length). After the error:
   - `SELECT count(*) FROM manuals WHERE title='<test>';` → `0`.
   - `SELECT count(*) FROM manual_chunks;` → unchanged.
   - `backend/uploaded_files/manuals/` → no new file from this upload.
2. Normal upload still works end-to-end.
3. `grep -n "insert(chunk_records)" backend/services/manual_rag_service.py` → no matches (the old batch insert is replaced).

---

## F11 — Stats RPC for delete path (was H2)

**Severity**: 🟠 HIGH
**Files**:
- [supabase/migrations/20260411000000_create_manuals.sql](../../supabase/migrations/20260411000000_create_manuals.sql)
- [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py)

**Depends on**: F8, F10 (RPC pattern and additional migration content).

### Problem

- `delete_manual` uses a hardcoded `chunk_count * 3500` to decrement the stats counter — drifts from reality.
- Read-modify-write on the stats row races with concurrent uploads.
- `"updated_at": "now()"` literal string (same bug class as F7).

### Exact fix

**Step 1** — Add to the migration file:

```sql
-- Accurate, atomic delete of a manual (plus chunks via CASCADE) and stats decrement.
CREATE OR REPLACE FUNCTION delete_manual_with_stats(p_manual_id uuid)
RETURNS TABLE (file_extension text, title text)
LANGUAGE plpgsql
AS $$
DECLARE
    v_bytes bigint := 0;
    v_chunk_count int := 0;
    v_ext text;
    v_title text;
BEGIN
    SELECT m.file_extension, m.title INTO v_ext, v_title
    FROM manuals m
    WHERE m.id = p_manual_id;

    IF v_ext IS NULL THEN
        RETURN;  -- caller handles "not found"
    END IF;

    -- Compute the exact bytes to subtract using the same formula upload uses.
    SELECT
        COALESCE(SUM(octet_length(content)), 0) + COUNT(*) * 3072 + COUNT(*) * 200 + 500,
        COUNT(*)
    INTO v_bytes, v_chunk_count
    FROM manual_chunks
    WHERE manual_id = p_manual_id;

    DELETE FROM manuals WHERE id = p_manual_id;  -- CASCADE removes manual_chunks

    UPDATE manual_corpus_stats
    SET total_bytes = GREATEST(0, total_bytes - v_bytes),
        manual_count = GREATEST(0, manual_count - 1),
        updated_at = now()
    WHERE id = 1;

    RETURN QUERY SELECT v_ext, v_title;
END;
$$;
```

**Step 2** — Replace `delete_manual` in [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py) with:

```python
async def delete_manual(manual_id: UUID) -> dict:
    """Returns {'file_extension': str, 'title': str} on success. Raises ManualNotFoundError if missing."""
    response = supabase.rpc(
        "delete_manual_with_stats",
        {"p_manual_id": str(manual_id)},
    ).execute()

    if not response.data:
        raise ManualNotFoundError(f"Manual {manual_id} not found")

    row = response.data[0]
    file_extension = row["file_extension"]
    title = row["title"]

    # Disk cleanup (tolerates missing file)
    try:
        delete_file(manual_id, file_extension)
    except Exception:
        pass

    return {"file_extension": file_extension, "title": title}
```

Also add a new typed exception near the top of the file:

```python
class ManualNotFoundError(Exception):
    pass
```

And update the router's delete handler to catch `ManualNotFoundError` specifically (currently it does string-matching — this is cleaner):

```python
try:
    deleted = await manual_rag_service.delete_manual(manual_uuid)
except manual_rag_service.ManualNotFoundError:
    raise HTTPException(status_code=404, detail={"error": "manual_not_found"})
except Exception:
    raise HTTPException(status_code=500, detail={"error": "delete_failed", "message": "Unable to delete the manual."})

deleted_title = deleted["title"]  # for audit logging (F2)
```

### Verification

1. Upload a manual. Note `total_bytes` before and after: `SELECT total_bytes FROM manual_corpus_stats;`.
2. Delete the same manual. Observe `total_bytes` returns to the original value (within a few hundred bytes — the seed row).
3. Delete an unknown UUID → 404.
4. Successful delete → 204.
5. `grep -n '"now()"' backend/services/manual_rag_service.py` → no matches.

---

## F12 — `users` left join in list endpoint (was H3)

**Severity**: 🟠 HIGH
**Files**: [backend/routers/manuals.py](../../backend/routers/manuals.py)
**Depends on**: F4.

### Problem

`.select("*, users!inner(full_name)")` drops manuals whose uploader was deleted (because `uploaded_by` is `NULL` under `ON DELETE SET NULL`). `work_orders.py:1120` uses the correct form `users(full_name)` — left join.

### Exact fix

In [backend/routers/manuals.py](../../backend/routers/manuals.py) `list_manuals`, change:

```python
.select("*, users!inner(full_name)")
```

to:

```python
.select("*, users(full_name)")
```

Also adjust the row mapping to tolerate `row["users"] is None`:

```python
"uploaded_by_name": (row.get("users") or {}).get("full_name") if row.get("users") else None,
```

### Verification

1. Upload a manual. Delete the uploader's row from `users` (dev environment only — not production). The manual should still appear in the Manuals tab with `uploaded_by_name: null` (UI shows "Unknown").
2. Restore the user (rollback the dev dataset) and confirm `uploaded_by_name` re-populates after a refresh.

---

## F13 — Chunker rewrite (was H4)

**Severity**: 🟠 HIGH
**Files**: [backend/services/manual_chunker.py](../../backend/services/manual_chunker.py)
**Depends on**: none.

### Problem

The current chunker is a word-stream across all paragraphs, not paragraph-first. `source_page` tracking is wrong when overlap words carry into a chunk whose "first paragraph" is on a different page. Pass-2 fallback is dead code.

### Exact fix

Replace [backend/services/manual_chunker.py](../../backend/services/manual_chunker.py) with:

```python
from dataclasses import dataclass
from typing import List, Tuple, Optional


@dataclass
class Chunk:
    chunk_index: int
    source_page: Optional[int]
    content: str


def chunk_paragraphs(
    paragraphs: List[Tuple[Optional[int], str]],
    max_words: int = 500,
    overlap_words: int = 50,
) -> List[Chunk]:
    """Paragraph-first chunker per research.md §2.

    Pass 1: greedily pack whole paragraphs until the next one would exceed max_words.
    Pass 2 (per-paragraph fallback): if a SINGLE paragraph exceeds max_words, slide a
    word-window over that paragraph.

    source_page is the page of the first paragraph that contributed non-overlap words
    to the chunk.
    """
    if not paragraphs:
        return []

    chunks: List[Chunk] = []
    chunk_index = 0

    # Normalize: expand oversized paragraphs into smaller "virtual paragraphs" via Pass 2.
    normalized: List[Tuple[Optional[int], List[str]]] = []
    for page, text in paragraphs:
        words = text.split()
        if not words:
            continue
        if len(words) <= max_words:
            normalized.append((page, words))
        else:
            # Pass 2: sliding window with overlap, each window inherits the paragraph's page
            step = max_words - overlap_words
            if step <= 0:
                step = max_words
            for start in range(0, len(words), step):
                window = words[start : start + max_words]
                if window:
                    normalized.append((page, window))

    # Pass 1: greedy paragraph packing
    current_words: List[str] = []
    current_page: Optional[int] = None

    def emit() -> None:
        nonlocal chunks, current_words, current_page, chunk_index
        if not current_words:
            return
        chunks.append(
            Chunk(
                chunk_index=chunk_index,
                source_page=current_page,
                content=" ".join(current_words),
            )
        )
        chunk_index += 1

    for page, words in normalized:
        if current_words and len(current_words) + len(words) > max_words:
            # Emit, then start next chunk with overlap tail from the emitted one.
            tail = current_words[-overlap_words:] if overlap_words > 0 else []
            emit()
            current_words = list(tail)
            # New chunk's source_page is the first paragraph that contributes non-overlap words.
            # The tail is overlap from the previous page; `page` is where the new content starts.
            current_page = page
        elif not current_words:
            current_page = page
        current_words.extend(words)

    emit()
    return chunks
```

### Verification

1. Unit-test the chunker with a synthetic input (one test case is enough for the fix pass):
   ```python
   paragraphs = [
       (1, " ".join(["alpha"] * 300)),
       (1, " ".join(["beta"] * 150)),
       (2, " ".join(["gamma"] * 120)),   # forces a chunk boundary
       (2, " ".join(["delta"] * 80)),
   ]
   chunks = chunk_paragraphs(paragraphs, max_words=500, overlap_words=50)
   # Expect: first chunk ends with alpha + beta fitting in 450 words; gamma fits (570 > 500 → new chunk)
   # Second chunk should have source_page=2 (gamma starts the new content)
   assert chunks[0].source_page == 1
   assert chunks[1].source_page == 2
   ```
2. Upload a real multi-page PDF and spot-check citations: ask a question whose answer is on a specific page and confirm the returned `source_page` is correct.

---

## F14 — `listManuals` sends empty headers (was H7)

**Severity**: 🟢 LOW (cosmetic now, latent bug)
**Files**: [frontend/lib/services/manual_assistant_service.dart](../../frontend/lib/services/manual_assistant_service.dart)
**Depends on**: F3.

### Problem

`listManuals` is the only method that doesn't pass any headers. Once F3 lands and the backend might care, this silently inconsistent path invites future bugs.

### Exact fix

In [manual_assistant_service.dart](../../frontend/lib/services/manual_assistant_service.dart), just remove the `headers:` argument from the `http.get` in `listManuals` (there's nothing to send) so the line is consistent with other read endpoints in the app:

```dart
final res = await http.get(
  Uri.parse('${AppConfig.baseUrl}/api/manuals/'),
);
```

No more `headers: {'Content-Type': 'application/json'}` — a GET with no body doesn't need a content type.

### Verification

`flutter analyze` clean; list still loads.

---

## F15 — Typed exceptions for dispatch (was M1)

**Severity**: 🟡 MEDIUM (code quality)
**Files**: [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py), [backend/routers/manuals.py](../../backend/routers/manuals.py)
**Depends on**: F8, F10, F11 (after those, the service errors are mostly typed already).

### Problem

The service throws `ManualUploadError("embedder_unavailable: ...")`, the router does `if "embedder_unavailable" in str(e): ...`. Fragile.

### Exact fix

In [manual_rag_service.py](../../backend/services/manual_rag_service.py), define (or retain) these typed exceptions near the top:

```python
class NoContentAfterChunkingError(Exception):
    pass

class CorpusFullError(Exception):
    def __init__(self, ceiling_mb: int):
        self.ceiling_mb = ceiling_mb

class EmbedderUnavailableError(Exception):
    pass

class GeneratorUnavailableError(Exception):
    pass

class ManualNotFoundError(Exception):
    pass

class UploadFailedError(Exception):
    pass
```

Remove `ManualUploadError` entirely if it's not used elsewhere after the refactor.

Then raise the specific class at each failure site (replace the existing stringly-typed `raise ManualUploadError("xxx: ...")` lines). For example:

```python
# inside upload_manual
try:
    embeddings = await embed_many(texts, concurrency=4)
except EmbedderTimeoutError as e:
    raise EmbedderUnavailableError("Embedding service is temporarily unavailable.") from e
```

And in the router, replace the big `if/elif` block with:

```python
try:
    result = await manual_rag_service.upload_manual(...)
except manual_rag_service.NoExtractableTextError:
    raise HTTPException(status_code=422, detail={"error": "no_extractable_text"})
except manual_rag_service.NoContentAfterChunkingError:
    raise HTTPException(status_code=422, detail={"error": "no_content_after_chunking"})
except manual_rag_service.CorpusFullError as e:
    raise HTTPException(status_code=413, detail={
        "error": "corpus_full",
        "message": "The manual library is full. Delete an existing manual to make room and try again.",
        "ceiling_mb": e.ceiling_mb,
    })
except manual_rag_service.EmbedderUnavailableError:
    raise HTTPException(status_code=504, detail={
        "error": "embedder_unavailable",
        "message": "The embedding service is temporarily unavailable. Please try again.",
    })
except Exception:
    raise HTTPException(status_code=500, detail={
        "error": "upload_failed",
        "message": "Something went wrong while saving the manual.",
    })
```

Same pattern for `ask` and `delete_manual` — each maps its typed exceptions to its contract error code.

(Note: `NoExtractableTextError` is already defined in `manual_parser.py` — re-export or import it in `manual_rag_service.py` so the router can catch it on the service path.)

### Verification

1. `grep -n 'ManualUploadError' backend/` → no matches after the refactor.
2. `grep -n 'in str(e)' backend/routers/manuals.py` → no matches.
3. Contract tests (F18) still pass.

---

## F16 — Nits (M3–M8, L1–L10 cleanup pass)

**Severity**: 🟡 MEDIUM / 🟢 LOW
**Files**: various
**Depends on**: F15 (so the router structure is settled).

Do these in one small cleanup commit after the criticals and highs are green. None of them require their own verification section.

- **M4** — Add title length check in the upload endpoint:
  ```python
  if len(title.strip()) > 200:
      raise HTTPException(status_code=400, detail={"error": "title_too_long", "limit": 200})
  ```
- **L1** — Rename `_mimeType` to `_fileExtension` in [upload_dialog.dart](../../frontend/lib/screens/manual_assistant/widgets/upload_dialog.dart) for clarity. Also move the extension→mime map to a `const` map at the top of the file.
- **L2** — In [chat_tab.dart](../../frontend/lib/screens/manual_assistant/chat_tab.dart) `_loadManuals`, show a retry affordance on error instead of silently swallowing:
  ```dart
  } catch (e) {
    if (mounted) setState(() { _loadError = e.toString(); });
  }
  ```
  And render the error with a Retry button in the empty state region.
- **L3** — Add a `_loading` boolean to `_ChatTabState` and render a `CircularProgressIndicator` while the initial `listManuals` is in flight, instead of flashing the empty state.
- **L4** — Either add `intl: ^0.19.0` to `pubspec.yaml` explicitly OR drop the `intl` import from [manuals_tab.dart](../../frontend/lib/screens/manual_assistant/manuals_tab.dart) and format the date manually: `'${manual.createdAt.year}-${manual.createdAt.month.toString().padLeft(2, "0")}-${manual.createdAt.day.toString().padLeft(2, "0")}'`.
- **L5** — Remove the unused `file_picker` import from [manuals_tab.dart](../../frontend/lib/screens/manual_assistant/manuals_tab.dart) (the picker is only used in `upload_dialog.dart`).
- **L6** — Remove duplicate `from uuid import UUID` inside `delete_manual` in [routers/manuals.py](../../backend/routers/manuals.py) (it's already imported at the top).
- **L7** — In the upload audit log call, use the trimmed `title.strip()` consistently.
- **L8** — The delete audit log should include the deleted manual's title — after F11, the RPC returns it, so pass `target_label=deleted["title"]`.
- **L10** — Already fine (the `ON CONFLICT DO NOTHING` seed is an improvement; leave it).

---

## F17 — Phase 6: Source highlighting (T047–T051)

**Severity**: 🟠 HIGH (spec feature; was explicitly pending)
**Files**:
- [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py)
- [frontend/lib/screens/manual_assistant/widgets/answer_card.dart](../../frontend/lib/screens/manual_assistant/widgets/answer_card.dart)
- [frontend/lib/screens/manual_assistant/widgets/source_card.dart](../../frontend/lib/screens/manual_assistant/widgets/source_card.dart) (new file)

**Depends on**: F8 (sources must actually contain relevant content before highlighting is meaningful).

### Problem

Phase 6 is entirely pending. `highlight_start`/`highlight_end` always serialize as `null`. No `SourceCard` widget exists. [FR-012a](./spec.md) isn't satisfied.

### Exact fix

**Backend** — in [manual_rag_service.py](../../backend/services/manual_rag_service.py), add below `_now_iso`:

```python
import re

# Arabic and English sentence terminators.
_SENT_RE = re.compile(r"(?<=[.!?؟])\s+")


def split_sentences(text: str) -> list[tuple[int, int, str]]:
    """Return list of (start_offset, end_offset, sentence_text) tuples within the input."""
    results: list[tuple[int, int, str]] = []
    cursor = 0
    for part in _SENT_RE.split(text):
        if not part.strip():
            cursor += len(part) + 1
            continue
        start = text.find(part, cursor)
        if start < 0:
            continue
        end = start + len(part)
        results.append((start, end, part))
        cursor = end
    return results


def _tokens(text: str) -> set[str]:
    return {
        w.strip(".,;:!?()[]\"'؟،").lower()
        for w in text.split()
        if len(w.strip(".,;:!?()[]\"'؟،")) >= 2
    }


def compute_highlight(
    chunk_content: str,
    answer_text: str,
    jaccard_threshold: float = 0.35,
) -> tuple[int | None, int | None]:
    """Return (highlight_start, highlight_end) offsets within chunk_content, or (None, None)."""
    chunk_sents = split_sentences(chunk_content)
    answer_sents = split_sentences(answer_text)
    if not chunk_sents or not answer_sents:
        return (None, None)

    answer_token_sets = [_tokens(s[2]) for s in answer_sents]

    best_score = 0.0
    best_range: tuple[int, int] | None = None
    for start, end, sent in chunk_sents:
        chunk_tokens = _tokens(sent)
        if not chunk_tokens:
            continue
        for a_tokens in answer_token_sets:
            if not a_tokens:
                continue
            inter = len(chunk_tokens & a_tokens)
            union = len(chunk_tokens | a_tokens)
            jaccard = inter / union if union else 0.0
            if jaccard > best_score:
                best_score = jaccard
                best_range = (start, end)

    if best_range and best_score >= jaccard_threshold:
        return best_range
    return (None, None)
```

Then, in `ask`, after the `content = chunk.get("content", "")` line, compute highlights relative to the truncated preview:

```python
content_preview = content[:500]
highlight_start, highlight_end = compute_highlight(content_preview, answer)
sources.append({
    "manual_id": chunk.get("manual_id"),
    "manual_title": manual_title,
    "chunk_index": chunk.get("chunk_index", 0),
    "source_page": source_page,
    "content_preview": content_preview,
    "highlight_start": highlight_start,
    "highlight_end": highlight_end,
})
```

Delete the `highlight_start: None, highlight_end: None` block at the end of `ask` — those fields are now set during assembly.

**Frontend** — create [frontend/lib/screens/manual_assistant/widgets/source_card.dart](../../frontend/lib/screens/manual_assistant/widgets/source_card.dart):

```dart
import 'package:flutter/material.dart';
import '../../../models/manual_source.dart';

class SourceCard extends StatelessWidget {
  final ManualSource source;

  const SourceCard({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    source.manualTitle,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                Text(
                  'page ${source.sourcePage ?? "—"}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildPreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final preview = source.contentPreview;
    final start = source.highlightStart;
    final end = source.highlightEnd;

    if (start == null || end == null || start < 0 || end > preview.length || start >= end) {
      return Text(
        preview,
        style: const TextStyle(fontSize: 12, height: 1.4),
      );
    }

    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 12, height: 1.4, color: Colors.black87),
        children: [
          TextSpan(text: preview.substring(0, start)),
          TextSpan(
            text: preview.substring(start, end),
            style: TextStyle(
              backgroundColor: Colors.yellow.shade200,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: preview.substring(end)),
        ],
      ),
    );
  }
}
```

Update [answer_card.dart](../../frontend/lib/screens/manual_assistant/widgets/answer_card.dart) to render sources via `SourceCard`:

```dart
import 'source_card.dart';

// inside build(), replace the `ListTile` map with:
children: answer.sources.map((source) => SourceCard(source: source)).toList(),
```

### Verification

1. Ask a question with a clear supporting sentence in an uploaded manual. The answer card's Sources section now shows the matching sentence highlighted in yellow.
2. Ask a question whose answer is vague. Some sources have highlights, others render plain (Jaccard < 0.35).
3. Answer cards where `grounded=false` still show no sources (no regression).

---

## F18 — Phase 7: Tests, fixtures, docs, quickstart validation

**Severity**: 🟠 HIGH (spec requires validation)
**Files**:
- [backend/tests/routers/test_manuals.py](../../backend/tests/routers/test_manuals.py) (new)
- [backend/tests/fixtures/manual_sample.pdf](../../backend/tests/fixtures/manual_sample.pdf) (new)
- [backend/tests/fixtures/manual_sample_ar.pdf](../../backend/tests/fixtures/manual_sample_ar.pdf) (new)
- [backend/tests/fixtures/manual_sample_empty.pdf](../../backend/tests/fixtures/manual_sample_empty.pdf) (new)
- [backend/tests/fixtures/manual_sample_large.pdf](../../backend/tests/fixtures/manual_sample_large.pdf) (new)
- [AGENT.md](../../AGENT.md) (append)

**Depends on**: F1–F17 all green.

Execute [tasks.md](./tasks.md) Phase 7 verbatim — T052 through T066. The contract test checklist is already written in [contracts/manuals-api.md](./contracts/manuals-api.md) under "Contract-test checklist." Work through it top to bottom.

Also run all six manual flows from [quickstart.md](./quickstart.md) (A, B, C, D, E, F) and record a pass/fail per flow.

Finally, append an entry for feature 040 to [AGENT.md](../../AGENT.md) describing the Manual Assistant's endpoints, tables, on-disk storage layout, and role access (all three).

### Verification

- `pytest backend/tests/routers/test_manuals.py -v` → all tests green.
- Flows A–F all pass on a clean database.
- `grep -n "040-manual-rag-assistant\|Manual Assistant" AGENT.md` → matches.

---

## F19 — Prompt assembly order for 3-layer context (Layer 2 + Layer 3)

**Severity**: 🔴 CRITICAL (without this, system instructions and history are ignored)
**Files**:
- [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py)
- [backend/routers/manuals.py](../../backend/routers/manuals.py)

**Depends on**: T067, T068, T069, T070 (Phase 8 tasks)

### Problem

After Phase 8 tasks are applied, the prompt assembly in `ask()` must follow the exact 3-layer order: system instructions → manual chunks → history → current question. If the order is wrong, Gemma deprioritizes the manual grounding constraint and may hallucinate.

### Exact fix

Verify the assembled prompt in `manual_rag_service.ask()` matches this structure exactly, in this order:

```python
parts = []

if system_instructions.strip():
    parts.append(system_instructions.strip())

parts.append(
    "You are a technical assistant for a civil aviation maintenance department.\n"
    "Answer the technician's question using ONLY the manual sections provided below.\n"
    'If the answer is not found in the sections, say: "This information is not in the available manuals."\n'
    "Reply in the same language as the question (Arabic or English)."
)

parts.append(f"MANUAL SECTIONS:\n{retrieved_chunks}")

if history:
    history_block = "\n\n".join(
        f"User: {turn['question']}\nAssistant: {turn['answer']}"
        for turn in history[-10:]
    )
    parts.append(f"CONVERSATION HISTORY:\n{history_block}")

parts.append(f"QUESTION: {user_question}\n\nANSWER:")

prompt = "\n\n".join(parts)
```

### Verification

1. With system instructions set to "Test context", print the assembled prompt before the Ollama call. Confirm the first line is "Test context".
2. After two question/answer turns, send a third question. Confirm the CONVERSATION HISTORY block appears between MANUAL SECTIONS and QUESTION in the assembled prompt.
3. With empty system instructions, confirm no blank line appears at the top of the prompt.
4. `grep -n "PROMPT_TEMPLATE" backend/services/manual_rag_service.py` should return no matches — the hardcoded template constant must be replaced by the dynamic assembly above.

---

## Final self-check before handing back for review

After the full fix pass, run these greps and the full quickstart. If any of these produce unexpected matches, you missed a fix:

```bash
# Criticals
grep -rn 'get_current_user\|"anonymous"\|user_id=' backend/routers/manuals.py       # → empty
grep -n 'Path("backend")' backend/services/manual_storage_service.py               # → empty
grep -n '"now()"' backend/services/manual_rag_service.py                            # → empty
grep -n 'APIRouter(prefix="/api/manuals"' backend/routers/manuals.py                # → empty
grep -n 'Full vector search' backend/services/manual_rag_service.py                 # → empty
grep -n 'f"{title}.{file_extension}"' backend/services/manual_rag_service.py        # → empty

# Highs
grep -n 'chunk_count \* 3500' backend/services/manual_rag_service.py                # → empty
grep -n 'users!inner' backend/routers/manuals.py                                    # → empty
grep -n 'in str(e)' backend/routers/manuals.py                                      # → empty (after F15)

# Flutter
grep -n 'MultipartFile.fromBytes' frontend/lib/services/manual_assistant_service.dart   # → exactly one match, and it includes contentType
grep -n 'statusCode == 204' frontend/lib/services/manual_assistant_service.dart          # → present
```

And the quickstart smoke test:

1. Clean DB: drop & recreate the three tables, re-apply migration (including F8/F10/F11 RPCs).
2. Log in as a `technician` user.
3. Upload `manual_sample.pdf` via the Manuals tab. Row appears. File lives at `backend/uploaded_files/manuals/<uuid>.pdf`.
4. Switch to Chat tab. Ask a question whose answer is in the manual. Get a grounded answer. Expand Sources — see at least one highlighted span.
5. Ask a question whose answer is NOT in any manual. Get the sentinel line.
6. Select the manual in the filter. Ask a question whose answer is only in a *different* manual (upload a second one first). Get the sentinel line (strict filter).
7. Delete both manuals via long-press. Confirm rows disappear, `manual_corpus_stats.total_bytes` returns to 0, `backend/uploaded_files/manuals/` is empty.
8. `SELECT action, count(*) FROM user_activity_log WHERE action IN ('uploaded_manual','asked_manual','deleted_manual') GROUP BY action;` — counts match your actions.

If all of the above pass, the feature is ready for a second review pass.

---

## Handoff note for the reviewer (me, next turn)

After the implementing LLM reports "fixes applied," I will:

1. Re-run every `grep` above.
2. Walk the quickstart smoke test checklist.
3. Diff the changed files against this fix manifest and flag any deviation.
4. Run `pytest backend/tests/routers/test_manuals.py -v` if Phase 7 landed.
5. Re-score severity of any remaining findings.

Expected outcome: if the LLM follows this manifest top to bottom and self-verifies at each step, no CRITICAL or HIGH findings should remain. A handful of LOW nits are acceptable as a second-pass cleanup.
