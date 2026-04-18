# Phase 0 Research: Verbatim Verified Answers

**Feature**: 083-verbatim-verified-answers
**Date**: 2026-04-18

The spec is unusually prescriptive (exact thresholds, exact telemetry schema, exact file paths), so Phase 0 research focused on verifying each prescription against the current code rather than selecting between alternatives. Findings below.

---

## R1 — Similarity-score precision returned by `check_validated_match`

**Question**: The verbatim trigger compares against 0.85 and 0.05. What precision does the retrieval helper return?

**Finding**: `backend/services/validated_qa_service.py:314` rounds each match's similarity to **two decimal places** via `similarity = round(1.0 - match.get("distance", 1.0), 2)`.

**Decision**: Keep `VERBATIM_MIN_SIMILARITY = 0.85` and `VERBATIM_DOMINANCE_GAP = 0.05` as module-level floats. Both values are already aligned to two-decimal precision; comparisons are exact (no floating-point edge cases). Boundary cases (top1 exactly 0.85, gap exactly 0.05) pass the `>=` comparisons by design — matches the acceptance-scenario intent.

**Rationale**: Changing the retrieval helper's rounding is forbidden by FR-019; adopting a precision-compatible threshold set is simpler than introducing tolerance arithmetic.

**Alternatives considered**:
- Compare with a small epsilon (`>= 0.85 - 1e-9`). Rejected — unnecessary since `round(x, 2)` produces exact 0.01-granular values, and `>=` with 0.85 and 0.05 in IEEE-754 double works reliably at this precision.
- Request 4-decimal similarity from the helper. Rejected — would violate FR-019.

---

## R2 — Dedup strategy for N in "Synthesized from N verified sources"

**Question (per clarification Session 2026-04-18)**: N must count **distinct underlying curated answers**, deduping spec-068 paraphrase variants. How should distinctness be computed without adding `rating_id` to `check_validated_match`'s return shape (which is forbidden by FR-019)?

**Finding**: Each match row returned by `check_validated_match` contains `id` (validated_qa row PK), `question_text`, `validated_answer`, `validated_by`, `validated_at`, and `similarity` — no `rating_id`. Spec 068's contract (recorded in project memory and in spec 068 itself) is that paraphrase variants **share the same `validated_answer` text** via the shared `rating_id`.

**Decision**: Dedup by `validated_answer` string identity. Two match rows whose `validated_answer` fields are byte-equal are counted as one source. Implementation: `N = len({m["validated_answer"] for m in matches})`.

**Rationale**: Spec-068 variants are explicitly designed to share answer text, so answer-text equivalence is a sound proxy for rating_id equivalence without widening the retrieval contract. The cost is a trivial set-comprehension over at most 3 strings.

**Alternatives considered**:
- Dedup by `id`. Rejected — two variants have distinct `validated_qa` row PKs, so this would not dedup.
- Extend `check_validated_match` to return `rating_id` as an additive field. Rejected — FR-019 forbids changes to this helper.
- Fetch `rating_id` for each match via a follow-up query. Rejected — adds latency on the only path that is meant to be fast, and answer-text identity already achieves the correct semantics.

**Edge case**: Two admins independently curating the same answer text for unrelated questions would collide to N=1. Acceptable: the UI statement "from N verified sources" is about source-content distinctness, and byte-identical curated text really is a single source regardless of which row serves it.

---

## R3 — SSE ordering for the verbatim streaming path

**Question**: FR-010 says the verbatim path must emit the full answer "as a single chunk" with `verification_mode` travelling on the metadata event. The existing SSE framing in `backend/routers/manuals.py:417–491` yields zero-or-more `data:` events (each a token chunk) followed by a single `event: metadata` event at the end — so metadata arrives **after** tokens, not before. How should the verbatim path realize the FR?

**Finding**: The streaming pipeline already mutates `stream_meta` in place **before** yielding tokens (e.g., `is_verified`, `verified_source`, `sources`, `confidence` are all assigned around lines 748–766 and 842–860 before the first `provider_generate_stream` chunk). The router reads the final `stream_meta` state after the generator completes and emits it in the terminal `event: metadata` event (`manuals.py:491`).

**Decision**: The verbatim streaming path will:

1. Populate `stream_meta` with `is_verified`, `verified_source`, `source_type = "validated_qa"`, `confidence`, `sources`, **and** `verification_mode = "verbatim"` — identical to today's streaming verified path except for the new `verification_mode` key.
2. `yield` the stored `validated_answer` as a single string chunk (one `data:` event).
3. `return` without calling `provider_generate_stream`.

The router's existing terminal `event: metadata` step will carry `verification_mode=verbatim` automatically because `stream_meta` was already mutated. One small wiring change is required in `manuals.py`: the terminal `result` dict at lines 470–489 must pass through `verification_mode` from `stream_meta` so the frontend receives it in the metadata event.

**Rationale**: This preserves today's SSE framing exactly. Clients already see "tokens first, then metadata" — verbatim just happens to be a single token. FR-009 ("same metadata event that already carries `is_verified`/`verified_source`") is satisfied because all three fields land in the same terminal JSON payload.

**Spec wording clarification**: FR-010's phrase "emitted as a single chunk immediately after the metadata event" was written based on an assumed order where metadata comes first. The observable behavior the FR is really describing — "one chunk, not a token stream" — holds under the actual SSE order. No spec change is required; the plan documents the realization.

**Alternatives considered**:
- Emit a synthetic early metadata event before tokens. Rejected — changes the SSE contract for all callers, not just verbatim, and would require frontend parser changes beyond what the spec permits.
- Concatenate metadata and answer into one `data:` event (JSON-encoded). Rejected — breaks the existing token-streaming contract.

---

## R4 — log_activity plumbing from the four verified-answer paths

**Question**: FR-014 requires every is_verified=true response to call `log_activity(...)` with a specific payload. `log_activity(user_email, category, action, target_label, target_id, detail)` requires `user_email`. Is it available at each of the four call sites?

**Finding**: Inspecting `manual_rag_service.py`:

- `ask_stream(question, manual_id_filter, model, history, session_summary, user_email, latency_breakdown, stream_meta)` — `user_email` is a param. ✅ pre- and post-rewrite streaming sites both have it in scope.
- The non-streaming `ask(...)` path (~L985–1280) likewise accepts and propagates `user_email`. ✅

**Decision**: Call `log_activity` directly at each of the four is_verified=true branches, immediately after `verification_mode` is determined and just before `yield`-ing (streaming) or building the return dict (non-streaming). Wrap in `try/except Exception: pass` **even though `utils/activity.py` already swallows exceptions internally** — this is defence-in-depth against any future refactor of the helper that might remove the internal try/except, per FR-015.

Payload (per FR-014):

```python
log_activity(
    user_email,
    category="manual",
    action="verified_answer_served",
    target_label=question[:80],  # question_text, not search_query
    target_id="",
    detail=f"mode={verification_mode};top1={top1:.3f};top2={top2:.3f}",
)
```

`top2` is `0.000` when only a single match is returned (per FR-014 wording: "Use top2=0.000 when only a single match was returned").

**`target_label` choice**: Use the original `question` (the user's verbatim input), **not** the possibly-rewritten `search_query`. Rationale: post-deploy analysts want to see real user phrasings to tune the thresholds; the rewritten query is an internal artifact. Truncated to 80 characters per FR-014.

**Rationale**: Matches FR-014 verbatim, uses the existing helper without modification, and stays fire-and-forget per Constitution VI and FR-015.

**Alternatives considered**:
- Centralize the log write inside `_build_verbatim_payload` / a new `_log_verified_served` helper. **Accepted and folded into the design**: `_log_verified_served(user_email, question, verification_mode, top1, top2)` will live alongside the two spec-mandated helpers, so the four code paths stay symmetric and the payload format is defined in one place. This is a minor extra helper, but it prevents the four sites from drifting on the exact `detail` string format — directly parallel to why the spec mandates `_should_return_verbatim` and `_build_verbatim_payload`.

---

## R5 — Frontend model & widget changes are localized

**Question**: The spec names `manual_qa_answer.dart` and `answer_card.dart` as the only two frontend files that need changes. Is that accurate?

**Finding**:

- `manual_qa_answer.dart:69–165` defines `ManualQaAnswer` with no `verificationMode` field today. Adding one is additive.
- `answer_card.dart:56` reads `isVerified`; lines 104–130 render the green badge; lines 149–151 already render a "Synthesized from N manuals" label for the non-verified path (different concept, don't confuse). The new synthesis footer is a sibling block inserted when `isVerified && verificationMode == "synthesized"`.
- No other widget or model references `verification_mode` (grep confirmed: zero hits in `frontend/`).

**Decision**: Scope the frontend diff to exactly these two files. No service-layer change required because `ManualAssistantService` (or equivalent) already calls `ManualQaAnswer.fromJson` and passes the full map through; adding a field to the factory is automatically visible at the call site.

**Source count for the footer**: The frontend computes N from the server-provided `sources` array after deduping by the `score`/`question_text` pair is **not** reliable (two distinct curated Q&A rows may score identically on different questions). Instead, the **backend will send a pre-computed `verified_source_count: int`** in the response alongside `verification_mode`. This keeps dedup logic (R2) in one place and lets the frontend render the literal integer without re-implementing distinctness. `verified_source_count` is meaningful only when `verification_mode == "synthesized"`; on verbatim it is `1` (or omitted).

**Rationale**: The spec's dedup rule is server-side information the frontend doesn't have (answer-text identity requires the full answer text of every source; the `sources` array carries only `question_text` and score). Pre-computing it on the server is the cheapest correct implementation.

**Alternatives considered**:
- Send the full `validated_answer` of each source to the frontend so the client dedups. Rejected — increases response size and duplicates logic.
- Let the frontend use `sources.length` unconditionally. Rejected — would count 3 for spec-068 triple-variant matches, contradicting the Session 2026-04-18 clarification.

---

## R6 — Empty / malformed `validated_answer` on the verbatim path

**Question**: What if a curated `validated_answer` is empty or whitespace-only?

**Finding**: `check_validated_match` does not filter on answer content. The admin-curated Q&A tab (spec 080) is presumed to validate non-empty input, but the retrieval helper's contract is "return whatever the embedding search found."

**Decision**: **Out of scope** — FR-019 forbids changes to `check_validated_match`, and the spec's position is that curated answers are admin-authored and presumed user-ready. If a degenerate row somehow ships, the verbatim path will emit its (empty) text and the synthesis path would have been equally unable to produce a useful answer from empty source material. The existing data-quality safeguards at creation time in spec 080 are the right enforcement point.

**Rationale**: Adding a fallback-to-synthesis branch for empty answers would introduce hidden behavior the spec does not call for, violating Principle II (Explicit Over Automatic). If empty curated rows become a real problem, a separate spec can add a retrieval-helper filter (the correct layer to enforce it).

**Alternatives considered**:
- Fall back to synthesis when `validated_answer.strip() == ""`. Rejected per reasoning above.
- Raise an exception. Rejected — would break the verified-response path for a data-quality issue outside this feature's surface area.

---

## R7 — Interaction with spec 067 direct-lookup fast path

**Question**: Spec 067 added a direct-lookup fast path for trivially short / direct questions. Is there any interaction with this feature?

**Finding**: The direct-lookup fast path (invoked via `_is_direct_lookup(question)` around `manual_rag_service.py:778`) runs **before** the validated-QA retrieval in the flow and bypasses the entire RAG pipeline for extremely short queries. It does not set `is_verified=true`, so it is orthogonal to this feature's surface.

**Decision**: No changes to the direct-lookup path. FR-017 is a no-op requirement satisfied by simply not touching that code.

**Rationale**: The two features are independent: 067 handles "greeting/trivial input" short-circuit, 083 handles "strong curated-match" short-circuit. Both are fast paths but with disjoint triggering conditions.

---

## R8 — Unit-test surface

**Question**: The spec mandates unit tests for `_should_return_verbatim` covering six cases. Where should the test file live?

**Finding**: `backend/tests/` exists and is the home of pytest files today (verified via existing test files pattern). The helper is module-private (leading underscore) but importable from the same package.

**Decision**: New file `backend/tests/test_verbatim_helper.py` with six parametrized pytest cases matching the spec's enumerated list:

| # | Input `matches` | Expected |
|---|---|---|
| 1 | `[]` (empty) | `False` |
| 2 | `[{"similarity": 0.80, "validated_answer": "a"}]` (single, below floor) | `False` |
| 3 | `[{"similarity": 0.85, "validated_answer": "a"}]` (single, at floor) | `True` |
| 4 | `[{"similarity": 0.90, ...}, {"similarity": 0.87, ...}]` (top1 strong, gap 0.03 < 0.05) | `False` |
| 5 | `[{"similarity": 0.92, ...}, {"similarity": 0.85, ...}]` (top1 strong, gap 0.07 ≥ 0.05) | `True` |
| 6 | `[{"similarity": 0.80, ...}, {"similarity": 0.70, ...}]` (top1 below floor) | `False` |

**Rationale**: One file, one target function, six parametrized cases — minimal surface that proves the decision table.

**Out of scope for unit tests**: End-to-end ask-the-AI behavior (covered by the quickstart manual verification); frontend widget tests (covered by the quickstart visual check).

---

## Summary of decisions

| Topic | Decision |
|-------|----------|
| Threshold constants | `VERBATIM_MIN_SIMILARITY = 0.85`, `VERBATIM_DOMINANCE_GAP = 0.05` — module-level in `manual_rag_service.py` |
| Dedup for N | By `validated_answer` string identity, computed server-side, sent to frontend as `verified_source_count` |
| SSE ordering | Unchanged. Verbatim path yields one `data:` chunk, relies on existing terminal metadata event |
| Telemetry write | Direct `log_activity` call from each of the four paths, through a shared `_log_verified_served` helper co-located with the two spec-mandated helpers |
| Empty curated answer | Out of scope — not this feature's problem |
| Direct-lookup fast path (spec 067) | Untouched |
| Unit tests | `backend/tests/test_verbatim_helper.py` with 6 parametrized cases |

All NEEDS-CLARIFICATION items resolved. Ready for Phase 1.
