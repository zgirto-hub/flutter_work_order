# TASK: Knowledge Chunk Editor — View/Edit Uploaded Knowledge

**Branch**: Create a new branch `050-knowledge-chunk-editor` from `main`  
**Priority**: Implement backend first, then frontend

## What To Build

Add a chunk editor to the "Ask the AI" Knowledge tab. When an admin taps a manual in the list, they navigate to a new screen showing that manual's chunks (paginated, 20/page). From there they can: edit chunk text, delete chunks, add new chunks, split a chunk into two, merge adjacent chunks, and re-embed (single or batch). Every mutation that changes chunk content auto-regenerates the vector embedding for the affected chunk(s).

## Architecture Overview

```
Flutter Frontend                         FastAPI Backend
─────────────────                        ──────────────
ManualsTab                               GET  /manuals/{id}/chunks?page=1&page_size=20
  └─ tap card → ChunkEditorScreen        GET  /manuals/{id}/chunks/{chunk_id}
       ├─ ChunkCard (paginated list)     PUT  /manuals/{id}/chunks/{chunk_id}
       ├─ tap → ChunkEditScreen          DELETE /manuals/{id}/chunks/{chunk_id}
       ├─ Add Chunk → ChunkEditScreen    POST /manuals/{id}/chunks
       ├─ Split → SplitEditor            POST /manuals/{id}/chunks/{chunk_id}/split
       ├─ Merge → confirm dialog         POST /manuals/{id}/chunks/{chunk_id}/merge
       ├─ Re-embed All button            POST /manuals/{id}/chunks/re-embed
       └─ Bulk Delete (multi-select)     DELETE /manuals/{id}/chunks/bulk-delete
```

---

## PART 1: Backend (FastAPI)

### File to modify: `backend/routers/manuals.py`

All new endpoints go in this existing file. All are **admin-only** — use the same admin check pattern already in the file:

```python
# Existing admin check pattern (see lines ~441-453 of manuals.py):
user_resp = (
    supabase.table("users")
    .select("user_type")
    .eq("email", user_email)
    .maybe_single()
    .execute()
)
if not user_resp.data or user_resp.data.get("user_type") != "admin":
    raise HTTPException(status_code=403, detail={"error": "admin_required"})
```

### Database context

The `manual_chunks` table schema (already exists, no migration needed):

```sql
CREATE TABLE manual_chunks (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    manual_id UUID NOT NULL REFERENCES manuals(id) ON DELETE CASCADE,
    chunk_index INTEGER NOT NULL,    -- sequential, 0-based
    source_page INTEGER,             -- nullable
    content TEXT NOT NULL,
    embedding VECTOR(768) NOT NULL,  -- nomic-embed-text via Ollama
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (id)
);
-- Unique constraint: (manual_id, chunk_index)
```

The `manuals` table has a `chunk_count INTEGER` column that must be kept in sync.

### Embedding helper

Use the existing embedder at `backend/services/ollama_embedder.py`:

```python
from services.ollama_embedder import embed_single, embed_many
# embed_single(text: str) -> List[float]  (768-dim vector)
# embed_many(texts: List[str], concurrency=4) -> List[List[float]]
```

### Supabase client

Already imported at top of manuals.py:
```python
from db import supabase  # Supabase Python client
```

### Endpoints to implement

#### 1. `GET /manuals/{manual_id}/chunks`

Paginated chunk list. Query params: `page` (default 1), `page_size` (default 20), `user_email` (required, for admin check).

```python
@router.get("/manuals/{manual_id}/chunks")
async def list_chunks(manual_id: str, user_email: str = Query(...), page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100)):
    # 1. Admin check
    # 2. Verify manual exists
    # 3. Count total chunks: supabase.table("manual_chunks").select("id", count="exact").eq("manual_id", manual_id).execute()
    # 4. Fetch page: .select("id, chunk_index, source_page, content, created_at")
    #      .eq("manual_id", manual_id)
    #      .order("chunk_index")
    #      .range((page-1)*page_size, page*page_size - 1)
    #      .execute()
    # 5. Return { "chunks": [...], "total": count, "page": page, "page_size": page_size, "total_pages": ceil(count/page_size) }
    #    Each chunk: { id, chunk_index, source_page, content, created_at }
    #    NOTE: Do NOT return the embedding vector (it's huge)
```

#### 2. `GET /manuals/{manual_id}/chunks/{chunk_id}`

Single chunk detail.

```python
@router.get("/manuals/{manual_id}/chunks/{chunk_id}")
async def get_chunk(manual_id: str, chunk_id: str, user_email: str = Query(...)):
    # Admin check, fetch single chunk, return { id, chunk_index, source_page, content, created_at }
```

#### 3. `PUT /manuals/{manual_id}/chunks/{chunk_id}`

Edit chunk text + auto re-embed.

```python
class UpdateChunkRequest(BaseModel):
    content: str
    user_email: str

@router.put("/manuals/{manual_id}/chunks/{chunk_id}")
async def update_chunk(manual_id: str, chunk_id: str, request: UpdateChunkRequest):
    # 1. Admin check
    # 2. Validate content is non-empty
    # 3. Generate new embedding: embedding = await embed_single(request.content)
    # 4. Update: supabase.table("manual_chunks").update({"content": request.content, "embedding": str(embedding)}).eq("id", chunk_id).eq("manual_id", manual_id).execute()
    #    NOTE: embedding must be stored as a string representation of the list for pgvector
    # 5. Log activity
    # 6. Return updated chunk (without embedding)
```

**IMPORTANT about embedding format**: When updating embeddings via the Supabase Python client, the vector must be passed as a string like `"[0.1, 0.2, ...]"`. Check how `manual_rag_service.py` stores embeddings and follow the same pattern.

#### 4. `DELETE /manuals/{manual_id}/chunks/{chunk_id}`

Delete single chunk, re-index remaining.

```python
@router.delete("/manuals/{manual_id}/chunks/{chunk_id}", status_code=204)
async def delete_chunk(manual_id: str, chunk_id: str, user_email: str = Query(...)):
    # 1. Admin check
    # 2. Delete the chunk
    # 3. Re-index: fetch all remaining chunks ordered by chunk_index, update each to sequential 0,1,2...
    # 4. Update manuals.chunk_count: supabase.table("manuals").update({"chunk_count": new_count}).eq("id", manual_id).execute()
    # 5. Log activity
    # 6. Return 204
```

#### 5. `POST /manuals/{manual_id}/chunks`

Add new chunk at a position.

```python
class AddChunkRequest(BaseModel):
    content: str
    insert_after: int = -1  # chunk_index to insert after; -1 = append at end
    user_email: str

@router.post("/manuals/{manual_id}/chunks")
async def add_chunk(manual_id: str, request: AddChunkRequest):
    # 1. Admin check
    # 2. Validate content non-empty
    # 3. Embed: embedding = await embed_single(request.content)
    # 4. Determine new chunk_index (insert_after + 1)
    # 5. Shift existing chunks: any chunk with chunk_index >= new_index gets chunk_index += 1
    # 6. Insert new chunk with the new_index
    # 7. Update manuals.chunk_count
    # 8. Log activity
    # 9. Return new chunk (without embedding)
```

#### 6. `POST /manuals/{manual_id}/chunks/{chunk_id}/split`

Split a chunk at a character position.

```python
class SplitChunkRequest(BaseModel):
    split_position: int  # character index to split at
    user_email: str

@router.post("/manuals/{manual_id}/chunks/{chunk_id}/split")
async def split_chunk(manual_id: str, chunk_id: str, request: SplitChunkRequest):
    # 1. Admin check
    # 2. Fetch the chunk
    # 3. Validate split_position is within content length (> 0 and < len(content))
    # 4. Split content: part_a = content[:split_position], part_b = content[split_position:]
    # 5. Strip both parts, validate both are non-empty
    # 6. Embed both: embeddings = await embed_many([part_a, part_b])
    # 7. Update original chunk: content = part_a, embedding = embeddings[0]
    # 8. Shift chunks after this one: chunk_index += 1
    # 9. Insert new chunk (part_b) with chunk_index = original_index + 1
    # 10. Update manuals.chunk_count += 1
    # 11. Log activity
    # 12. Return both chunks (without embeddings)
```

#### 7. `POST /manuals/{manual_id}/chunks/{chunk_id}/merge`

Merge chunk with the next one.

```python
class MergeChunkRequest(BaseModel):
    user_email: str

@router.post("/manuals/{manual_id}/chunks/{chunk_id}/merge")
async def merge_chunk(manual_id: str, chunk_id: str, request: MergeChunkRequest):
    # 1. Admin check
    # 2. Fetch the chunk, get its chunk_index
    # 3. Fetch the next chunk (chunk_index + 1 for same manual_id)
    # 4. If no next chunk, return 400 error "No next chunk to merge with"
    # 5. Merge: combined = chunk.content + "\n\n" + next_chunk.content
    # 6. Embed: embedding = await embed_single(combined)
    # 7. Update original chunk: content = combined, embedding = new embedding
    # 8. Delete the next chunk
    # 9. Re-index remaining chunks
    # 10. Update manuals.chunk_count -= 1
    # 11. Log activity
    # 12. Return merged chunk (without embedding)
```

#### 8. `POST /manuals/{manual_id}/chunks/re-embed`

Batch re-embed all chunks as a background task.

```python
from fastapi import BackgroundTasks

@router.post("/manuals/{manual_id}/chunks/re-embed")
async def re_embed_all(manual_id: str, user_email: str = Query(...), background_tasks: BackgroundTasks = None):
    # 1. Admin check
    # 2. Count chunks
    # 3. Define background function that:
    #    - Fetches all chunks for the manual
    #    - For each chunk: embed_single(content), update embedding
    #    - Process sequentially (not concurrently) to conserve RAM (15GB server limit)
    # 4. background_tasks.add_task(re_embed_worker, manual_id)
    # 5. Return { "status": "started", "chunk_count": count }
```

#### 9. `DELETE /manuals/{manual_id}/chunks/bulk-delete`

Bulk delete selected chunks.

```python
class BulkDeleteRequest(BaseModel):
    chunk_ids: List[str]
    user_email: str

@router.delete("/manuals/{manual_id}/chunks/bulk-delete")
async def bulk_delete_chunks(manual_id: str, request: BulkDeleteRequest):
    # 1. Admin check
    # 2. Delete all chunks with ids in chunk_ids AND manual_id matches
    # 3. Re-index remaining chunks
    # 4. Update manuals.chunk_count
    # 5. Log activity
    # 6. Return { "deleted": len(chunk_ids) }
```

### Re-index helper function

Create a shared helper since multiple endpoints need it:

```python
def _reindex_chunks(manual_id: str):
    """Re-number chunk_index values sequentially (0-based) and update chunk_count."""
    chunks = (
        supabase.table("manual_chunks")
        .select("id")
        .eq("manual_id", manual_id)
        .order("chunk_index")
        .execute()
    )
    for i, chunk in enumerate(chunks.data):
        supabase.table("manual_chunks").update({"chunk_index": i}).eq("id", chunk["id"]).execute()
    
    supabase.table("manuals").update({"chunk_count": len(chunks.data)}).eq("id", manual_id).execute()
```

### IMPORTANT: Route ordering

FastAPI matches routes top-to-bottom. The route `POST /manuals/{manual_id}/chunks/re-embed` will conflict with `POST /manuals/{manual_id}/chunks/{chunk_id}/split` if not ordered correctly. **Put fixed-path routes (re-embed, bulk-delete) BEFORE parameterized routes ({chunk_id}).**

```python
# Correct order:
@router.post("/manuals/{manual_id}/chunks/re-embed")     # fixed path first
@router.delete("/manuals/{manual_id}/chunks/bulk-delete") # fixed path first
@router.get("/manuals/{manual_id}/chunks")                # list
@router.post("/manuals/{manual_id}/chunks")               # add
@router.get("/manuals/{manual_id}/chunks/{chunk_id}")     # detail
@router.put("/manuals/{manual_id}/chunks/{chunk_id}")     # update
@router.delete("/manuals/{manual_id}/chunks/{chunk_id}")  # delete
@router.post("/manuals/{manual_id}/chunks/{chunk_id}/split")
@router.post("/manuals/{manual_id}/chunks/{chunk_id}/merge")
```

---

## PART 2: Frontend (Flutter)

### Existing files to reference for patterns

- **Service pattern**: `frontend/lib/services/manual_assistant_service.dart` — all HTTP calls use `http` package, `AppConfig.baseUrl`, `jsonDecode`
- **Theme**: `frontend/lib/theme/app_theme.dart` — use existing AppTheme/AppColors
- **Config**: `frontend/lib/config.dart` — `AppConfig.baseUrl` for API URL
- **Manual model**: `frontend/lib/models/manual.dart` — `Manual` class with `id`, `title`, `fileName`, etc.
- **Current Knowledge tab**: `frontend/lib/screens/manual_assistant/manuals_tab.dart`

### File 1: Modify `frontend/lib/services/manual_assistant_service.dart`

Add these methods to the existing `ManualAssistantService` class:

```dart
// --- Chunk Editor Methods ---

Future<Map<String, dynamic>> listChunks(String manualId, {int page = 1, int pageSize = 20, required String userEmail}) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/manuals/$manualId/chunks?page=$page&page_size=$pageSize&user_email=${Uri.encodeComponent(userEmail)}'),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    if (res.statusCode == 403) throw Exception('Admin access required');
    throw Exception('Failed to load chunks');
}

Future<Map<String, dynamic>> getChunk(String manualId, String chunkId, {required String userEmail}) async {
    // GET /manuals/{manualId}/chunks/{chunkId}?user_email=...
}

Future<Map<String, dynamic>> updateChunk(String manualId, String chunkId, String content, {required String userEmail}) async {
    // PUT /manuals/{manualId}/chunks/{chunkId} with body { content, user_email }
}

Future<void> deleteChunk(String manualId, String chunkId, {required String userEmail}) async {
    // DELETE /manuals/{manualId}/chunks/{chunkId}?user_email=...
}

Future<Map<String, dynamic>> addChunk(String manualId, String content, {int insertAfter = -1, required String userEmail}) async {
    // POST /manuals/{manualId}/chunks with body { content, insert_after, user_email }
}

Future<Map<String, dynamic>> splitChunk(String manualId, String chunkId, int splitPosition, {required String userEmail}) async {
    // POST /manuals/{manualId}/chunks/{chunkId}/split with body { split_position, user_email }
}

Future<Map<String, dynamic>> mergeChunk(String manualId, String chunkId, {required String userEmail}) async {
    // POST /manuals/{manualId}/chunks/{chunkId}/merge with body { user_email }
}

Future<Map<String, dynamic>> reEmbedAll(String manualId, {required String userEmail}) async {
    // POST /manuals/{manualId}/chunks/re-embed?user_email=...
}

Future<Map<String, dynamic>> bulkDeleteChunks(String manualId, List<String> chunkIds, {required String userEmail}) async {
    // DELETE /manuals/{manualId}/chunks/bulk-delete with body { chunk_ids, user_email }
    // NOTE: Use http.Request with DELETE method and body (http.delete doesn't support body)
}
```

### File 2: Modify `frontend/lib/screens/manual_assistant/manuals_tab.dart`

Make the manual ListTile tappable:

```dart
// Change the ListTile to add onTap:
return ListTile(
  title: Text(manual.title),
  subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
  trailing: IconButton(
    icon: const Icon(Icons.delete_outline),
    onPressed: () => _showDeleteDialog(manual),
  ),
  onTap: () {
    // Only navigate if user is admin
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChunkEditorScreen(manual: manual),
      ),
    );
  },
);
```

The delete should move from `onLongPress` to the trailing `IconButton` directly (since `onTap` is now used for navigation).

### File 3: NEW `frontend/lib/screens/manual_assistant/chunk_editor_screen.dart`

Paginated chunk list screen.

```dart
class ChunkEditorScreen extends StatefulWidget {
  final Manual manual;
  const ChunkEditorScreen({super.key, required this.manual});
  // ...
}

class _ChunkEditorScreenState extends State<ChunkEditorScreen> {
  final ManualAssistantService _service = ManualAssistantService();
  List<Map<String, dynamic>> _chunks = [];
  int _page = 1;
  int _totalPages = 1;
  int _totalChunks = 0;
  bool _loading = true;
  bool _selectionMode = false;
  Set<String> _selectedIds = {};

  // AppBar: title = manual.title
  //   Actions: 
  //     - IconButton(Icons.add) → navigate to ChunkEditScreen(mode: add, manualId, totalChunks)
  //     - IconButton(Icons.sync) → call _reEmbedAll()

  // Body: ListView of ChunkCards
  //   - Each card: chunk_index, source_page, content preview (~150 chars)
  //   - Overflow menu (PopupMenuButton): Edit, Delete, Split, "Merge with next" (hidden if last)
  //   - Long press enters selection mode (checkboxes appear)
  
  // Bottom: Row with Previous/PageIndicator/Next buttons
  
  // When in selection mode: show BottomAppBar with "Delete Selected (N)" button
  
  // _loadChunks(page) → calls service.listChunks()
  // _deleteChunk(chunkId) → confirm dialog → service.deleteChunk() → _loadChunks()
  // _mergeChunk(chunkId) → show preview dialog → service.mergeChunk() → _loadChunks()
  // _reEmbedAll() → service.reEmbedAll() → show SnackBar "Re-embedding N chunks..."
  // _bulkDelete() → confirm dialog → service.bulkDeleteChunks() → _loadChunks()
}
```

### File 4: NEW `frontend/lib/screens/manual_assistant/chunk_edit_screen.dart`

Edit/Add/Split screen — one screen with modes.

```dart
enum ChunkEditMode { edit, add, split }

class ChunkEditScreen extends StatefulWidget {
  final ChunkEditMode mode;
  final String manualId;
  final Map<String, dynamic>? chunk; // null for add mode
  final int? totalChunks; // for add mode insert position dropdown
  
  const ChunkEditScreen({
    super.key,
    required this.mode,
    required this.manualId,
    this.chunk,
    this.totalChunks,
  });
}

class _ChunkEditScreenState extends State<ChunkEditScreen> {
  late TextEditingController _controller;
  bool _modified = false;
  bool _saving = false;
  int _insertAfter = -1; // for add mode

  // AppBar title:
  //   edit → "Edit Chunk #N"
  //   add → "Add Chunk"
  //   split → "Split Chunk #N"
  
  // AppBar actions: Save button (disabled if not modified or saving)
  
  // Body for edit/add mode:
  //   - Read-only metadata row: source page, chunk index, character count (live)
  //   - For add mode: dropdown "Insert after chunk #__" (0 to totalChunks-1, plus "End")
  //   - Large multiline TextField with full chunk content
  
  // Body for split mode:
  //   - Instruction text: "Tap in the text where you want to split, then press Split Here"
  //   - Large multiline TextField (the chunk text)
  //   - "Split Here" button at bottom (enabled only when cursor is inside text, not at start/end)
  
  // Back/Cancel handling:
  //   - WillPopScope / PopScope: if _modified, show "Discard changes?" dialog
  
  // Save action:
  //   - edit: service.updateChunk() → pop with result
  //   - add: service.addChunk() → pop with result
  //   - split: get cursor position from controller.selection.baseOffset → service.splitChunk() → pop with result
}
```

### File 5: NEW `frontend/lib/screens/manual_assistant/widgets/chunk_card.dart`

Chunk list item widget.

```dart
class ChunkCard extends StatelessWidget {
  final Map<String, dynamic> chunk;
  final bool selectionMode;
  final bool selected;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSplit;
  final VoidCallback? onMerge; // null if isLast
  final ValueChanged<bool?>? onSelectChanged;
  
  // Layout:
  //   Card with:
  //     - If selectionMode: Checkbox on the left
  //     - Header row: "#N" badge + "Page X" (or "No page") + PopupMenuButton on right
  //     - Content: Text preview, maxLines: 3, overflow: ellipsis
  //     - PopupMenu items: Edit, Delete, Split, Merge with next (if !isLast)
}
```

---

## Styling Notes

- Follow the existing app's visual style — the Knowledge tab uses basic `ListTile` with Material styling
- Use `Card` with slight elevation for chunk cards to distinguish them from the parent list
- Use the app's existing color scheme from `frontend/lib/theme/app_theme.dart`
- Show loading indicators (CircularProgressIndicator) during async operations
- Show SnackBars for success/error feedback after operations
- Use `ScaffoldMessenger.of(context).showSnackBar(...)` for notifications

## Edge Cases to Handle

1. **Empty manual** (0 chunks after all deleted) — show empty state with "Add Chunk" prompt
2. **Single chunk** — disable "Merge with next" 
3. **Split at start/end** — disable split button if cursor at position 0 or content.length
4. **Concurrent edits** — not a concern (single admin user), but reload list after each mutation
5. **Large chunks** — TextField should be scrollable; no max length enforced
6. **Re-embed failure** — if Ollama is down, the update/add/split/merge endpoint should still save the text but return a warning that embedding failed (don't block the save)
7. **Pagination after delete** — if deleting the last item on a page, go to previous page

## Testing

1. Upload a manual with multiple chunks
2. Navigate to chunk editor, verify paginated list
3. Edit a chunk, verify text updates and new content appears in AI search results
4. Add a new chunk, verify it appears at the correct position
5. Split a chunk, verify two chunks created with correct content
6. Merge two chunks, verify combined content
7. Bulk delete, verify re-indexing
8. Re-embed all, verify it completes without error
9. Test admin-only access: non-admin user should get 403

## Do NOT

- Do NOT create any new database migration files — the `manual_chunks` table already exists
- Do NOT modify the existing `manual_rag_service.py` — all chunk CRUD goes directly through the Supabase client in the router
- Do NOT return embedding vectors in any API response (they are 768 floats each)
- Do NOT add any new Flutter packages — everything needed is already in pubspec.yaml
- Do NOT change the existing upload or delete manual endpoints
