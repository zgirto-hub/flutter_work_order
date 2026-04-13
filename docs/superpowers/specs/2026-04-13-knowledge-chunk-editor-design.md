# Knowledge Chunk Editor — Design Spec

**Date**: 2026-04-13  
**Feature**: View and edit individual chunks of uploaded knowledge documents  
**Scope**: Full-stack (Flutter frontend + FastAPI backend)

## Summary

Add a chunk editor screen accessible from the Knowledge tab in "Ask the AI". Admin users can tap a manual to view its chunks in a paginated list, then edit text, delete, add new chunks, split a chunk at a cursor position, and merge adjacent chunks. Every mutation auto re-embeds affected chunks, with an additional batch re-embed button for bulk operations.

## Constraints

- Admin-only access (consistent with existing upload/delete)
- 15GB server RAM — re-embedding must be sequential, not parallel
- Ollama nomic-embed-text for 768-dim embeddings (existing)
- PWA primary target — must work well on tablet/mobile

## Navigation & Chunk List View

**Entry point:** Tapping a manual card in the Knowledge tab navigates to `ChunkEditorScreen`. The card itself becomes tappable; the existing delete icon remains on the right.

**ChunkEditorScreen:**
- **AppBar** — manual title, with "Add Chunk" (+) and "Re-embed All" (sync) icon buttons
- **Body** — paginated list of chunk cards, 20 per page
- **Bottom** — page navigation: Previous / Page X of Y / Next

**Chunk card contents:**
- Header row: chunk index (e.g. "#1") + source page (e.g. "Page 3")
- Text preview: first ~150 characters, truncated with ellipsis
- Overflow menu (three dots): Edit, Delete, Split, Merge with next

**Multi-select:** Long-press enters selection mode with checkboxes. A floating action bar appears at the bottom with "Delete Selected".

## Chunk Edit/Detail Screen

**Triggered by:** Tapping "Edit" from overflow menu, or tapping the chunk card.

**Opens as:** Full-screen pushed route (not bottom sheet — chunk text can be long).

**Layout:**
- **AppBar** — "Edit Chunk #N" with Save and Cancel actions
- **Metadata row** (read-only) — source page, chunk index, live character count
- **Text field** — large multiline TextField, pre-filled, auto-focused, scrollable
- **Bottom bar** — Cancel and Save buttons

**Save behavior:**
1. PUT to backend with updated text
2. Backend updates `manual_chunks.content`
3. Backend re-generates embedding via Ollama
4. Returns updated chunk
5. List refreshes with new preview

**Unsaved changes guard:** If text modified and user taps Cancel/back, confirmation dialog: "Discard changes?" — Discard / Keep Editing.

## Split Operation

**Triggered by:** "Split" from overflow menu.

**UI:** Split editor screen showing full chunk text in a TextField. User places cursor at split point, taps "Split Here" button.

**Backend:**
- Creates two chunks from the original at the cursor position
- Re-indexes all subsequent chunks
- Auto-embeds both new chunks
- Returns updated chunk list

## Merge Operation

**Triggered by:** "Merge with next" from overflow menu (disabled/hidden on last chunk).

**UI:** Confirmation dialog previewing combined text (chunk N + "\n\n" + chunk N+1).

**Backend:**
- Combines two chunks into one
- Re-indexes subsequent chunks
- Auto-embeds the merged chunk
- Returns updated chunk list, chunk count decreases by 1

## Add New Chunk

**Triggered by:** "Add Chunk" button in AppBar.

**UI:** Same editor screen as edit, but empty. Includes a dropdown: "Insert after chunk #__" (defaults to last).

**Backend:**
- Inserts new chunk at specified position
- Re-indexes subsequent chunks
- Auto-embeds the new chunk
- Increments manual's chunk_count

## Re-embed

**Auto (per chunk):** Every save/split/merge/add triggers embedding regeneration server-side. Frontend shows loading indicator on the affected chunk card.

**Batch "Re-embed All":** AppBar button triggers background task re-embedding every chunk in the manual. Returns immediately with toast: "Re-embedding X chunks in background..."

## Backend API

All endpoints admin-only, under existing `/manuals` router:

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/manuals/{manual_id}/chunks?page=1&page_size=20` | Paginated chunk list |
| GET | `/manuals/{manual_id}/chunks/{chunk_id}` | Single chunk detail |
| PUT | `/manuals/{manual_id}/chunks/{chunk_id}` | Edit chunk text, auto re-embed |
| DELETE | `/manuals/{manual_id}/chunks/{chunk_id}` | Delete chunk, re-index |
| POST | `/manuals/{manual_id}/chunks` | Add new chunk (body: content, insert_after), auto embed |
| POST | `/manuals/{manual_id}/chunks/{chunk_id}/split` | Split at position, re-index, embed both |
| POST | `/manuals/{manual_id}/chunks/{chunk_id}/merge` | Merge with next, re-index, embed merged |
| POST | `/manuals/{manual_id}/chunks/re-embed` | Batch re-embed all (background task) |
| DELETE | `/manuals/{manual_id}/chunks/bulk-delete` | Bulk delete (body: chunk_ids[]), re-index |

## Re-indexing Logic

After any operation changing chunk count, backend re-numbers `chunk_index` values sequentially for all chunks in that manual. Updates `manuals.chunk_count` via COUNT query.

## Frontend Changes

**New files:**
- `frontend/lib/screens/manual_assistant/chunk_editor_screen.dart` — paginated chunk list
- `frontend/lib/screens/manual_assistant/chunk_edit_screen.dart` — edit/add/split editor
- `frontend/lib/screens/manual_assistant/widgets/chunk_card.dart` — chunk list item

**Modified files:**
- `frontend/lib/screens/manual_assistant/manuals_tab.dart` — make manual cards tappable, navigate to ChunkEditorScreen
- `frontend/lib/services/manual_assistant_service.dart` — add chunk CRUD methods
- `backend/routers/manuals.py` — add 9 new endpoints

**No new models needed** — chunk data uses the existing `manual_chunks` table structure. Frontend can use a simple map/class for chunk data.

## File Structure

```text
frontend/lib/screens/manual_assistant/
├── manual_assistant_screen.dart    # Existing (unchanged)
├── manuals_tab.dart                # Modified: cards now tappable
├── chat_tab.dart                   # Existing (unchanged)
├── review_queue_tab.dart           # Existing (unchanged)
├── chunk_editor_screen.dart        # NEW: paginated chunk list
├── chunk_edit_screen.dart          # NEW: edit/add/split editor
└── widgets/
    ├── upload_dialog.dart          # Existing (unchanged)
    ├── chunk_card.dart             # NEW: chunk list item widget
    └── ...existing widgets

backend/routers/
└── manuals.py                      # Modified: 9 new chunk endpoints
```
