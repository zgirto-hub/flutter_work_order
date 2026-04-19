# Phase 0 Research: Spec 089 — Generator Prompt Tuning

**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Date**: 2026-04-19

All NEEDS CLARIFICATION items from Technical Context were resolved via `/speckit.clarify` (5 Q&A, see `spec.md → ## Clarifications`). This document records the research that backs the clarifications plus four further decisions discovered while inspecting the actual code.

---

## D-01 — Generator model target

**Decision**: Model-neutral prompt. Target `services.ai_providers.resolver` (spec 063); validation runs against whichever provider the resolver returns at test time.

**Rationale**: Spec 063 already abstracts provider choice via `app_settings.ai_provider`. Memory + spec 076 show the default has flipped (Gemma → Gemini) and may flip again. Pinning to one provider forces re-tuning when the default changes. A model-neutral prompt — no Gemma-specific tokens, no Gemini-specific preambles — absorbs the abstraction correctly.

**Alternatives considered**:
- *Pin to Gemini*: Currently default per spec 076, but creates tuning debt on flip. Rejected.
- *Pin to Gemma 4 E2B*: Matches memory snapshot, but misaligned with current runtime. Rejected.
- *Two parallel prompts, dispatched by provider*: Adds maintenance surface; Principle VII violation. Rejected.

**Research evidence**: [backend/services/ai_providers/resolver.py](../../backend/services/ai_providers/resolver.py), [backend/services/ai_providers/gemini.py](../../backend/services/ai_providers/gemini.py), [backend/services/ai_providers/local_ollama.py](../../backend/services/ai_providers/local_ollama.py) all consume the same `system_prompt` string — no provider-specific reformatting step exists.

---

## D-02 — Few-shot example content authenticity

**Decision**: Source 3 of the 4 few-shot examples from existing `validated_qa` rows (human-verified via spec 083). The 4th (genuine-refuse case) remains synthetic because no `validated_qa` row represents a truly unanswerable question.

**Rationale**: Invented example answers teach pattern shape but risk leaking fabricated specifics into production output. `validated_qa` is already human-curated through the spec 083 verbatim path (similarity ≥ 0.85 short-circuit) — reusing its rows gives Gemma/Gemini authentic prose grounded in real manual content, with zero fabrication risk.

**Alternatives considered**:
- *Keep illustrative (invented)*: Fastest but risks teaching wrong content. Rejected.
- *Hand-craft verified excerpts*: Requires implementer to find manual content and transcribe accurately — slow and error-prone. Rejected.
- *Generate examples synthetically via Gemini and have user approve*: Adds pipeline step for a one-off artifact. Rejected as overengineering (Principle VII).

**Research evidence**: `validated_qa` schema in [supabase/migrations/20260413000000_create_feedback_loop.sql](../../supabase/migrations/20260413000000_create_feedback_loop.sql) — columns `question_text`, `validated_answer`, `thumbs_up_count`, `thumbs_down_count`, `is_reflagged`, `created_at`. Selection SQL ready to run at implementation time; see quickstart.md §2.

**Column-name correction**: Initial spec draft referenced `answer_text` and `approval_count` — both wrong. Correct names are `validated_answer` and `(thumbs_up_count - thumbs_down_count)`. Spec 089 has been patched.

---

## D-03 — Causal-signal SC (SC-007)

**Decision**: Hard merge gate — `rag_diagnostic_log` entries with `source='test_suite'` in the post-run 2-hour window must show `generator_refused_with_chunks ≤ 15` (baseline: 50). Stretch: ≤ 8.

**Rationale**: The 87-question aggregate pass rate (SC-002) is composed of many failure modes; it can improve by luck on any subset of them. The reason-code distribution in `rag_diagnostic_log` is the direct causal signal: spec 089's lever targets `generator_refused_with_chunks` specifically, and that bucket must drop materially for the change to have taken effect. Catches silent deployment bugs where prompt didn't reach runtime (cache, wrong file edited, restart missed).

**Alternatives considered**:
- *Advisory only (PR description, not gate)*: Loses merge-blocking rigor. Rejected.
- *Per-question sentinel check instead of aggregate bucket*: Duplicates SC-005's must-refuse logic. Rejected.
- *Include provenance assertion (which model actually ran)*: Out of scope; resolver-level provenance is ambient, not per-request. Deferred.

**Research evidence**: Spec 088 ships `rag_diagnostic_log` with `source`, `reason_code`, `created_at` filter columns. Query in spec.md §6.4 validated against running database via Supabase MCP during `/speckit.clarify`.

---

## D-04 — Must-refuse assertion location

**Decision**: Extend `backend/tests/test_rag_quality.py` with a `must_refuse: bool` per-entry flag. Runner logic: if `must_refuse=True` and response returns `grounded=True`, mark as REGRESSION (distinct from ordinary FAILURE) and exit non-zero after the summary.

**Rationale**: `test_rag_quality.py` already has per-entry `expect: "ungrounded"` markers for Cat 6 questions. The `must_refuse` flag is a promotion of those from "expected outcome for scoring" to "merge-blocking gate." Keeps pass/fail logic co-located with the suite; avoids parallel CI scripts.

**Alternatives considered**:
- *Standalone script `test_rag_089_must_refuse.py`*: Separate invocation, separate output, parallel truth source. Rejected.
- *Post-run SQL assertion on `rag_diagnostic_log`*: Couples test outcome to ambient DB state (what if other traffic writes in the window?). Rejected.

**Research evidence**: [backend/tests/test_rag_quality.py](../../backend/tests/test_rag_quality.py) already structures entries as `TestQuestion` dataclass with `expect`/`keywords`/`category`. Adding a Boolean field is a one-line dataclass change plus a runner branch.

---

## D-05 — Iteration cap exit path

**Decision**: At iteration 3 without all SC floors green → revert branch, immediately scaffold spec 090 (query-time acronym expansion + rewrite prompt edit).

**Rationale**: If prompt tuning alone can't close the gap after 3 attempts, the remaining failures are almost certainly on the retrieval/vocabulary side, not the generation side. That's spec 090's territory. Shipping a half-fix of 089 pollutes the baseline for 090. Reverting keeps `main` clean and measurable.

**Alternatives considered**:
- *Abandon branch, wait for more data*: Loses momentum; no concrete follow-up owner. Rejected.
- *Merge best-effort partial win*: Violates the "all floors" merge gate; sets precedent for soft gates. Rejected.
- *Model swap before 090*: Data doesn't support this hypothesis (retrieval-side failures show up as `rerank_below_threshold` + vocabulary mismatch, not model sensitivity). Deferred.

**Research evidence**: See baseline distribution — only 7/58 failures are `rerank_below_threshold` and 1/58 is `no_chunks_retrieved`. These are vocabulary-side failures that 090 targets.

---

## D-06 — Sentinel phrase divergence between prompt and runtime output

**Decision**: Edit DOCUMENT_QA_SYSTEM_PROMPT only; do NOT touch `_NOT_FOUND_KNOWLEDGE_BASE`, `_NOT_FOUND_MANUALS`, `_NOT_FOUND_KNOWLEDGE_BASE_AR` constants or the classifier's `_SENTINEL_PHRASES` list. If the model emits any of the three sentinels, classification still treats that as ungrounded — which is correct.

**Rationale**: While inspecting [backend/services/manual_rag_service.py:210-212](../../backend/services/manual_rag_service.py#L210) I found three refusal strings in use:

```python
_NOT_FOUND_KNOWLEDGE_BASE = "I don't have that information in the knowledge base."
_NOT_FOUND_MANUALS = "This information is not in the available manuals."
_NOT_FOUND_KNOWLEDGE_BASE_AR = "المعلومات المطلوبة غير موجودة في الأدلة المتاحة"
```

DOCUMENT_QA_SYSTEM_PROMPT instructs the model to emit `_NOT_FOUND_KNOWLEDGE_BASE` ("I don't have that information in the knowledge base.") but the test run shows answers coming back with `_NOT_FOUND_MANUALS` ("This information is not in the available manuals."). That means there's a post-generation translation or an override somewhere (likely the trivial-bypass / streaming handler per spec 088 hotfix F2+F3).

For spec 089, this divergence is **not a bug to fix** — the classifier treats all three equivalently. Spec 089 focuses solely on reducing the emission rate. The prompt keeps telling the model to use `_NOT_FOUND_KNOWLEDGE_BASE` via `f-string` substitution; the runtime translation layer continues to normalize to `_NOT_FOUND_MANUALS` for user-facing display.

**Alternatives considered**:
- *Unify to one sentinel*: Attractive for consistency but out of scope. Defer to a future cleanup spec.
- *Change DOCUMENT_QA_SYSTEM_PROMPT to reference `_NOT_FOUND_MANUALS` directly*: Would break the f-string substitution invariant with `_NOT_FOUND_KNOWLEDGE_BASE`; also not in scope. Rejected.

**Research evidence**: [backend/services/manual_rag_service.py:210-212](../../backend/services/manual_rag_service.py#L210) and test output in `rag_quality_results.json` show the mismatch.

---

## Constitution re-check (post-research)

All decisions remain compatible with the Constitution Check in plan.md:
- **Principle VII (YAGNI)**: D-01, D-02, D-04 reuse existing infrastructure (resolver, validated_qa, test_rag_quality.py). No new abstractions added.
- **Principle VI (Audit)**: D-03 reads existing `rag_diagnostic_log` audit stream. No new audit schema.
- **Principle I (Full-Stack Ownership)**: Exception remains justified per plan.md Complexity Tracking.

Gate outcome unchanged: PASS. Proceeding to Phase 1 artifacts.
