# Tasks: Validated-QA Lookup Stability

**Branch**: `067-validated-qa-lookup-stability`
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Research**: [research.md](./research.md) | **Contracts**: [contracts/ask-endpoint-behavior.md](./contracts/ask-endpoint-behavior.md)

**Executor**: opencode (implementation) → Claude Code (superpowers review)

---

## Instructions for opencode

You are implementing a bug fix, not building a new feature. Read these four files **in this order** before writing any code:

1. [spec.md](./spec.md) — what the bug looks like to the user
2. [research.md](./research.md) — the three design decisions (why we add a lookup, not replace; why we don't touch the service; why we keep the system filter)
3. [contracts/ask-endpoint-behavior.md](./contracts/ask-endpoint-behavior.md) — INV-1 through INV-5 are non-negotiable invariants
4. [quickstart.md](./quickstart.md) — how the fix will be verified manually and in pytest

**Scope boundary (do not cross)**:
- ✅ Modify **one file**: [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py)
- ✅ Create **one new test file**: `backend/tests/test_validated_qa_lookup.py`
- ❌ Do NOT modify [backend/services/validated_qa_service.py](../../backend/services/validated_qa_service.py)
- ❌ Do NOT modify any Supabase migration, RPC, or schema
- ❌ Do NOT modify `_rewrite_query`, HyDE, retrieval, rerank, or generation code
- ❌ Do NOT modify frontend code
- ❌ Do NOT change the HTTP response schema

**If a task seems to require changes outside this scope, stop and flag it rather than expand scope.**

**Commit strategy**: One commit at the end of Phase 5 with the implementation + tests together. Commit message format: `fix(spec-067): pre-rewrite validated_qa lookup for stable cache hits`.

---

## Rules of engagement (non-negotiable)

These rules exist because past LLM-run implementations have quietly skipped steps, edited tests to pass, or claimed success without evidence. Violating any of them is a review failure, even if the code happens to work.

### 1. No unverified claims

Every task you mark complete must be backed by **evidence you paste into your handoff report (T020)**. Evidence means:
- For code edits: the actual unified diff of your changes (from `git diff`).
- For test runs: the full pytest output (not a summary, not "tests pass").
- For file inspections (T002, T003): quote the relevant lines you read, with line numbers.

Saying "done" or "tests pass" without the evidence block is treated as the task not being done.

### 2. Never edit tests to make them pass

If a test fails, the **implementation** is wrong — not the test. Fix the code. The only exception is a genuine bug in the test itself (wrong assertion, typo in fixture). If you believe that's the case, flag it explicitly in T020 with the reasoning; don't silently rewrite the test.

### 3. No vacuous mocks

When you mock `check_validated_match` or other dependencies (T009–T015), the test must still exercise real production code paths in `ask(...)`. A test that mocks every dependency and only verifies the mocks were called is vacuous — it would pass even if `ask(...)` were `return None`. Each test must assert something about the **actual return value or real side effect** of `ask(...)`, not just the interaction with mocks.

### 4. Read before you write

T001 is not a formality. If your T005 diff contradicts something stated in [research.md](./research.md) or [contracts/ask-endpoint-behavior.md](./contracts/ask-endpoint-behavior.md), the review will catch it and you will redo the task. Quote the specific passage you followed if any design decision feels ambiguous.

### 5. Do not invent

If a referenced function, parameter, or line range doesn't match what you find in the code, **stop and report** — do not guess and patch a plausible-looking version. The spec was written against real line numbers; drift is possible but must be flagged, not hidden.

### 6. No surprise files

If your final `git status` shows any file changed that isn't `backend/services/manual_rag_service.py` or `backend/tests/test_validated_qa_lookup.py`, either (a) revert it, or (b) explain why in T020. Unexplained drift files (e.g., `__pycache__`, editor config, version bumps, accidental reformatting of adjacent code) are a review failure.

### 7. Report honestly

In T020, if you got stuck, took a shortcut, or made a judgment call not covered by the spec, **say so**. Hidden shortcuts caught in review cost more trust than disclosed ones. A report like "I couldn't figure out how to time the lookup without extending LatencyBreakdown, so I used a plain `time.monotonic()` and a log line — flagging for review" is exactly the right disclosure.

---

**Commit strategy**: One commit at the end of Phase 5 with the implementation + tests together. Commit message format: `fix(spec-067): pre-rewrite validated_qa lookup for stable cache hits`.

---

## Phase 1: Setup

- [ ] T001 Read [spec.md](./spec.md), [research.md](./research.md), [contracts/ask-endpoint-behavior.md](./contracts/ask-endpoint-behavior.md), and [quickstart.md](./quickstart.md) in full.
- [ ] T002 Open [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py) and locate the `async def ask(...)` function. Confirm the current validated_qa call sits AFTER `_rewrite_query` (around lines 793–850). If the layout has shifted, note the current line numbers before editing.
- [ ] T003 Open [backend/services/validated_qa_service.py](../../backend/services/validated_qa_service.py) and read `check_validated_match` (around line 260). Confirm its signature: `async def check_validated_match(query_text: str, detected_system: str | None = None) -> dict`. Confirm return shape: `{"match_type": "direct" | "context" | "none", "validated_qa": {...} | None}`. Do NOT modify this file.
- [ ] T004 Confirm `backend/tests/conftest.py` exists and understand its fixtures. This is where shared test helpers live.

## Phase 2: Foundational

*(No foundational tasks — the existing `validated_qa_service`, `search_validated_qa` RPC, and `detect_system` helper already provide everything needed.)*

---

## Phase 3: User Story 1 — Repeated Lookup Returns Cached Answer Every Time (P1)

**Story goal**: Five identical asks in one session all return the Verified Answer in under 2 seconds each.

**Independent test (from quickstart step 1)**: Fresh session → ask "what is the password of AIDA NG system?" five times in a row → all five must be cache hits with Verified Answer badge.

### Implementation

- [ ] T005 [US1] In [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py), inside `ask(...)`, **immediately before** the existing `_rewrite_query` call (currently around line 796–797), insert a pre-rewrite validated-QA fast-path block. The block must:
  1. Call `detect_system(question)` on the raw question (the variable is already named `question` in this function). If `detected_system` is already set earlier in the function, reuse it; do not shadow it.
  2. Time the call using the existing `_StageTimer` / latency-breakdown pattern used elsewhere in this file — reuse the `retrieval_ms` or introduce a reusable label; match existing style. (If unclear, use a `time.monotonic()` pair and a log line; do NOT add a new Pydantic field to `LatencyBreakdown`.)
  3. Call `await validated_qa_service.check_validated_match(question, detected_system=detected_system)`.
  4. If `match_result["match_type"] == "direct"`, construct and return the same response dict that the existing post-rewrite direct-hit branch returns (lines ~824–842). Copy that structure verbatim — including `answer`, `grounded: True`, `sources: []`, `model: "validated_qa"`, `duration_seconds`, `is_verified: True`, `verified_source: {...}`, `retrieval_info`.
  5. If `match_result["match_type"] == "context"`, do NOT return. Instead, set `validated_context = match_result["validated_qa"]["validated_answer"]` so the downstream pipeline still benefits. Then allow the function to continue into `_rewrite_query`.
  6. If `match_result["match_type"] == "none"`, set `validated_context = None` and continue.
  7. Wrap the whole block in `try/except Exception as e` and log a warning (`"Pre-rewrite validated_qa check failed, falling back to normal pipeline: %s"`). On exception, continue to the existing pipeline.
- [ ] T006 [US1] Add a log statement inside the pre-rewrite HIT branch: `logger.info("validated_qa hit (pre-rewrite)", extra={"validated_qa_id": str(vqa["id"]), "detected_system": detected_system})`. Add a matching `logger.info("validated_qa hit (post-rewrite)", ...)` inside the existing post-rewrite direct-hit branch so the two paths are distinguishable in logs. (Contract INV: observable signals.)
- [ ] T007 [US1] Review the edited `ask(...)` flow end-to-end and verify against invariants in [contracts/ask-endpoint-behavior.md](./contracts/ask-endpoint-behavior.md):
  - INV-1: same raw question returns same cached answer regardless of history length.
  - INV-3: `detected_system` is passed to both pre- and post-rewrite `check_validated_match` calls.
  - INV-4: no writes to `validated_qa` anywhere on the new path.
  - INV-5: the Verified Answer response shape matches the existing post-rewrite hit response byte-for-byte (except for the new log line).

### Tests (pytest)

- [ ] T008 [P] [US1] Create `backend/tests/test_validated_qa_lookup.py` with module docstring and imports for pytest, unittest.mock (AsyncMock, patch, call), and the function under test (`from services.manual_rag_service import ask`).
- [ ] T009 [P] [US1] In `test_validated_qa_lookup.py`, write `test_pre_rewrite_hit_returns_cached_answer_without_rewrite`. Mock `validated_qa_service.check_validated_match` to return `{"match_type": "direct", "validated_qa": {...fixture...}}`. Mock `_rewrite_query`, `_generate_hypothetical_answer`, and any retrieval function so you can assert they are NOT called. Call `await ask(question="what is the password of AIDA NG system?", history=[], user_email="test@example.com")`. Assert response has `is_verified is True`, `model == "validated_qa"`, and the mocked downstream functions were called zero times.
- [ ] T010 [US1] In `test_validated_qa_lookup.py`, write `test_pre_rewrite_miss_falls_through_to_existing_pipeline`. Mock the first `check_validated_match` call (pre-rewrite) to return `{"match_type": "none", "validated_qa": None}`. Assert `_rewrite_query` IS called. Mock downstream stages to short-circuit cleanly.

---

## Phase 4: User Story 2 — Lookup Remains Stable Across Interleaved Topics (P2)

**Story goal**: Topic switches and trivial paraphrases don't break the cache for a previously-hit question.

**Independent test (from quickstart step 2)**: Ask Q1 (cached), ask Q2 (unrelated), re-ask Q1 → still cache hit.

### Implementation

*(No additional implementation — Story 2 is covered by the same pre-rewrite fast path from Story 1, because the lookup uses raw question text and doesn't depend on history.)*

### Tests

- [ ] T011 [US2] In `test_validated_qa_lookup.py`, write `test_pre_rewrite_hit_ignores_history_length`. Call `ask(...)` with the same raw question across two invocations: one with `history=[]`, one with `history=[{"question": "unrelated", "answer": "..."}] * 5`. Mock `check_validated_match` to return a direct hit in both cases. Assert both responses are identical (same cached answer, same `is_verified`) and the mocked `_rewrite_query` was never called in either invocation.
- [ ] T012 [US2] In `test_validated_qa_lookup.py`, write `test_context_dependent_followup_hits_post_rewrite_path`. Set up: pre-rewrite lookup returns `none`, `_rewrite_query` returns a rewritten query like `"any other steps for CADAS-ATS?"`, post-rewrite lookup returns `direct`. Assert the final response is the cached answer from the post-rewrite lookup AND that `_rewrite_query` was called exactly once. This protects INV-2.

---

## Phase 5: Polish & Cross-Cutting

- [ ] T013 [P] In `test_validated_qa_lookup.py`, write `test_system_filter_applied_on_pre_rewrite_lookup`. Assert that when `ask(...)` is called with a question containing a system keyword (e.g., "AIDA NG"), the pre-rewrite `check_validated_match` is called with `detected_system="AIDA-NG"` (or whatever `detect_system` returns for that input). Protects INV-3.
- [ ] T014 [P] In `test_validated_qa_lookup.py`, write `test_validated_qa_never_written_on_read_path`. Patch `supabase.table("validated_qa")` at the import site; run a full `ask(...)` cycle (both hit and miss paths); assert no `.insert()`, `.update()`, or `.delete()` calls occurred. Protects INV-4 / FR-007.
- [ ] T015 [P] In `test_validated_qa_lookup.py`, write `test_pre_rewrite_exception_falls_through_safely`. Patch `check_validated_match` to raise `Exception("boom")` on the pre-rewrite call. Assert the pipeline continues into `_rewrite_query` rather than surfacing the exception to the caller.
- [ ] T016 Run the full test file: `cd backend && pytest tests/test_validated_qa_lookup.py -v`. All tests must pass. If any fail, fix implementation — not the tests — unless you find a genuine test bug.
- [ ] T017 Run the existing backend test suite to confirm no regression: `cd backend && pytest -x`. Must pass cleanly.
- [ ] T018 Manual smoke test locally (if local backend is running): invoke `POST /manuals/ask` with the AIDA-NG question from a REST client 5 times in a row with accumulated history; confirm 5 cache hits via response `is_verified: true` and server log lines `validated_qa hit (pre-rewrite)`. If no local backend, skip and rely on server-side verification after deploy.
- [ ] T019 Stage the two files (`backend/services/manual_rag_service.py`, `backend/tests/test_validated_qa_lookup.py`) and commit: `fix(spec-067): pre-rewrite validated_qa lookup for stable cache hits`. Include a body mentioning SC-001 (5/5 hits) and SC-002 (<2 s hit path).
- [ ] T020 Report back to Claude Code for superpowers review. Your report MUST include, in this order:
  1. **Commit SHA** of the single commit from T019.
  2. **Full `git diff HEAD~1`** output (the entire diff, not excerpts).
  3. **Full output of `pytest tests/test_validated_qa_lookup.py -v`** (all test names + PASSED/FAILED status + any stdout).
  4. **Full output of `pytest -x` in `backend/`** (or the first failure with full traceback if any).
  5. **Final `git status`** output showing the working tree is clean.
  6. **Design judgment calls**: for each place in T005 where the spec left room for interpretation (e.g., timing strategy, log format, where exactly to insert the block), state what you chose and why.
  7. **Scope concerns**: anything you considered doing but decided was out of scope per the rules. Empty list is acceptable.
  8. **Disclosures**: anything you skipped, any test you modified for non-obvious reasons, any assumption that isn't explicit in the spec. Empty list is acceptable.

  A report missing any of items 1–5 is treated as T020 incomplete.

---

## Dependency Graph

```
Phase 1 (T001–T004) — read & orient
    ↓
Phase 2 — (none)
    ↓
Phase 3 (T005–T010) — pre-rewrite fast-path + core tests
    ↓
Phase 4 (T011–T012) — stability tests (depend on T005's implementation)
    ↓
Phase 5 (T013–T020) — invariant tests, suite run, commit, handoff
```

**Parallel opportunities**: T008–T015 are all inside the same new test file; technically they touch the same file so run serially, but they are independent logically — opencode can think of them as a single batch drafted in one pass, then verified together in T016.

**Within Phase 3**: T005 must complete before T007. T008 can start in parallel with T005 (skeleton only). T009, T010 depend on T005 and T008.

---

## Acceptance checklist for review

When opencode reports back in T020, Claude Code review will verify:

- [ ] Only two files changed (`manual_rag_service.py`, `test_validated_qa_lookup.py`).
- [ ] `validated_qa_service.py` is byte-identical to main.
- [ ] No migration files added.
- [ ] No frontend files changed.
- [ ] No changes to `_rewrite_query`, HyDE, or retrieval functions.
- [ ] All five test files from Phase 3–5 present and passing.
- [ ] `pytest -x` clean in `backend/`.
- [ ] Pre-rewrite HIT branch returns the exact same response shape as post-rewrite HIT branch (diff the two branches in review).
- [ ] `detect_system` is passed to the pre-rewrite lookup.
- [ ] Exception handler around pre-rewrite block falls through, does not raise.
- [ ] Commit message follows project convention (`fix(spec-067): ...`).
- [ ] INV-1 through INV-5 each verifiable by reading the diff.

---

## Out-of-scope (do not implement)

- Retuning the similarity threshold.
- Refactoring `check_validated_match` signature.
- Adding a new "lookup strategy" parameter anywhere.
- Caching validated_qa results in-memory across requests.
- Adding new metrics dashboards.
- Adding a frontend indicator for pre-rewrite vs post-rewrite hit.
- Adding a new `LatencyBreakdown` field for validated_qa timing (spec 066 owns that file; this spec does not extend it).

If any of these seem necessary, stop and flag it for Claude Code review — do not implement on your own judgment.
