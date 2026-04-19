# API Contracts: RAG Refusal Diagnostic Logging

**Feature**: 088-rag-refusal-diagnostic | **Date**: 2026-04-19

Two surfaces:

1. **Modified**: `POST /api/manuals/ask` gains an optional `source` field on the request body. No change to the response schema — the per-stage diagnostic data is written to Supabase, not returned to the caller.
2. **New**: `GET /api/admin/rag-diagnostics` and `GET /api/admin/rag-diagnostics/summary`, plus `GET /api/admin/rag-diagnostics/health` and `GET /api/admin/rag-diagnostics/export`. All admin-only.

---

## 1. Modified — `POST /api/manuals/ask`

### Request body (Pydantic `AskRequest`)

```json
{
  "question": "lost ats admin pw, how to reset",
  "user_email": "test@quality-check.local",
  "history": [],
  "manual_id": null,
  "model": null,
  "session_summary": null,
  "source": "test_suite"
}
```

Only the `source` field is new:

| Field | Type | Required | Default | Allowed values |
|---|---|---|---|---|
| `source` | string | no | `"user"` | `"user"` \| `"test_suite"` \| `"internal"` |

**Backward compatibility**: absent `source` resolves to `"user"`. All existing production callers (the Flutter frontend) do NOT need to be modified. The RAG quality test suite MUST be updated to set `source: "test_suite"` in its payload.

### Response body

**Unchanged** from current behaviour. Diagnostic data is written to `rag_diagnostic_log` server-side, never sent to the client. This preserves FR-013 and simplifies the contract — admin retrieves diagnostic data via the dedicated admin endpoints below.

### Status codes

Unchanged: `200`, `400` (validation), `500` (pipeline error). A `500` from the pipeline STILL produces a diagnostic entry with `decision='error'`, `reason_code='pipeline_error'`.

---

## 2. New — `GET /api/admin/rag-diagnostics`

Admin-only paginated list of diagnostic entries with filters.

### Authorization

- Requires `Authorization: Bearer <jwt>` with `role: admin`.
- Returns `403` otherwise.

### Query parameters

| Param | Type | Default | Notes |
|---|---|---|---|
| `source` | `user \| test_suite \| internal` | (all) | Filter by request source tag |
| `decision` | `grounded \| ungrounded \| error` | (all) | Filter by final decision |
| `reason_code` | one of the six enum values | (all) | Filter by reason code |
| `from` | ISO-8601 timestamp | `now - 24h` | Start of time window (inclusive) |
| `to` | ISO-8601 timestamp | `now` | End of time window (exclusive) |
| `limit` | integer | 50 | Max 200 |
| `offset` | integer | 0 | Pagination cursor |

### Response

```json
{
  "entries": [
    {
      "id": "uuid",
      "created_at": "2026-04-19T14:23:01.234Z",
      "user_email": "tech@example.com",
      "source": "user",
      "question_raw": "lost ats admin pw, how to reset",
      "decision": "ungrounded",
      "reason_code": "rerank_below_threshold",
      "reason_note": "top rerank score 0.41 below threshold 0.55",
      "provider_used": "gemini",
      "latency_breakdown": { "total_ms": 1834, "retrieval_ms": 120, "...": "..." }
    }
  ],
  "total": 57,
  "limit": 50,
  "offset": 0
}
```

The list response omits `pipeline_stages` and `thresholds` for bandwidth reasons — these are heavy JSONB payloads. Callers fetch the full entry via `GET /api/admin/rag-diagnostics/{id}` (below).

---

## 3. New — `GET /api/admin/rag-diagnostics/{id}`

Admin-only single-entry fetch with full detail.

### Response

```json
{
  "id": "uuid",
  "created_at": "2026-04-19T14:23:01.234Z",
  "user_email": "tech@example.com",
  "source": "user",
  "question_raw": "lost ats admin pw, how to reset",
  "decision": "ungrounded",
  "reason_code": "rerank_below_threshold",
  "reason_note": "top rerank score 0.41 below threshold 0.55",
  "pipeline_stages": { "...full JSONB payload..." },
  "thresholds": { "max_chunk_distance": 0.55, "verbatim_match_min": 0.85 },
  "latency_breakdown": { "...": "..." },
  "provider_used": "gemini"
}
```

Returns `404` if no entry with that id (or admin lacks RLS visibility, though RLS is redundant here since the endpoint already requires admin auth).

---

## 4. New — `GET /api/admin/rag-diagnostics/summary`

Admin-only grouped counts for the summary panel (User Story 2).

### Query parameters

| Param | Type | Default | Notes |
|---|---|---|---|
| `source` | enum | (all) | Filter |
| `from` | ISO-8601 | `now - 24h` | Start |
| `to` | ISO-8601 | `now` | End |

### Response

```json
{
  "from": "2026-04-18T14:00:00Z",
  "to": "2026-04-19T14:00:00Z",
  "total_requests": 612,
  "by_decision": {
    "grounded": 318,
    "ungrounded": 287,
    "error": 7
  },
  "by_reason_code": {
    "grounded_answer": 298,
    "verbatim_answer": 14,
    "short_circuited_no_rag": 6,
    "no_chunks_retrieved": 9,
    "rerank_below_threshold": 204,
    "generator_refused_with_chunks": 74,
    "pipeline_error": 7
  }
}
```

Counts always sum to `total_requests` within each group. Missing reason codes (zero entries in the window) are present with value `0` so client code can rely on the shape.

**Performance**: single SQL GROUP BY over the `(reason_code, created_at)` and `(decision, created_at)` indexes; MUST complete in under 3 s at full retention volume (SC-003).

---

## 5. New — `GET /api/admin/rag-diagnostics/export`

Admin-only CSV export of grouped counts for the currently-applied filter (User Story 2 scenario 2).

### Query parameters

Same as `/summary`.

### Response

- `Content-Type: text/csv`
- Filename via `Content-Disposition: attachment; filename="rag-diagnostics-summary-<from>-to-<to>.csv"`
- Body:

```csv
reason_code,count
grounded_answer,298
verbatim_answer,14
short_circuited_no_rag,6
no_chunks_retrieved,9
rerank_below_threshold,204
generator_refused_with_chunks,74
pipeline_error,7
```

CSV-only per research.md R-04. No JSON or Markdown alternatives.

---

## 6. New — `GET /api/admin/rag-diagnostics/health`

Admin-only health endpoint for the logging subsystem (FR-014 escalation channel).

### Response

```json
{
  "in_process_write_failures_last_hour": 0,
  "last_successful_write_at": "2026-04-19T14:22:58.012Z",
  "retention_job_last_run_at": "2026-04-19T03:15:00.000Z",
  "retention_job_rows_deleted_last_run": 342
}
```

Used by the admin UI's diagnostic tab to display a small status indicator. If `in_process_write_failures_last_hour > 0` or `last_successful_write_at > 1 hour ago`, the UI MUST show a visible warning. This is the only signal admins get that logging itself is broken — the user flow is intentionally unaffected.

---

## Error responses

All endpoints follow the existing project convention:

```json
{ "detail": "short human-readable error message" }
```

Status codes: `400` (validation), `401` (missing/invalid auth), `403` (non-admin), `404` (entry not found), `500` (server error).

---

## Contract validation tests (referenced in tasks.md)

For each endpoint, a pytest test in `backend/tests/test_admin_rag_diagnostics.py` that:

1. Asserts the response schema matches the contracts above (field presence + types).
2. Asserts the admin guard — non-admin JWT returns `403`.
3. Asserts the filter semantics — `?decision=ungrounded` returns only rows with that decision.
4. Asserts CSV shape — exported file has the expected header row and a count column that sums to the filtered total.

No integration with the live backend is needed for these — they run against a test FastAPI app with a seeded in-memory or test-Supabase fixture.
