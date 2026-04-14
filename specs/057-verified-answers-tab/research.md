# Research: Verified Answers Admin Tab

## Decision: No database migration needed

- **Rationale**: The `validated_qa` table already has all required columns (id, question_text, validated_answer, question_embedding, equipment_type, fault_code, validated_by, validated_at, thumbs_up_count, thumbs_down_count, is_reflagged, rating_id, updated_at). No schema changes required.
- **Alternatives considered**: Adding a `deleted_at` column for soft delete — rejected per user decision; hard delete with `answer_ratings.review_status` reset is the chosen approach.

## Decision: Use existing `_admin_check()` for authorization

- **Rationale**: `_admin_check(user_email)` in `manuals.py:517-530` queries `users` table, raises HTTPException(403) if not admin. All three new endpoints (GET, PUT, DELETE) use this.
- **Alternatives considered**: Middleware-based auth — rejected per YAGNI; all existing manual endpoints use the same inline check pattern.

## Decision: Re-embed only when question_text changes

- **Rationale**: `embed_single()` is async and calls Ollama (localhost:11434). Only the question_text drives the embedding vector — answer text changes don't affect retrieval. Re-extracting equipment_type/fault_code also only depends on question text.
- **Alternatives considered**: Always re-embed — rejected because it adds latency and load with no benefit when only the answer changes.

## Decision: Hard delete + reset answer_ratings to pending

- **Rationale**: Hard delete removes the validated_qa row and its embedding from RAG search results immediately. Resetting the linked `answer_ratings.review_status` to `'pending'` preserves the user's original feedback and makes it available for re-review in the Review Queue.
- **Alternatives considered**: (A) Soft delete with `deleted_at` — adds query complexity for no current benefit. (B) Hard delete of both rows — loses feedback history. (C) Leave answer_ratings orphaned — creates stale data.

## Decision: ilike search on question_text

- **Rationale**: PostgreSQL `ilike` via Supabase PostgREST is sufficient for case-insensitive text search at current data volumes (hundreds of entries). No GIN trigram index needed yet.
- **Alternatives considered**: Full-text search with `to_tsvector` — overkill for v1. Vector similarity search — semantically different purpose (retrieval vs. admin browse).

## Key implementation references

| Item | Location | Details |
|------|----------|---------|
| `_admin_check()` | `manuals.py:517-530` | `_admin_check(user_email)` → HTTPException(403) |
| Pydantic model pattern | `manuals.py:398-402` | `ReviewAnswerRequest(BaseModel)` with Optional fields |
| Error handling pattern | `manuals.py:203-243` | Specific exception → HTTPException with detail dict |
| `log_activity()` pattern | `manuals.py:246-255` | Fire-and-forget in try/except, args: email, type, action, **kwargs |
| `embed_single()` | `validated_qa_service.py:7,137` | Async, returns List[float] |
| Embedding format | `validated_qa_service.py:138` | `"[" + ",".join(str(x) for x in emb) + "]"` |
| `_extract_equipment_type()` | `validated_qa_service.py:27-32` | `(text: str) -> Optional[str]` |
| `_extract_fault_code()` | `validated_qa_service.py:35-40` | `(text: str) -> Optional[str]` |
| `EmbedderTimeoutError` | `ollama_embedder.py:12-13` | Custom exception, raised on httpx timeout |
| Review Queue tab pattern | `review_queue_tab.dart` | StatefulWidget + AutomaticKeepAliveClientMixin |
| TabController setup | `manual_assistant_screen.dart:33` | `TabController(length: _isAdmin ? 5 : 2)` |
| Service GET pattern | `manual_assistant_service.dart:336-361` | `getFlaggedAnswers()` with auth headers |
| Service POST pattern | `manual_assistant_service.dart:363-398` | `reviewAnswer()` with JSON body |
