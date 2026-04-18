---
description: "Task list for feature 083 implementation by opencode"
---

# Tasks: Verbatim Verified Answers

**Input**: Design documents from `specs/083-verbatim-verified-answers/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/response-schema.md](contracts/response-schema.md), [quickstart.md](quickstart.md)

**Tests**: Unit tests are **REQUIRED** — the spec mandates 6 parametrized cases for `_should_return_verbatim` (see research.md §R8). All other test tasks are optional.

**Organization**: Tasks grouped by user story for independent implementability. User Story 1 is the MVP and must be shippable on its own.

**Audience**: opencode LLM. After opencode finishes a phase, stop and signal for Claude Code to perform superpowers code review.

---

## Format: `[ID] [P?] [Story?] Description`

- **[P]** = parallelizable (different file, no blocking dependency on an incomplete task)
- **[Story]** = user story label (`[US1]`, `[US2]`, `[US3]`)
- All file paths are relative to repo root `c:/Development/flutter_work_order/`

---

## Phase 1: Setup

**Purpose**: Confirm local state is ready.

- [ ] T001 Confirm you are on branch `083-verbatim-verified-answers` (`git branch --show-current`) and the working tree is clean. If not, abort and ask the user.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the shared constants and helpers that all four is_verified=true code paths will depend on. Writing the helpers first keeps the four callers symmetric.

**⚠️ CRITICAL**: No US1/US2/US3 task may start until this phase is complete and unit tests pass.

### Tests first (TDD for the verbatim decision)

- [ ] T002 Create `backend/tests/test_verbatim_helper.py` with six parametrized pytest cases matching [research.md §R8](research.md) exactly. Each case asserts the return value of `manual_rag_service._should_return_verbatim(matches)`:

  | Case | `matches` input | Expected |
  |---|---|---|
  | empty | `[]` | `False` |
  | single_below_floor | `[{"similarity": 0.80, "validated_answer": "a"}]` | `False` |
  | single_at_floor | `[{"similarity": 0.85, "validated_answer": "a"}]` | `True` |
  | multi_gap_too_small | `[{"similarity": 0.90, "validated_answer": "a"}, {"similarity": 0.87, "validated_answer": "b"}]` | `False` |
  | multi_dominant | `[{"similarity": 0.92, "validated_answer": "a"}, {"similarity": 0.85, "validated_answer": "b"}]` | `True` |
  | multi_top1_below_floor | `[{"similarity": 0.80, "validated_answer": "a"}, {"similarity": 0.70, "validated_answer": "b"}]` | `False` |

  Use `pytest.mark.parametrize` with ids matching the column above. Import via `from services.manual_rag_service import _should_return_verbatim`. Run `cd backend && pytest tests/test_verbatim_helper.py -v` and confirm **all six FAIL** with `ImportError` or `AttributeError` (helper not yet defined).

### Module-level constants

- [ ] T003 [P] In `backend/services/manual_rag_service.py`, add two module-level constants **immediately below** the existing `RAG_CONFIDENCE_THRESHOLD = 0.75` around line 103:

  ```python
  VERBATIM_MIN_SIMILARITY = 0.85  # top-1 floor for verbatim short-circuit (FR-001)
  VERBATIM_DOMINANCE_GAP = 0.05   # required gap between top-1 and top-2 (FR-001)
  ```

  Do not add any other constants, imports, or blank-line changes.

### Helpers

- [ ] T004 In `backend/services/manual_rag_service.py`, implement private helper `_should_return_verbatim(matches: list[dict]) -> bool` per [data-model.md §2.1](data-model.md). Logic, line-for-line:

  ```python
  def _should_return_verbatim(matches: list[dict]) -> bool:
      if not matches:
          return False
      top1 = matches[0]["similarity"]
      if top1 < VERBATIM_MIN_SIMILARITY:
          return False
      if len(matches) == 1:
          return True
      top2 = matches[1]["similarity"]
      return (top1 - top2) >= VERBATIM_DOMINANCE_GAP
  ```

  Place it between the existing module-level helpers (e.g., near `_is_direct_lookup` around line 500+ — use your best judgment on location, but module scope, not nested). Re-run `cd backend && pytest tests/test_verbatim_helper.py -v` and confirm **all six PASS**.

- [ ] T005 [P] In `backend/services/manual_rag_service.py`, implement `_count_distinct_sources(matches: list[dict]) -> int` at module scope:

  ```python
  def _count_distinct_sources(matches: list[dict]) -> int:
      """Count distinct underlying curated answers (spec 068 variants share text)."""
      return len({m["validated_answer"] for m in matches}) if matches else 0
  ```

  Rationale per [research.md §R2](research.md) — dedup by answer-text identity.

- [ ] T006 In `backend/services/manual_rag_service.py`, implement `_log_verified_served` at module scope per [data-model.md §2.3](data-model.md):

  ```python
  def _log_verified_served(
      user_email: str,
      question: str,
      verification_mode: str,
      top1: float,
      top2: float,
  ) -> None:
      """Fire-and-forget telemetry write per FR-014. Never blocks the response path."""
      try:
          from utils.activity import log_activity
          log_activity(
              user_email=user_email,
              category="manual",
              action="verified_answer_served",
              target_label=question[:80],
              target_id="",
              detail=f"mode={verification_mode};top1={top1:.3f};top2={top2:.3f}",
          )
      except Exception as e:
          logger.warning("verified_answer_served telemetry failed: %s", e)
  ```

  `log_activity` already has an internal try/except; this outer wrapper is defence-in-depth per FR-015.

- [ ] T007 In `backend/services/manual_rag_service.py`, implement `_build_verbatim_payload` at module scope per [data-model.md §1.3 and §2.2](data-model.md):

  ```python
  def _build_verbatim_payload(
      matches: list[dict],
      *,
      search_query: str,
      retrieval_info: dict | None,
      latency_breakdown: dict | None,
  ) -> dict:
      """Build response dict for the verbatim path — NO LLM call."""
      top1 = matches[0]["similarity"]
      confidence = "high" if top1 >= RAG_HIGH_CONFIDENCE else "medium"
      if latency_breakdown is not None:
          latency_breakdown["generator_ms"] = 0
      return {
          "answer": matches[0]["validated_answer"],  # byte-identical, NO stripping
          "grounded": True,
          "sources": [
              {"id": m["id"], "question_text": m["question_text"], "score": m["similarity"]}
              for m in matches
          ],
          "confidence": confidence,
          "score": top1,
          "model": "Verbatim (no generation)",
          "provider_display_name": "Verbatim (no generation)",
          "duration_seconds": 0.0,
          "is_verified": True,
          "verified_source": {
              "validated_qa_id": str(matches[0]["id"]),
              "validated_by": matches[0]["validated_by"],
              "validated_at": (
                  matches[0]["validated_at"].isoformat()
                  if hasattr(matches[0]["validated_at"], "isoformat")
                  else str(matches[0]["validated_at"])
              ),
              "similarity": top1,
          },
          "verification_mode": "verbatim",
          "verified_source_count": 1,
          "retrieval_info": retrieval_info,
          "provider_used": "verbatim",
          "fallback_used": False,
          "session_summary": None,
          "search_query": search_query,
          "latency_breakdown": latency_breakdown,
          "source_type": "validated_qa",
      }
  ```

  Do NOT `.strip()` or modify `validated_answer` in any way (SC-007 requires byte-identical output).

**Checkpoint**: Foundational helpers complete. Unit tests green. Stop and wait for review before starting Phase 3.

---

## Phase 3: User Story 1 — Verbatim short-circuit + telemetry (Priority: P1) 🎯 MVP

**Goal**: Wire `_should_return_verbatim`, `_build_verbatim_payload`, and `_log_verified_served` into all four is_verified=true code paths so a near-exact curated match returns in <2s without invoking the LLM. Also set `verification_mode` and `verified_source_count` on the synthesis branch (backend contract-complete on both modes).

**Independent Test**: Per [quickstart.md §1](quickstart.md): send the exact text of a curated Q&A question via `POST /manuals/ask`; response arrives in <2s with `verification_mode: "verbatim"`, `provider_used: "verbatim"`, `duration_seconds: 0.0`, and `answer` byte-identical to the stored `validated_answer`. `user_activity_log` gains one row with `action='verified_answer_served'`.

### Backend wiring — four is_verified=true paths

For each of T008–T011, follow the SAME 7-step recipe:

```
(a) Replace `max_score = max(m["similarity"] for m in vqa_matches)` with:
        top1 = vqa_matches[0]["similarity"]
        top2 = vqa_matches[1]["similarity"] if len(vqa_matches) > 1 else 0.0
        max_score = top1  # keep variable name for minimal downstream diff

(b) After the existing `if max_score >= RAG_CONFIDENCE_THRESHOLD:` guard,
    before any context-building, add:
        is_verbatim = _should_return_verbatim(vqa_matches)
        verification_mode = "verbatim" if is_verbatim else "synthesized"
        verified_source_count = 1 if is_verbatim else _count_distinct_sources(vqa_matches)

(c) Call telemetry BEFORE the branch:
        _log_verified_served(user_email, question, verification_mode, top1, top2)
    (Use `question` on pre-rewrite paths; use `search_query` on post-rewrite paths — these are the variables already in scope at each site.)

(d) If is_verbatim is True:
        - STREAMING paths: populate stream_meta with is_verified, verified_source,
          sources, grounded, confidence (same as today), plus:
              stream_meta["verification_mode"] = "verbatim"
              stream_meta["verified_source_count"] = 1
          Then `yield vqa_matches[0]["validated_answer"]` and `return`.
          DO NOT call provider_generate_stream.
        - NON-STREAMING paths: `return _build_verbatim_payload(
              vqa_matches,
              search_query=search_query,
              retrieval_info=retrieval_info,
              latency_breakdown=breakdown,
          )`. DO NOT call provider_generate.

(e) Else (synthesis path — unchanged behavior plus two new fields):
        - STREAMING paths: in the existing stream_meta.update({...}) that sets
          is_verified/verified_source, also add:
              "verification_mode": "synthesized",
              "verified_source_count": verified_source_count,
        - NON-STREAMING paths: in the existing `return { ... }` dict that sets
          is_verified/verified_source, also add:
              "verification_mode": "synthesized",
              "verified_source_count": verified_source_count,

(f) Preserve ALL existing code below the is_verified branch unchanged.

(g) After editing, grep the file for `is_verified` to confirm all four sites now
    have symmetric structure.
```

- [ ] T008 [US1] Apply recipe to **pre-rewrite streaming path** in `backend/services/manual_rag_service.py` around lines 725–774. Source variable: `question`. The yield goes through the existing async generator — `yield vqa_matches[0]["validated_answer"]` then `return`.

- [ ] T009 [US1] Apply recipe to **post-rewrite streaming path** in `backend/services/manual_rag_service.py` around lines 819–868. Source variable: `search_query`.

- [ ] T010 [US1] Apply recipe to **pre-rewrite non-streaming path** in `backend/services/manual_rag_service.py` around lines 988–1078. Source variable: `question`. Non-streaming uses `_build_verbatim_payload(...)` return instead of yield.

- [ ] T011 [US1] Apply recipe to **post-rewrite non-streaming path** in `backend/services/manual_rag_service.py` around lines 1170–1269. Source variable: `search_query`.

### Router forwarding (streaming endpoint)

- [ ] T012 [US1] In `backend/routers/manuals.py`, locate the terminal `result = { ... }` dict inside `event_gen()` around lines 470–489. Add two keys so the metadata event carries them to the frontend:

  ```python
  "verification_mode": stream_meta.get("verification_mode"),
  "verified_source_count": stream_meta.get("verified_source_count"),
  ```

  Place them immediately after the existing `"verified_source": stream_meta.get("verified_source"),` line. Do not reorder other keys.

### MVP validation

- [ ] T013 [US1] Deploy to the dev backend (or restart locally): `sudo systemctl restart document_server.service` (or equivalent in dev). Then manually hit the API per [quickstart.md §1](quickstart.md): verify JSON contains `verification_mode`, `verified_source_count`, `provider_used: "verbatim"`, `duration_seconds: 0.0`, and answer byte-identical to the curated row. Round-trip < 2 seconds.

- [ ] T014 [US1] Query Supabase to confirm telemetry: `SELECT * FROM user_activity_log WHERE action='verified_answer_served' ORDER BY created_at DESC LIMIT 1;`. Confirm `detail` matches format `mode=verbatim;top1=0.XXX;top2=0.XXX|0.000`.

**Checkpoint**: Backend is contract-complete. Frontend shows today's UI — users see fast verbatim answers but no footer distinction yet. Stop and wait for review before starting Phase 4.

---

## Phase 4: User Story 2 — Honest labeling (Priority: P2)

**Goal**: Frontend differentiates verbatim from synthesized responses. Both show the green "Verified Answer" badge. Only synthesized shows the grey "Synthesized from N verified sources" footer caption.

**Independent Test**: Per [quickstart.md §2](quickstart.md): query with multiple comparable matches → badge visible, footer visible, N correct. Query with dominant match → badge visible, footer absent.

### Frontend model

- [ ] T015 [P] [US2] In `frontend/lib/models/manual_qa_answer.dart`, add two fields to class `ManualQaAnswer` per [data-model.md §3.1](data-model.md):

  1. Add to the field list (after `final String? searchQuery;`):

     ```dart
     final String? verificationMode;
     final int? verifiedSourceCount;
     ```

  2. Add to the constructor parameter list:

     ```dart
     this.verificationMode,
     this.verifiedSourceCount,
     ```

  3. Add to `fromJson` (after `searchQuery: json['search_query'] as String?,`):

     ```dart
     verificationMode: json['verification_mode'] as String?,
     verifiedSourceCount: (json['verified_source_count'] as num?)?.toInt(),
     ```

  Do not rename or reorder existing fields.

### Frontend widget

- [ ] T016 [US2] In `frontend/lib/screens/manual_assistant/widgets/answer_card.dart`, add a grey footer caption widget beneath the answer `Text` (around line 131–134) per [data-model.md §3.2](data-model.md):

  ```dart
  if (isVerified && widget.answer.verificationMode == 'synthesized') ...[
    const SizedBox(height: 8),
    Text(
      'Synthesized from ${widget.answer.verifiedSourceCount ?? widget.answer.sources.length} verified sources',
      style: TextStyle(
        fontSize: 11,
        color: Colors.grey.shade600,
      ),
    ),
  ],
  ```

  Insert it IMMEDIATELY AFTER the answer body `Text` widget (line ~134) and BEFORE the existing `if (widget.answer.manualsConsulted.isNotEmpty)` block at line 135. The existing "Synthesized from N manuals" block at lines 137–159 is a **different** widget serving the non-verified path; do not modify it.

### Frontend validation

- [ ] T017 [US2] Run `cd frontend && dart analyze` — confirm zero new warnings or errors.

- [ ] T018 [US2] Deploy frontend (`scripts/deploy_frontend.sh`) and run manual UI checks per [quickstart.md §2 and §1](quickstart.md):
  - Verbatim response: green badge present, grey footer ABSENT.
  - Synthesized response: green badge present, grey footer reads "Synthesized from N verified sources" where N matches JSON's `verified_source_count`.
  - N correctly dedupes spec-068 paraphrase variants (if any are present in your test data).

**Checkpoint**: End-to-end UX complete. Stop and wait for review before starting Phase 5.

---

## Phase 5: User Story 3 — Telemetry visibility for post-deploy tuning (Priority: P3)

**Goal**: Confirm the telemetry written during Phase 3 is queryable in the shape the operator will use for post-deploy tuning.

**Independent Test**: Per [quickstart.md §6](quickstart.md): run the grouped-aggregation SQL query and get at least one row per `mode` value.

- [ ] T019 [US3] After generating some mixed traffic during Phase 3/4 validation, run the SQL query from [quickstart.md §6](quickstart.md) against the dev database. Confirm:
  - At least two rows returned (one for `mode=verbatim`, one for `mode=synthesized`).
  - `avg_top1` and `avg_top2` are plausible values in range [0.00, 1.00].
  - Event counts match your expected traffic.

- [ ] T020 [US3] Write the verification result (pass/fail + any anomalies) into a short comment at the bottom of `specs/083-verbatim-verified-answers/quickstart.md` (under a new `## Post-implementation verification` section). Do not modify the rest of the file.

**Checkpoint**: All three user stories done.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T021 [P] Run the full backend test suite from repo root: `cd backend && pytest -q`. All pre-existing tests must still pass. `test_verbatim_helper.py` must pass.

- [ ] T022 [P] Run `cd frontend && dart analyze` — zero warnings/errors (sanity re-check after both phases).

- [ ] T023 Re-check all 4 is_verified=true sites by searching the file: `grep -n "is_verified.*True" backend/services/manual_rag_service.py` — confirm all four call `_log_verified_served` and all four set `verification_mode` + `verified_source_count` in their respective return/stream_meta paths. Symmetry across the four sites is the load-bearing invariant of FR-005.

- [ ] T024 Run the full [quickstart.md](quickstart.md) walkthrough end-to-end, marking each of SC-1 through SC-7 as pass or fail. Report results to the user. Do NOT claim completion unless every SC passes.

- [ ] T025 Commit the changes on branch `083-verbatim-verified-answers` with a single commit: `feat(083): verbatim verified answers (US1/US2/US3)`. Do NOT push; the user will handle merge.

**Final checkpoint**: Feature complete, tests green, quickstart SC-1..SC-7 all pass, committed but not pushed. Signal the user that the feature is ready for Claude Code's superpowers code review.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)** → **Foundational (Phase 2)** → (US1 → US2 → US3) → **Polish (Phase 6)**
- US1 (Phase 3) **must** complete before US2 (Phase 4): US2 depends on `verification_mode` and `verified_source_count` existing in the backend response.
- US3 (Phase 5) **must** complete after US1 (Phase 3): US3 validates the telemetry writes added in US1.

### Within Each User Story

- Within Phase 2: T002 (tests) before T004 (helper it tests). T003 (constants) before T004 (helper uses them). T005–T007 can be done in any order after T004.
- Within Phase 3: T008–T011 are technically parallelizable (different code regions in same file), but since they all edit `manual_rag_service.py` a single sequential pass is safer to avoid merge conflicts in the same file. T012 depends on T008 and T009 (router forwards what stream_meta carries). T013/T014 depend on all prior backend changes being deployed.
- Within Phase 4: T015 (model) before T016 (widget that uses model fields). T017/T018 after both.

### Parallel Opportunities

- Phase 2: T003 [P] and T005 [P] are independent file-region edits after T004 lands.
- Phase 6: T021 [P] and T022 [P] run against different toolchains.

---

## Parallel Example — Phase 2 Foundational

```bash
# After T002 (tests) and T003 (constants) are in:
# T004 must run solo (defines the helper under test).
# After T004 passes, T005 and T006 can proceed in parallel:
Task: "Implement _count_distinct_sources in backend/services/manual_rag_service.py"
Task: "Implement _log_verified_served in backend/services/manual_rag_service.py"
# T007 depends on nothing in particular once constants are defined; can run after T004 or alongside T005/T006.
```

---

## Implementation Strategy

### MVP (User Story 1 only)

1. Complete Phase 1 (Setup).
2. Complete Phase 2 (Foundational) — helpers + unit tests.
3. Complete Phase 3 (US1) — backend verbatim short-circuit + telemetry.
4. **STOP AND VALIDATE** against quickstart §1 + §4.
5. The backend contract is complete. Users see fast verbatim answers; UI is unchanged. This is a shippable MVP because correctness (verbatim bytes, telemetry, response contract) is proven before any UI work.

### Incremental Delivery

After MVP validates:

1. Phase 4 (US2) → adds visible UI differentiation → quickstart §2 and §3.
2. Phase 5 (US3) → validates telemetry → quickstart §6.
3. Phase 6 (Polish) → final sweep, quickstart end-to-end, commit.

### Serialization note

Because ~90% of the backend work is in a single 1504-line file, Phase 3's four tasks (T008–T011) SHOULD be done sequentially by one executor rather than parallelized across agents — to prevent merge conflicts. Treat that recipe as one atomic task if that's simpler.

---

## Notes for the implementer (opencode)

- [research.md](research.md) documents every design decision and has the full rationale; when in doubt, check it first.
- [data-model.md](data-model.md) has every helper signature and field shape; copy signatures exactly.
- [contracts/response-schema.md](contracts/response-schema.md) is the JSON contract truth; keep response shapes aligned.
- Do NOT modify `backend/services/validated_qa_service.py` (FR-019 explicitly forbids it).
- Do NOT add migrations in `supabase/migrations/` (FR-019).
- Do NOT change `RAG_CONFIDENCE_THRESHOLD = 0.75` (FR-016).
- Do NOT touch the `_is_direct_lookup` spec-067 fast path (FR-017).
- Do NOT add language-model call fallbacks on the verbatim path — FR-003 says zero LLM on verbatim.
- `validated_answer` on the verbatim path is **byte-identical** — never call `.strip()`, `.replace()`, or any normalization on it (SC-007).
- `log_activity` has an internal try/except already; the outer wrapper in `_log_verified_served` is intentional defence-in-depth (FR-015). Do not remove it.
- After completing each phase checkpoint, pause so Claude Code can do a superpowers code review of the phase's work before the next phase begins.
