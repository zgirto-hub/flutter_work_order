# Phase 0 Research: Validated-QA Lookup Stability

**Branch**: `067-validated-qa-lookup-stability`
**Date**: 2026-04-15

## Context

The spec identifies the root cause: `validated_qa_service.check_validated_match(search_query, ...)` is invoked in `manual_rag_service.ask(...)` *after* `_rewrite_query(question, history)` has already mutated the user's raw question using accumulated conversation context. When history grows across turns, the rewriter produces different vectors for the same raw question, so the pre-calibrated similarity threshold sometimes clears and sometimes doesn't — hence the observed alternating hit/miss pattern.

This research phase resolves three open questions that determine the minimal safe fix.

---

## Decision 1: Add a pre-rewrite lookup; keep the post-rewrite lookup

**Decision**: Insert a new validated-QA lookup using the raw `question` string *before* the `_rewrite_query(...)` call. If it returns `match_type == "direct"`, short-circuit and return the cached answer. Otherwise, continue into the existing pipeline untouched — including the existing post-rewrite validated-QA check at [backend/services/manual_rag_service.py:820](../../backend/services/manual_rag_service.py#L820).

**Rationale**:
- The comment at `manual_rag_service.py:793-795` explicitly says rewrite must happen before cache check *so context-dependent follow-ups like "in english" get expanded*. That reasoning is still valid for the miss path — don't remove the post-rewrite lookup.
- Self-contained questions (95% of asks, per observation) are already fully qualified and don't need history context to resolve. For them, the raw-question lookup is correct and fast.
- Context-dependent follow-ups ("any other steps?", "in english") will miss the pre-rewrite lookup (low similarity to any standalone cached question), fall through to rewrite, and hit the existing post-rewrite lookup — preserving today's behavior for that case.
- Net effect: hits get faster and consistent; misses behave identically to today.

**Alternatives considered**:
- *Replace* post-rewrite lookup with pre-rewrite only. **Rejected** — would reintroduce the context-dependent-pollution bug that commit b25ec13 partly addressed and break the "in english" follow-up case.
- Lookup against *both* raw and rewritten queries in parallel, return highest-scoring. **Rejected** — adds a second embed call unconditionally, doubles cache-lookup latency for the miss path with no clear benefit. Early-return is simpler.
- Change `_rewrite_query` to preserve raw-question semantics better. **Rejected** — out of scope, doesn't address the layering, and would add LLM-prompt engineering risk far larger than this fix.

---

## Decision 2: No changes to `validated_qa_service` or the RPC

**Decision**: Call the existing `validated_qa_service.check_validated_match(raw_question, detected_system=detected_system)` as-is. Do not modify the service, the `search_validated_qa` RPC, the threshold, or the embedding pipeline.

**Rationale**:
- The spec's FR-007 is explicit: read-path only.
- Current threshold is calibrated against raw-question-like inputs (since users type raw questions). Running the lookup against the *rewritten* query was the accidental layering — the threshold itself is correct.
- Zero schema/RPC change keeps the blast radius small and the rollback trivial (revert one file).

**Alternatives considered**:
- Add a `lookup_strategy` parameter to `check_validated_match`. **Rejected** — YAGNI. The caller knows whether it's pre- or post-rewrite; no need for the service to care.
- Create a separate `check_raw_validated_match` function. **Rejected** — would duplicate logic. Same function, different caller-supplied query text is sufficient.

---

## Decision 3: System-filter (`detected_system`) is passed on pre-rewrite lookup too

**Decision**: Pass `detected_system` to the pre-rewrite `check_validated_match` call, using `detect_system(question)` run against the raw question.

**Rationale**:
- Commit b25ec13's fix (spec 065) established that cross-system false matches are a real risk — a bare "in english" in a session that had been discussing system X could match a cached answer for system Y. The `detected_system` filter at the service layer rejects those.
- Even pre-rewrite, if the raw question mentions a system keyword (e.g., "AIDA NG password"), we want that scoping applied.
- Cost is negligible: `detect_system` is a keyword scan, <1 ms.

**Alternatives considered**:
- Skip system detection on the pre-rewrite path. **Rejected** — creates a window where pre-rewrite lookup could cross-match, undoing b25ec13's defense. Not worth the risk.

---

## Performance analysis

**Cache-hit path (the wins)**:
- Before: embed(rewritten_query) ~300 ms + rewrite ~8 s + (on miss) HyDE ~11 s + retrieval ~3 s + generation ~1 s = 20–25 s worst case
- After: embed(raw_question) ~300 ms + vector search ~500 ms = **<1 s**
- Net saving on hit: ~20 s

**Cache-miss path (cost)**:
- Before: 0 ms added before rewrite
- After: +1 embed call (~300 ms) + 1 RPC call (~500 ms) = **~800 ms added**
- Acceptable: misses are already 20+ s end-to-end; sub-1 s addition is ~4% increase.

**Worst case (miss on both raw and rewritten)**:
- +800 ms over today's miss path
- Still bounded by existing generator timeouts

---

## Behavioral test matrix

| Scenario | Raw lookup | Post-rewrite lookup | Expected flow |
|---|---|---|---|
| Known cached question, fresh session | HIT | — (skipped) | Return cached answer, ~1 s |
| Known cached question, 5 turns deep | HIT | — (skipped) | Return cached answer, ~1 s (fixes bug) |
| Context-dependent follow-up ("in english") | MISS | HIT or MISS depending on context | Today's behavior preserved |
| Genuinely unknown question | MISS | MISS | Full RAG, today's miss path + ~800 ms |
| Cross-system false-match risk | MISS (system filter rejects) | MISS | Safe; no regression of b25ec13 |

---

## Open questions resolved

- **Q**: Does the pre-rewrite lookup need its own threshold? **A**: No — same threshold works, since it was originally calibrated against raw-question-like inputs.
- **Q**: Should we log pre- vs post-rewrite hits separately? **A**: Add a log field `vqa_hit_source: "pre_rewrite" | "post_rewrite"` for observability, but no new `user_activity_log` category. Same existing "ask_the_ai" event with the existing `source: "validated_qa"` tag.
- **Q**: What about `detect_system` on bare follow-ups like "in english"? **A**: Returns `None` — which is fine. The pre-rewrite lookup will then miss on similarity anyway (the question is too short/generic), and the existing post-rewrite path handles it as today.

**Status**: All NEEDS CLARIFICATION resolved. Ready for Phase 1.
