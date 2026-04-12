# API Contract: `/api/manuals/*`

Four endpoints exposed by `backend/routers/manuals.py`. All endpoints require a valid `Authorization: Bearer <supabase_jwt>` header and are accessible to all three roles (`reporter`, `technician`, `admin`) per [FR-001](../spec.md) and [Assumptions](../spec.md).

Base URL: `${API_BASE_URL}/api/manuals` (resolved per existing `frontend/lib/config.dart` conventions).

---

## 1. `POST /api/manuals/upload`

Upload a new manual. This is the most complex endpoint: parse → chunk → embed → store → persist.

### Request

**Content-Type**: `multipart/form-data`

| Field | Type | Required | Constraints |
|---|---|---|---|
| `file` | file (binary) | yes | MIME type MUST be one of: `application/pdf`, `application/vnd.openxmlformats-officedocument.wordprocessingml.document`, `text/plain`, `text/markdown`. Size ≤ 20 MB (per [FR-004a](../spec.md)). |
| `title` | string | yes | Non-empty after `.strip()`. ≤ 200 chars. |

### Admission checks (in order, fail-fast)

1. MIME type in the allowed set → else **415 Unsupported Media Type**.
2. `file.size ≤ 20 * 1024 * 1024` → else **413 Payload Too Large** with `{"error": "file_too_large", "limit_mb": 20}`.
3. `title.strip() != ""` → else **400** with `{"error": "title_required"}`.
4. `manual_corpus_stats.total_bytes + projected_bytes ≤ ceiling_bytes` → else **413 Payload Too Large** with `{"error": "corpus_full", "message": "The manual library is full. Delete an existing manual to make room and try again.", "ceiling_mb": <configured>}`.
5. For PDFs: at least 1 page with ≥20 characters of extractable text → else **422** with `{"error": "no_extractable_text"}`.
6. Page-count check for PDFs: `doc.page_count ≤ 500` → else **413** with `{"error": "too_many_pages", "limit": 500}`.

Note: checks 5–6 happen during parse (already past the file-size and title checks). Failures after step 5 do **not** leave any on-disk or DB state behind, per [FR-019b](../spec.md).

### Processing pipeline (happy path)

1. Parse with `manual_parser.py` → list of `(page_number | None, paragraph_text)` tuples.
2. Chunk with `manual_chunker.py` → list of `Chunk(chunk_index, source_page, content)` records.
3. Embed each chunk via `ollama_embedder.py` (concurrency cap 4, per research §6).
4. Allocate a new UUID for the manual (`manual_id = uuid4()`).
5. Write the original file to `backend/uploaded_files/manuals/<manual_id>.<ext>` via `manual_storage_service.save(manual_id, file_bytes, extension)`.
6. Open a Supabase transaction:
   - `INSERT` into `manuals` with the computed fields.
   - `INSERT` all chunks into `manual_chunks` in a single batch.
   - `UPDATE manual_corpus_stats SET total_bytes = total_bytes + projected_bytes, manual_count = manual_count + 1, updated_at = now() WHERE id = 1`.
7. On any exception during step 6, `os.unlink(disk_path)` then re-raise as **500**.
8. Fire-and-forget audit log: `activity.log(user_id, category='file', action='uploaded_manual', details={...})`.

### Response

**200 OK** (on success):

```json
{
  "manual_id": "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
  "title": "Caterpillar D11 Hydraulic System",
  "file_name": "caterpillar_d11_hyd.pdf",
  "file_extension": "pdf",
  "file_size_bytes": 18423901,
  "chunk_count": 423,
  "created_at": "2026-04-11T14:22:07.412Z"
}
```

**Error responses** (in addition to the ones listed in admission checks):

| Code | When | Body |
|---|---|---|
| 401 | Missing/invalid JWT | `{"error": "unauthenticated"}` |
| 422 | Parse succeeded but chunker produced 0 chunks (e.g. file was only whitespace) | `{"error": "no_content_after_chunking"}` |
| 504 | Ollama embedding timeout | `{"error": "embedder_unavailable", "message": "The embedding service is temporarily unavailable. Please try again in a moment."}` |
| 500 | Disk write or DB transaction failure | `{"error": "upload_failed", "message": "Something went wrong while saving the manual. Please try again."}` |

---

## 2. `GET /api/manuals/`

List all manuals currently in the corpus. Used by the Manuals tab and by the Chat tab's filter dropdown.

### Request

No body. No query parameters in v1 (client-side filtering per constitution V).

### Response

**200 OK**:

```json
{
  "manuals": [
    {
      "id": "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
      "title": "Caterpillar D11 Hydraulic System",
      "file_name": "caterpillar_d11_hyd.pdf",
      "file_extension": "pdf",
      "file_size_bytes": 18423901,
      "uploaded_by": "51a8f9c2-2f7c-4c11-b8a4-9e28b1a6f312",
      "uploaded_by_name": "Ahmed Al-Otaibi",
      "chunk_count": 423,
      "created_at": "2026-04-11T14:22:07.412Z"
    }
  ],
  "corpus_stats": {
    "total_bytes": 87421904,
    "manual_count": 12,
    "ceiling_bytes": 419430400
  }
}
```

Sort: `created_at DESC` (most recent first). `uploaded_by_name` is resolved server-side via a join on `users`; NULL if the uploader has been deleted.

**Empty corpus**: returns `{"manuals": [], "corpus_stats": {...}}` with 200 — empty state is rendered client-side per [FR-016](../spec.md) / [FR-017](../spec.md), not via a 404.

---

## 3. `DELETE /api/manuals/{manual_id}`

Delete a manual. Cascades to chunks and removes the on-disk original per [FR-022](../spec.md).

### Request

Path param: `manual_id` (UUID). No body.

### Processing

1. Resolve the manual (read `file_extension`, `chunk_count`, compute `projected_bytes` for the stats decrement).
2. If manual does not exist → **404** with `{"error": "manual_not_found"}`.
3. Open a Supabase transaction:
   - `DELETE FROM manuals WHERE id = $1` (CASCADE removes chunks).
   - `UPDATE manual_corpus_stats SET total_bytes = total_bytes - $projected, manual_count = manual_count - 1, updated_at = now() WHERE id = 1` (clamp at 0 defensively).
4. `os.unlink(disk_path)`. If the file is already missing, log a warning and continue ([FR-022](../spec.md)).
5. Fire-and-forget audit: `activity.log(user_id, category='file', action='deleted_manual', details={...})`.

### Response

**204 No Content** on success.

**Errors**:

| Code | When | Body |
|---|---|---|
| 401 | Missing/invalid JWT | `{"error": "unauthenticated"}` |
| 404 | Unknown `manual_id` | `{"error": "manual_not_found"}` |
| 500 | DB txn failure (rare; file unlink failure is non-fatal) | `{"error": "delete_failed", "message": "Unable to delete the manual. Please try again."}` |

---

## 4. `POST /api/manuals/ask`

The core query endpoint. Embeds the question, retrieves top-k chunks, prompts Gemma, returns grounded answer + sources.

### Request

**Content-Type**: `application/json`

```json
{
  "question": "How do I purge air from the main hydraulic line?",
  "manual_id": "3f2504e0-4f89-41d3-9a0c-0305e82c3301"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `question` | string | yes | Non-empty after strip. ≤ 2000 chars. |
| `manual_id` | string \| null | no | When present: scope retrieval to this manual only, per [FR-013](../spec.md) strict-filter semantics. When null or omitted: search all manuals. |

### Admission checks

1. `question.strip() != ""` → else **400** with `{"error": "question_required"}`.
2. `len(question) ≤ 2000` → else **400** with `{"error": "question_too_long", "limit": 2000}`.
3. If `manual_id` provided, it must exist → else **404** with `{"error": "manual_not_found"}`.
4. **Corpus emptiness guard**: if the corpus (or the filtered manual) has 0 chunks, short-circuit the LLM call and return the 200 empty-response shape below with `grounded=false` and the sentinel message. Rationale: avoid a wasted Gemma call and meet the edge case from [spec.md](../spec.md) ("question before any manual has been uploaded").

### Processing pipeline

1. Embed the question via `ollama_embedder.py` (single-vector call).
2. SQL: retrieve top 5 nearest chunks by `embedding <=> $1` (cosine distance), scoped to `manual_id` if provided. Include `manuals.title` via JOIN for source labeling:
   ```sql
   SELECT mc.id, mc.manual_id, mc.chunk_index, mc.source_page, mc.content,
          m.title AS manual_title,
          (mc.embedding <=> $1) AS distance
   FROM manual_chunks mc
   JOIN manuals m ON m.id = mc.manual_id
   WHERE ($2::uuid IS NULL OR mc.manual_id = $2)
   ORDER BY mc.embedding <=> $1
   LIMIT 5;
   ```
3. Build the prompt per research §7, feeding the 5 retrieved chunks.
4. Call Gemma 4 E2B via `POST http://localhost:11434/api/generate` with `stream=false`, timeout 90s.
5. Strip the answer. Detect groundedness: if the answer **contains** the sentinel substring `"This information is not in the available manuals"` (or its Arabic equivalent), mark `grounded=false` and discard the sources. Otherwise mark `grounded=true`.
6. For each retrieved chunk (if grounded): compute highlight offsets via the Jaccard-threshold algorithm (research §8). Build a `content_preview` capped at 500 chars.
7. Fire-and-forget audit: `activity.log(user_id, category='file', action='asked_manual', details={...})`.

### Response

**200 OK** — grounded answer:

```json
{
  "answer": "To purge air from the main hydraulic line, loosen the bleeder valve at the top of the reservoir while the engine is at idle, until a steady stream of fluid appears with no bubbles. Tighten the valve. Repeat at each branch bleeder in sequence A → B → C.",
  "grounded": true,
  "sources": [
    {
      "manual_id": "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
      "manual_title": "Caterpillar D11 Hydraulic System",
      "chunk_index": 127,
      "source_page": 84,
      "content_preview": "Air purge procedure: With the engine at idle, loosen the bleeder valve at the top of the reservoir until a steady stream of fluid appears...",
      "highlight_start": 19,
      "highlight_end": 187
    }
  ]
}
```

**200 OK** — not grounded (cannot answer from the corpus):

```json
{
  "answer": "This information is not in the available manuals.",
  "grounded": false,
  "sources": []
}
```

Note the 200 on the not-grounded path: this is the assistant's correct behavior, not an error. The frontend distinguishes based on `grounded`, not HTTP status.

**Errors**:

| Code | When | Body |
|---|---|---|
| 400 | Missing/invalid question | `{"error": "question_required" or "question_too_long"}` |
| 401 | Missing/invalid JWT | `{"error": "unauthenticated"}` |
| 404 | `manual_id` does not exist | `{"error": "manual_not_found"}` |
| 504 | Ollama timeout (embedder OR generator) | `{"error": "assistant_unavailable", "message": "The assistant is taking longer than usual to respond. Please try again."}` |
| 500 | DB failure | `{"error": "ask_failed", "message": "Something went wrong while answering. Please try again."}` |

---

## Contract-test checklist

Each endpoint has a contract test in `backend/tests/routers/test_manuals.py`. The test cases below are the minimum set — they mirror the acceptance scenarios from [spec.md](../spec.md) and will drive the failing tests created in `/speckit.tasks`.

### Upload
- [ ] happy path with a small PDF → 200, row in `manuals`, chunks in `manual_chunks`, file on disk
- [ ] unsupported MIME (e.g. .zip) → 415
- [ ] 21 MB PDF → 413 `file_too_large`
- [ ] 501-page PDF → 413 `too_many_pages`
- [ ] image-only PDF (no text) → 422 `no_extractable_text`, no disk/DB residue
- [ ] empty `title` → 400 `title_required`
- [ ] corpus already at ceiling → 413 `corpus_full`
- [ ] Ollama down → 504 `embedder_unavailable`, no disk/DB residue
- [ ] simulated DB failure after disk write → 500 `upload_failed`, **file on disk removed**

### List
- [ ] empty corpus → `{"manuals": [], "corpus_stats": {...}}`
- [ ] one manual present → 1 row, correct metadata, `uploaded_by_name` joined
- [ ] `uploaded_by` user deleted → row still present with `uploaded_by_name = null`

### Delete
- [ ] happy path → 204, row gone, chunks gone (CASCADE), file unlinked, stats decremented
- [ ] missing on-disk file → 204 (logs warning), DB rows still removed
- [ ] unknown id → 404 `manual_not_found`

### Ask
- [ ] question answered from a single manual → 200, `grounded=true`, ≥1 source, source has correct manual id + page
- [ ] question whose answer is not in the manuals → 200, `grounded=false`, empty sources, sentinel answer
- [ ] empty corpus → 200 short-circuit with sentinel answer (no Ollama call)
- [ ] `manual_id` filter honored strictly: answer exists only in a different manual → 200, `grounded=false` ([FR-013](../spec.md))
- [ ] Arabic question → 200, `grounded=true`, answer in Arabic
- [ ] English question against a mixed-language manual → 200, answer in English
- [ ] `manual_id` unknown → 404
- [ ] Ollama generate timeout → 504 `assistant_unavailable`
- [ ] highlight emitted when Jaccard ≥ 0.35; otherwise `highlight_start/end = null`

---

## Rate limiting and concurrency

- No server-side rate limiting in v1 (constitution VII — YAGNI). If this becomes a problem, Nginx already has `limit_req_zone` available at the ingress.
- Concurrent embedding is capped at 4 in-process per upload (research §6) to avoid Ollama OOM.
- Concurrent `ask` requests are not artificially limited; the frontend disables the send button while a question is in flight per [FR-021](../spec.md), so accidental bursts are prevented client-side. Backend does not enforce.
