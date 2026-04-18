# Response Contract Diff: `/manuals/ask` and `/manuals/ask-stream`

**Feature**: 083-verbatim-verified-answers
**Scope**: Additive JSON fields on existing endpoints. **No endpoint surface changes, no path changes, no method changes, no deprecations.**

---

## Affected endpoints

| Endpoint | Change type |
|---|---|
| `POST /manuals/ask` (non-streaming) | Response body gains two optional fields |
| `POST /manuals/ask-stream` (SSE) | Terminal `event: metadata` JSON payload gains two optional fields |

Both share the same JSON diff. The streaming endpoint's per-token `data:` events are unchanged (they still carry raw answer text).

---

## Response JSON — before vs. after

### Before (today)

```json
{
  "answer": "To back up CADAS ATS, first ensure ...",
  "grounded": true,
  "sources": [
    {"id": "abc-123", "question_text": "how to backup cadas ats", "score": 0.92}
  ],
  "confidence": "high",
  "score": 0.92,
  "model": "gemma4:e2b",
  "provider_display_name": "Local (Ollama)",
  "duration_seconds": 12.4,
  "is_verified": true,
  "verified_source": {
    "validated_qa_id": "abc-123",
    "validated_by": "admin@example.com",
    "validated_at": "2026-04-01T10:22:15",
    "similarity": 0.92
  },
  "retrieval_info": { "...": "..." },
  "provider_used": "local",
  "fallback_used": false,
  "session_summary": null,
  "search_query": "backup cadas ats procedure",
  "latency_breakdown": { "...": "..." },
  "source_type": "validated_qa"
}
```

### After — verbatim response

```json
{
  "answer": "To back up CADAS ATS, first ensure ...",
  "grounded": true,
  "sources": [
    {"id": "abc-123", "question_text": "how to backup cadas ats", "score": 0.92}
  ],
  "confidence": "high",
  "score": 0.92,
  "model": "Verbatim (no generation)",
  "provider_display_name": "Verbatim (no generation)",
  "duration_seconds": 0.0,
  "is_verified": true,
  "verified_source": {
    "validated_qa_id": "abc-123",
    "validated_by": "admin@example.com",
    "validated_at": "2026-04-01T10:22:15",
    "similarity": 0.92
  },
  "verification_mode": "verbatim",
  "verified_source_count": 1,
  "retrieval_info": { "...": "..." },
  "provider_used": "verbatim",
  "fallback_used": false,
  "session_summary": null,
  "search_query": "backup cadas ats procedure",
  "latency_breakdown": {
    "...": "...",
    "generator_ms": 0
  },
  "source_type": "validated_qa"
}
```

### After — synthesized response

```json
{
  "answer": "To back up CADAS ATS, first ensure ...",
  "grounded": true,
  "sources": [
    {"id": "abc-123", "question_text": "how to backup cadas ats", "score": 0.90},
    {"id": "def-456", "question_text": "backup procedure cadas",  "score": 0.87},
    {"id": "ghi-789", "question_text": "back up the cadas server", "score": 0.86}
  ],
  "confidence": "high",
  "score": 0.90,
  "model": "gemma4:e2b",
  "provider_display_name": "Local (Ollama)",
  "duration_seconds": 12.4,
  "is_verified": true,
  "verified_source": {
    "validated_qa_id": "abc-123",
    "validated_by": "admin@example.com",
    "validated_at": "2026-04-01T10:22:15",
    "similarity": 0.90
  },
  "verification_mode": "synthesized",
  "verified_source_count": 2,
  "retrieval_info": { "...": "..." },
  "provider_used": "local",
  "fallback_used": false,
  "session_summary": null,
  "search_query": "backup cadas ats procedure",
  "latency_breakdown": { "...": "..." },
  "source_type": "validated_qa"
}
```

Note on the synthesized example: `sources` has 3 entries but `verified_source_count` is **2** because two of the three rows share the same underlying `validated_answer` text (per spec 068 paraphrase variants). Dedup is computed server-side per [research.md §R2](../research.md).

---

## Field additions

| Field | Type | Presence | Description |
|---|---|---|---|
| `verification_mode` | `string` enum: `"verbatim" \| "synthesized"` | Present on every `is_verified=true` response. Absent (or `null`) on non-verified responses. | Tells the client which presentation path to use. |
| `verified_source_count` | `integer ≥ 1` | Present on every `is_verified=true` response. Absent on non-verified responses. | Count of distinct underlying curated answers (dedup-by-answer-text). Always `1` on verbatim. |

### Constraints

- `is_verified == true` ⇔ both `verification_mode` and `verified_source_count` are present.
- `verification_mode == "verbatim"` ⇒ `verified_source_count == 1`.
- `verification_mode == "verbatim"` ⇒ `answer` is byte-identical to `validated_qa.validated_answer` for the row identified by `verified_source.validated_qa_id`.
- `verification_mode == "synthesized"` ⇒ `answer` is the LLM-generated text (today's behavior) and `verified_source_count` is the deduped count.

---

## Field removals / renames

**None.** All existing fields keep their current names, types, and presence rules. Older clients that don't know about `verification_mode` or `verified_source_count` will continue to parse responses correctly (they fall back to not showing the footer caption, which degrades to today's UI where every verified response looks the same).

---

## Streaming-specific notes

For `POST /manuals/ask-stream` (SSE via `EventSourceResponse`):

- The verbatim path emits **exactly one** `data:` event carrying the full stored answer text, followed by the terminal `event: metadata` event.
- The synthesis path's per-token streaming is unchanged.
- The terminal `event: metadata` JSON carries `verification_mode` and `verified_source_count` on both paths.
- No new SSE event types. No new `event:` names.

---

## Client migration

| Client | Required action |
|---|---|
| Flutter frontend (`manual_qa_answer.dart`, `answer_card.dart`) | Update model to parse new fields; update answer_card to render footer when `isVerified && verificationMode == "synthesized"`. See [data-model.md §3](../data-model.md#3-frontend-model). |
| Any future non-Flutter consumer | Optional — ignore the new fields to keep today's UX, or consume them to differentiate verbatim vs. synthesized. |

---

## Versioning

No API version bump required — changes are strictly additive and backward-compatible.
