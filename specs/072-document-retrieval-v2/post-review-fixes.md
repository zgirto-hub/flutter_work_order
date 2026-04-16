# Post-Review Fixes for Spec 072

**Branch**: `072-document-retrieval-v2`
**Do NOT commit** — leave as uncommitted changes for final review.

Read each fix completely before making changes. Fixes are in priority order.

---

## Fix 1 (Critical): Migration file path lookup always fails

**File**: `backend/routers/documents.py`, line 736

**Problem**: `manual.get("file_path", "")` reads a column that doesn't exist on the `manuals` table. The `manuals` table has `id`, `title`, `file_name`, `file_extension` — no `file_path`. Files are stored at `uploaded_files/manuals/{manual_id}.{file_extension}`. Every manual migration will fail with "File not found".

**Fix**: Replace lines 735-737 with:

```python
            # Build file path from manual ID and extension (manuals table has no file_path column)
            file_ext = manual.get("file_extension", "pdf")
            file_path = os.path.join("uploaded_files", "manuals", f"{manual['id']}.{file_ext}")
            if not os.path.exists(file_path):
                _migration_status["failed"].append(
                    {"id": manual["id"], "error": f"File not found: {file_path}"}
                )
                continue
```

Also delete lines 743-753 (the `file_ext` detection block that follows) since `file_ext` is now set above. Replace the `ext` variable usage on line 761 with `file_ext`:

```python
            "file_extension": file_ext,
```

---

## Fix 2 (Critical): Re-embed background task calls async without await

**File**: `backend/routers/documents.py`, lines 639-658

**Problem**: `_re_embed_task()` is a sync `def` function but calls `embed_single()` which is `async def`. Without `await`, the result is a coroutine object, not a list of floats. The embedding string will be garbage.

**Fix**: Change the function from `def` to `async def`:

```python
# BEFORE (line 639):
    def _re_embed_task():

# AFTER:
    async def _re_embed_task():
```

And add `await` to the embed call:

```python
# BEFORE (line 649):
                emb = embed_single(chunk["content"])

# AFTER:
                emb = await embed_single(chunk["content"])
```

FastAPI's `BackgroundTasks` supports async functions natively, so `background_tasks.add_task(_re_embed_task)` will work correctly.

---

## Fix 3 (Critical): DELETE /migrate-cleanup route shadowed by DELETE /{document_id}

**File**: `backend/routers/documents.py`, line 787 vs line 134

**Problem**: FastAPI matches routes in definition order. `DELETE /{document_id}` (line 134) matches any DELETE to `/documents/<anything>`, including `/documents/migrate-cleanup`. The cleanup endpoint is unreachable — it always returns 404 "Document not found".

**Fix**: Move the `DELETE /migrate-cleanup` endpoint BEFORE `DELETE /{document_id}`. Cut lines 787-809 (the entire `migrate_cleanup` function) and paste them before line 134 (before `delete_document_endpoint`).

The final order of DELETE endpoints should be:
1. `DELETE /migrate-cleanup` (specific path — matches first)
2. `DELETE /{document_id}` (catch-all path — matches after)
3. `DELETE /{document_id}/chunks/{chunk_id}` (more specific, no conflict)
4. `DELETE /{document_id}/chunks/bulk-delete` (more specific, no conflict)

Similarly, check `GET /migration-status` — it should be before `GET /{document_id}/status`. Move the `GET /migration-status` endpoint (lines 780-784) before `GET /{document_id}/status` endpoint.

And `POST /migrate-all` — check it doesn't conflict with `POST /{document_id}/reindex`. It doesn't (POST routes are `/upload`, `/{doc_id}/reindex`, `/{doc_id}/chunks`, etc.) so `POST /migrate-all` is fine where it is.

---

## Fix 4 (Critical): Parent chunk deletion — children deleted after parent CASCADE

**File**: `backend/routers/documents.py`, lines 456-462

**Problem**: Line 456 deletes the parent chunk first. If the DB has `ON DELETE CASCADE` on `parent_id` FK (which it does — from spec 070 DDL), the children are already gone by line 456. Line 462 then tries to delete children that no longer exist — it's a no-op but wasteful and confusing.

**Fix**: Delete children BEFORE the parent. Replace lines 453-466 with:

```python
    parent_id = resp.data.get("parent_id")
    chunk_type = resp.data.get("chunk_type")

    # If deleting a parent, explicitly delete children first (before CASCADE)
    if chunk_type == "parent":
        supabase.table("document_chunks").delete().eq("parent_id", chunk_id).execute()

    # Delete the chunk itself
    supabase.table("document_chunks").delete().eq("id", chunk_id).execute()

    # Reindex siblings if this was a child chunk
    if parent_id:
        _reindex_siblings(document_id, parent_id)

    log_activity(user_email, "chunk", "deleted", "", chunk_id)

    return {"deleted": True}
```

---

## Fix 5 (Important): Split endpoint doesn't select chunk_index

**File**: `backend/routers/documents.py`, line 480

**Problem**: The SELECT is `.select("id, parent_id, content")` but line 522 uses `resp.data.get("chunk_index", 0)`. Since `chunk_index` is not selected, it always defaults to 0, causing incorrect sibling reindexing.

**Fix**: Add `chunk_index` to the select:

```python
# BEFORE (line 480):
        .select("id, parent_id, content")

# AFTER:
        .select("id, parent_id, content, chunk_index")
```

---

## Fix 6 (Important): Migration is synchronous — blocks HTTP request

**File**: `backend/routers/documents.py`, lines 713-777

**Problem**: The `for` loop processing all manuals runs synchronously inside the request handler. For 10-20 manuals with embedding, this takes 10+ minutes. The HTTP request will timeout. The response on line 777 is returned AFTER all processing, so the client never sees "migrating" to start polling.

**Fix**: Use `BackgroundTasks` to run the migration loop:

```python
@router.post("/migrate-all")
async def migrate_all_documents(
    user_email: str = Query(...),
    background_tasks: BackgroundTasks = None,
):
    _admin_check(user_email)

    global _migration_status

    manuals_resp = supabase.table("manuals").select("*").execute()
    all_manuals = manuals_resp.data or []
    _migration_status = {
        "status": "migrating",
        "completed": 0,
        "total": len(all_manuals),
        "failed": [],
        "current": "",
    }

    background_tasks.add_task(_run_migration, all_manuals, user_email)

    return {"status": "migrating", "total_manuals": len(all_manuals)}


async def _run_migration(all_manuals: list, user_email: str):
    """Background task that processes manuals sequentially."""
    global _migration_status
    from services.document_service import index_document

    for i, manual in enumerate(all_manuals):
        _migration_status["current"] = manual.get("title", "")
        _migration_status["completed"] = i

        try:
            file_ext = manual.get("file_extension", "pdf")
            file_path = os.path.join("uploaded_files", "manuals", f"{manual['id']}.{file_ext}")
            if not os.path.exists(file_path):
                _migration_status["failed"].append(
                    {"id": manual["id"], "error": f"File not found: {file_path}"}
                )
                continue

            # Look up uploader email from users table
            uploader_email = user_email
            if manual.get("uploaded_by"):
                user_resp = supabase.table("users").select("email").eq("id", manual["uploaded_by"]).maybe_single().execute()
                if user_resp.data:
                    uploader_email = user_resp.data["email"]

            doc_row = {
                "filename": manual.get("file_name", ""),
                "display_name": manual.get("title", ""),
                "file_path": file_path,
                "status": "pending",
                "uploaded_by": uploader_email,
                "file_extension": file_ext,
            }
            doc_resp = supabase.table("knowledge_documents").insert(doc_row).execute()
            doc_id = doc_resp.data[0]["id"]

            await index_document(doc_id, file_path)

            _migration_status["completed"] = i + 1

        except Exception as e:
            _migration_status["failed"].append({"id": manual["id"], "error": str(e)})

    _migration_status["status"] = (
        "completed_with_errors" if _migration_status["failed"] else "completed"
    )

    log_activity(user_email, "document", "migrated", f"{len(all_manuals)} manuals", "")
```

Note: This fix also addresses **Fix 1** (file path) and **I4** (uploaded_by UUID → email lookup). If you apply Fix 6, you can skip the file_path portion of Fix 1 since the migration function is fully replaced here.

---

## Fix 7 (Important): POST/PUT endpoints send content via query params

**File**: `backend/routers/documents.py` — `add_chunk` (line 284), `update_chunk` (line 387)

**Problem**: Chunk content is passed as `content: str = Query(...)`. URL query strings have ~2000 char limits. Large chunk content will be truncated or rejected.

**Fix for update_chunk** — replace lines 387-392:

```python
from pydantic import BaseModel

class ChunkUpdateBody(BaseModel):
    content: str
    user_email: str

@router.put("/{document_id}/chunks/{chunk_id}")
async def update_chunk(
    document_id: str,
    chunk_id: str,
    body: ChunkUpdateBody,
):
    _admin_check(body.user_email)
    content = body.content
```

**Fix for add_chunk** — replace lines 284-291:

```python
class ChunkAddBody(BaseModel):
    parent_id: str
    content: str
    user_email: str
    insert_after: Optional[int] = None

@router.post("/{document_id}/chunks")
async def add_chunk(
    document_id: str,
    body: ChunkAddBody,
):
    _admin_check(body.user_email)
    parent_id = body.parent_id
    content = body.content
    insert_after = body.insert_after
```

Put the Pydantic models near the top of the file (after imports, before the first endpoint).

**Also update the frontend** — `frontend/lib/services/document_service.dart`:

**updateChunk** (lines 95-104) — change from query params to JSON body:
```dart
  Future<Map<String, dynamic>> updateChunk(String documentId, String chunkId,
      String content, String userEmail) async {
    final resp = await http.put(
      Uri.parse('$_baseUrl/documents/$documentId/chunks/$chunkId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'content': content, 'user_email': userEmail}),
    );
    if (resp.statusCode != 200)
      throw Exception('Update chunk failed: ${resp.statusCode}');
    return jsonDecode(resp.body);
  }
```

**addChunk** (lines 106-118) — change from query params to JSON body:
```dart
  Future<Map<String, dynamic>> addChunk(
      String documentId, String parentId, String content, String userEmail,
      {int? insertAfter}) async {
    final body = {
      'parent_id': parentId,
      'content': content,
      'user_email': userEmail,
    };
    if (insertAfter != null) body['insert_after'] = insertAfter;
    final resp = await http.post(
      Uri.parse('$_baseUrl/documents/$documentId/chunks'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200)
      throw Exception('Add chunk failed: ${resp.statusCode}');
    return jsonDecode(resp.body);
  }
```

---

## Fix 8 (Important): Re-embed response missing total_children

**File**: `backend/routers/documents.py`, line 663

**Problem**: Returns `{"message": "Re-embedding started"}` but API contract specifies `{"status": "re-embedding", "total_children": N}`.

**Fix**: Before `background_tasks.add_task(...)`, count the children:

```python
    children_count = len(
        supabase.table("document_chunks")
        .select("id")
        .eq("document_id", document_id)
        .eq("chunk_type", "child")
        .execute()
        .data or []
    )

    background_tasks.add_task(_re_embed_task)

    return {"status": "re-embedding", "total_children": children_count}
```

---

## Verification

After all 8 fixes, run:
```bash
python -c "import ast; ast.parse(open('backend/routers/documents.py').read()); print('documents.py: OK')"
python -c "import ast; ast.parse(open('backend/services/document_search_service.py').read()); print('document_search_service.py: OK')"
python -c "import ast; ast.parse(open('backend/services/manual_rag_service.py').read()); print('manual_rag_service.py: OK')"
```

All should print OK.

Also verify with `git diff --stat` that only the expected files are modified.
