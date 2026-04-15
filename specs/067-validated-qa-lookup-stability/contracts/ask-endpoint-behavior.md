# Behavioral Contract: `/manuals/ask` cache-hit path

**Branch**: `067-validated-qa-lookup-stability`
**Scope**: Internal behavioral contract — no request/response schema changes.

## HTTP contract (unchanged)

- **Endpoint**: `POST /manuals/ask`
- **Request**: same payload as today (question, history, optional filters).
- **Response shape on cache hit**: identical to today's `validated_qa` hit response — `answer`, `is_verified: true`, `verified_source: {validated_qa_id, validated_by, validated_at, similarity}`, `sources: []`, `model: "validated_qa"`.
- **Response shape on miss**: identical to today's miss/grounded response.

This feature **does not alter the response schema**. Existing frontend code continues to work unchanged.

## Internal behavioral contract (what changes)

### Before this feature

```
receive question
  → run _rewrite_query(question, history)  [~8 s average]
  → check_validated_match(rewritten_query)
    → HIT: return cached answer
    → CONTEXT match: set validated_context, continue
    → MISS: continue
  → HyDE → retrieval → rerank → generation
```

### After this feature

```
receive question
  → detect_system(question)
  → check_validated_match(question, detected_system)   [NEW — raw-question lookup]
    → HIT: return cached answer immediately              [NEW — fast path, ~1 s]
    → MISS/CONTEXT: fall through
  → run _rewrite_query(question, history)
  → check_validated_match(rewritten_query, detected_system)  [existing, unchanged]
    → HIT: return cached answer
    → CONTEXT match: set validated_context, continue
    → MISS: continue
  → HyDE → retrieval → rerank → generation
```

## Invariants

- **INV-1 (idempotence across history)**: For any self-contained raw question Q with a validated_qa entry above threshold, the response must be identical regardless of the number of prior turns in `history`.
- **INV-2 (no regression on context-dependent follow-ups)**: For any raw question R that is not self-contained (e.g., "in english", "any other steps?"), the pre-rewrite lookup must miss and the pipeline must proceed to the existing rewrite + post-rewrite-lookup path, producing the same behavior as before this feature.
- **INV-3 (system filter preserved)**: Cross-system matches rejected by today's post-rewrite call must also be rejected by the new pre-rewrite call. The `detected_system` argument is passed identically to both.
- **INV-4 (read-only on validated_qa)**: No inserts, updates, or deletes to `validated_qa` occur as a result of this path. (FR-007)
- **INV-5 (audit preserved)**: Cache-hit responses continue to produce the existing `user_activity_log` entry with `source: "validated_qa"` — whether the hit came from pre-rewrite or post-rewrite lookup. (FR-006)

## Observable signals

Add a log field (not a response field) to distinguish hit sources for debugging:

- `logger.info("validated_qa hit (pre-rewrite)", extra={...})` on new fast-path hit.
- `logger.info("validated_qa hit (post-rewrite)", extra={...})` on existing path hit.

No new metrics dashboards; these are grep-able logs for troubleshooting.

## Non-contract (explicitly out of scope)

- No change to embedding model or dimensionality.
- No change to similarity threshold.
- No change to `validated_qa_service.check_validated_match` signature or body.
- No change to `_rewrite_query`, HyDE, retrieval, rerank, or generation.
- No change to frontend rendering of Verified Answer cards.
