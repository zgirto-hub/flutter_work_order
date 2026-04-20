# Contracts — Routes Being REMOVED (Story 2)

**Feature**: Spec 090, Delete Legacy `manuals` Table & Dead Code
**Scope**: Every FastAPI route removed by Story 2. All are admin-gated today; every response becomes `404 Not Found` after removal.

Line numbers refer to `main` as of this spec's creation (2026-04-20) and are approximate — use them for navigation, not diff targeting.

---

## `backend/routers/manuals.py` — CRUD routes on the `manuals` / `manual_chunks` tables

| HTTP verb | Path | Handler | Line | What it does today |
|---|---|---|---:|---|
| GET    | `/manuals/` | `list_manuals` | 209 | Returns `manuals` table rows. Empty in prod. |
| POST   | `/manuals/upload` | `upload_manual` | 258 | Accepts a PDF/DOCX/TXT/MD file, parses, chunks, embeds, writes to `manuals` + `manual_chunks` via `create_manual_with_chunks` RPC. |
| DELETE | `/manuals/{manual_id}` | `delete_manual` | 349 | Deletes one `manuals` row via `delete_manual_with_stats` RPC (cascade deletes `manual_chunks`). |
| GET    | `/manuals/{manual_id}/chunks` | `list_chunks` | 2244 | Paginated list of `manual_chunks` rows for one manual. |
| POST   | `/manuals/{manual_id}/chunks` | `add_chunk` | 2300 | Inserts a new chunk. |
| GET    | `/manuals/{manual_id}/chunks/{chunk_id}` | `get_chunk` | 2391 | Returns one chunk. |
| PUT    | `/manuals/{manual_id}/chunks/{chunk_id}` | `update_chunk` | 2416 | Edits content and re-embeds. |
| DELETE | `/manuals/{manual_id}/chunks/{chunk_id}` | `delete_chunk` | 2467 | Deletes one chunk and renumbers siblings. |
| POST   | `/manuals/{manual_id}/chunks/{chunk_id}/split` | `split_chunk` | 2491 | Splits a chunk into two. |
| POST   | `/manuals/{manual_id}/chunks/{chunk_id}/merge` | `merge_chunk` | 2620 | Merges a chunk with the next one. |
| POST   | `/manuals/{manual_id}/chunks/re-embed` | `re_embed_all` | 2147 | Re-embeds every chunk of one manual with the current embedding model. |
| DELETE | `/manuals/{manual_id}/chunks/bulk-delete` | `bulk_delete_chunks` | 2219 | Deletes N chunks of a manual in one request. |

Post-Story-2 behavior: every handler above is removed from the router. FastAPI returns `404 Not Found` for the path (because the prefix `/manuals` still has *other* registered routes, FastAPI responds with the standard auto-generated 404).

---

## `backend/routers/documents.py` — legacy-manual migration helpers

| HTTP verb | Path | Handler | Line | What it does today |
|---|---|---|---:|---|
| POST   | `/migrate-all` | `migrate_all_documents` | 181 | Spawns a background task that walks `manuals` table rows, copies each into `knowledge_documents`, and runs `index_document()`. Polled by the frontend migration UI. |
| GET    | `/migration-status` | `get_migration_status` | 268 | Returns the in-memory `_migration_status` dict (progress, current item, failed list). |
| DELETE | `/migrate-cleanup` | `migrate_cleanup` | 274 | After a successful migration, wipes `manual_chunks` + `manuals` + resets `manual_corpus_stats`. Also emits an activity-log entry. |

Post-Story-2 behavior: all three handlers plus the `_run_migration` helper and the module-level `_migration_status` state are removed. Any in-flight background task started before the deploy completes naturally (Python will finish the already-dispatched `_run_migration` coroutine); the state is simply inaccessible via HTTP afterwards.

---

## Backend services being removed or trimmed

| File | Disposition | Reason |
|---|---|---|
| `backend/services/manual_parser.py` | RETAIN (audit correction) | Also imported by `services/document_service.py` (line 31) for the live knowledge-documents parsing pipeline. Originally flagged for deletion but cannot be removed. |
| `backend/services/manual_storage_service.py` | DELETE whole file | Only caller is `manual_rag_service.py` upload/delete paths (being removed in this story). Saves/deletes files under `backend/uploaded_files/manuals/`. **Note**: the directory itself remains because `knowledge_documents` also uses it via a different save path. |
| `backend/services/manual_rag_service.py` | TRIM | Remove `upload_manual`, `delete_manual`, `manual_corpus_stats` reads/writes, `create_manual_with_chunks` / `delete_manual_with_stats` RPC callsites. Keep all ask-path helpers (context building, chunk search via `document_chunks`, prompt formatting, generator invocation, HyDE, reranking, session summary, etc.). |
| `backend/scripts/backfill_validated_qa_manual_ids.py` | DELETE whole file | One-shot backfill, already run in prod; preserved in git history. |

---

## Client call sites that will 404 after Story 2 (removed in Story 1 first)

| Frontend caller (file:line) | URL it hits |
|---|---|
| `manual_assistant_service.dart:125` | `GET /manuals/` |
| `manual_assistant_service.dart:155` | `POST /manuals/upload` |
| `manual_assistant_service.dart:429` | `DELETE /manuals/{manual_id}` |
| `manual_assistant_service.dart:732` | `GET /manuals/{manual_id}/chunks` |
| `manual_assistant_service.dart:747, 779` | `GET /manuals/{manual_id}/chunks/{chunk_id}` |
| `manual_assistant_service.dart:762` | `DELETE /manuals/{manual_id}/chunks/{chunk_id}` |
| `manual_assistant_service.dart:793` | `POST /manuals/{manual_id}/chunks` (add_chunk) |
| `manual_assistant_service.dart:815` | `POST /manuals/{manual_id}/chunks/{chunk_id}/split` |
| `manual_assistant_service.dart:833` | `POST /manuals/{manual_id}/chunks/{chunk_id}/merge` |
| `manual_assistant_service.dart:850` | `POST /manuals/{manual_id}/chunks/re-embed` |
| `manual_assistant_service.dart:866` | `DELETE /manuals/{manual_id}/chunks/bulk-delete` |
| `documents_tab.dart:438` | `GET /manuals/count?user_email=…` — **NOTE**: audit finding — no backend handler exists for `/manuals/count` today. The frontend `_checkOldManuals` call already receives a non-200 response and silently returns `0`, which is why the "Old manuals" block always shows zero in production. Story 1 removes the dead caller; nothing else changes on the backend. |

Story 1 removes every caller in this table **from the frontend** so that by the time Story 2 deletes the backend routes, no client is pointing at them.

---

## Database objects removed by Story 3

See [data-model.md](../data-model.md) for the full list — three tables, three RPC functions, one FK constraint, one column.
