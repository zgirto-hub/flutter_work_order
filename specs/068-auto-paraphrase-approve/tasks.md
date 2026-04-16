# Tasks: Auto-Paraphrase on Admin Approve

**Feature**: 068-auto-paraphrase-approve
**Branch**: `068-auto-paraphrase-approve`
**Input**: Spec, plan, research, contracts, data-model, and quickstart in `specs/068-auto-paraphrase-approve/`

This tasks file is written for handoff to another LLM (opencode). Claude Code will perform superpowers review after implementation.

---

## Reference documents (read in full before T005)

1. [spec.md](./spec.md) — feature specification with P1/P2/P3 user stories and 17 FRs
2. [plan.md](./plan.md) — tech stack, scope-in/scope-out, and invariants INV-1..INV-5
3. [research.md](./research.md) — R1–R7 decisions (prompt, embedder strategy, multi-row insert, modal UX, retro-expansion, fallback signalling, atomicity)
4. [data-model.md](./data-model.md) — invariant-enforcement map (no schema changes)
5. [contracts/generate_variants.md](./contracts/generate_variants.md) — paraphrase endpoint contract
6. [contracts/approve_with_variants.md](./contracts/approve_with_variants.md) — batch-insert endpoint contract; INV-1..INV-5 and FR-013 atomicity rules are non-negotiable
7. [quickstart.md](./quickstart.md) — manual smoke tests P1, P2, P2b, P3

---

## Scope boundary (enforce throughout)

**ALLOWED files to modify or create**:
- `backend/routers/manuals.py` (extend)
- `backend/services/validated_qa_service.py` (add bulk-insert helper only — DO NOT touch `check_validated_match`)
- `backend/prompts/paraphrase_prompt.py` (new, tiny — prompt template + parser)
- `backend/tests/test_paraphrase_generation.py` (new)
- `frontend/lib/screens/manual_assistant/widgets/variants_modal.dart` (new)
- `frontend/lib/screens/manual_assistant/review_queue_tab.dart` (extend)
- `frontend/lib/screens/manual_assistant/verified_answers_tab.dart` (extend)
- `frontend/test/variants_modal_test.dart` (new)

**FORBIDDEN** (if you feel the need to touch these, STOP and report in T-last):
- Any `supabase/migrations/*.sql` (no schema changes permitted)
- `backend/services/manual_rag_service.py` (read path — spec 067 territory)
- `backend/services/ai_providers/resolver.py` internals (reuse `.generate()` only — do not modify)
- `backend/services/ollama_embedder.py` configuration (reuse `.embed_single()` — do not change model or parameters)
- Anything in `frontend/lib/screens/manual_assistant/chat_tab.dart` (technician-facing; out of scope)
- `validated_qa_service.check_validated_match` (INV-4 — read path is spec 067's)

---

## Rules of engagement (non-negotiable)

These rules exist because past LLM-run implementations have quietly skipped steps, edited tests to pass, or claimed success without evidence. Violating any of them is a review failure, even if the code happens to work.

### 1. No unverified claims

Every task you mark complete must be backed by **evidence you paste into your handoff report (T-last)**. Evidence means:
- For code edits: the actual unified diff of your changes (from `git diff`).
- For test runs: the full pytest or flutter test output (not a summary, not "tests pass").
- For file inspections (T002, T003, T004): quote the relevant lines you read, with line numbers.

Saying "done" or "tests pass" without the evidence block is treated as the task not being done.

### 2. Never edit tests to make them pass

If a test fails, the **implementation** is wrong — not the test. Fix the code. The only exception is a genuine bug in the test itself (wrong assertion, typo in fixture). If you believe that's the case, flag it explicitly in T-last with the reasoning; don't silently rewrite the test.

### 3. No vacuous mocks

When you mock `resolver.generate`, `embed_single`, or the Supabase client, the test must still exercise real production code paths in the endpoint or service. A test that mocks every dependency and only verifies the mocks were called is vacuous — it would pass even if the endpoint were `return None`. Each test must assert something about the **actual return value, response shape, or real side effect** (row count, row contents, HTTP status), not just the interaction with mocks.

### 4. Read before you write

T001 is not a formality. If your code contradicts something stated in [research.md](./research.md), [plan.md](./plan.md), or either contract file, the review will catch it and you will redo the task. Quote the specific passage you followed if any design decision feels ambiguous.

### 5. Do not invent

If a referenced function, parameter, or line range doesn't match what you find in the code, **stop and report** — do not guess and patch a plausible-looking version. The spec and plan were written against real line numbers and real function signatures; drift is possible but must be flagged in T-last, not hidden.

### 6. No surprise files

If your final `git status` shows any file changed that isn't in the ALLOWED list under "Scope boundary" above, either (a) revert it, or (b) explain why in T-last. Unexplained drift files (e.g., `__pycache__`, editor config, version bumps, accidental reformatting of adjacent code, stray `frontend/backend/version.json` commits) are a review failure.

### 7. Report honestly

In T-last, if you got stuck, took a shortcut, or made a judgment call not covered by the spec, **say so**. Hidden shortcuts caught in review cost more trust than disclosed ones. A report like "contract said atomic single-statement insert but I ended up with a per-row loop because the Supabase Python client rejected the list payload — flagging for review" is exactly the right disclosure.

---

**Commit strategy**: Two commits — one for backend, one for frontend — OR one combined commit, your call. Document which in T-last item 1. Suggested message formats:
- Combined: `feat(spec-068): auto-paraphrase variants on admin approve`
- Split: `feat(spec-068): backend paraphrase + batch insert endpoints` and `feat(spec-068): variants modal UI for Review/Verified tabs`

**MVP scope**: User Story 1 (P1) only. P2 (retro-expansion) and P3 (fallback) are additive phases that can be skipped without breaking P1. Deliver P1 end-to-end before starting P2.

---

## Phase 1: Setup

- [ ] T001 Read [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/generate_variants.md](./contracts/generate_variants.md), [contracts/approve_with_variants.md](./contracts/approve_with_variants.md), and [quickstart.md](./quickstart.md) in full. Note INV-1..INV-5 from plan.md — these are non-negotiable invariants.
- [ ] T002 Open [backend/services/validated_qa_service.py](../../backend/services/validated_qa_service.py). Locate `review_answer` (around line 152) and note its exact current signature and body, especially the answer_ratings → validated_qa row construction around lines 213–253. Locate `check_validated_match` (around line 267) and record its signature. **Do not modify either function** — you will add a new sibling helper, not edit these.
- [ ] T003 Open [backend/routers/manuals.py](../../backend/routers/manuals.py). Locate the existing `/review-answer` endpoint (around line 580–605 per plan.md grep) and note the admin auth dependency it uses (e.g., `Depends(require_admin)` or equivalent). Your new endpoints will reuse the same admin gate.
- [ ] T004 Open [backend/services/ai_providers/resolver.py](../../backend/services/ai_providers/resolver.py) and confirm `generate(prompt, system=None, ...)` signature. Open [backend/services/ollama_embedder.py](../../backend/services/ollama_embedder.py) and confirm `embed_single(text) -> list[float]` returns a 768-dim vector for model `nomic-embed-text`. Quote the signatures in T-last as evidence.
- [ ] T005 Open [frontend/lib/screens/manual_assistant/review_queue_tab.dart](../../frontend/lib/screens/manual_assistant/review_queue_tab.dart) and [frontend/lib/screens/manual_assistant/verified_answers_tab.dart](../../frontend/lib/screens/manual_assistant/verified_answers_tab.dart). Note where the existing "Approve" action is wired for the Review tab and how rows are rendered in the Verified tab. Open [frontend/lib/widgets/bottom_sheet_widgets.dart](../../frontend/lib/widgets/bottom_sheet_widgets.dart) and confirm `BottomSheetContainer` exists and its constructor shape.

## Phase 2: Foundational

*(No foundational tasks — all required services, helpers, widgets, and schema already exist. Feature is a pure extension.)*

---

## Phase 3: User Story 1 — Approve with Auto-Generated Variants (P1) — MVP

**Story goal**: Admin clicks Approve in the Review tab → modal opens within ~3s with the original question plus 3–5 paraphrase chips → admin edits/deletes/adds → Save all inserts N `validated_qa` rows sharing one answer, one `rating_id`, each with its own question text and 768-dim embedding.

**Independent test**: Seed one `answer_ratings` row with `review_status='pending'`. Execute P1 scenario from [quickstart.md](./quickstart.md). Verify N distinct `validated_qa` rows exist, all sharing `validated_answer` / `rating_id` / `manual_ids` / `source_chunks`, each with a unique `question_text` and a non-null 768-element `question_embedding`. Asking any variant phrasing as a technician returns the verified answer via the direct-match fast path.

### Backend

- [ ] T010 [US1] Create [backend/prompts/paraphrase_prompt.py](../../backend/prompts/paraphrase_prompt.py) with two things: (a) a module-level constant `PARAPHRASE_PROMPT_TEMPLATE` containing the exact prompt from research.md R1 with a `{q}` placeholder; (b) a function `parse_paraphrase_output(raw: str, original_question: str) -> list[str]` implementing the parser rules from research.md R1 (split on newline, strip, drop empties, drop leading-digit/bullet lines, drop case-insensitive matches to original after whitespace normalisation, cap at 5). Pure function; no I/O.
- [ ] T011 [P] [US1] Add unit tests to [backend/tests/test_paraphrase_generation.py](../../backend/tests/test_paraphrase_generation.py) covering `parse_paraphrase_output`:
   - happy path: 4 clean lines → 4 variants;
   - numbered lines ("1. foo", "2) bar") → stripped or dropped (per research.md R1 — document which you chose in T-last item 6);
   - bullet lines ("- foo", "* bar") → dropped;
   - duplicate of original (case/whitespace-insensitive) → dropped;
   - empty / whitespace-only lines → dropped;
   - 7 lines returned → capped at 5;
   - zero usable lines → returns `[]`.
   Assertions must check actual list contents, not just lengths. No mocks needed (pure function).
- [ ] T012 [US1] In [backend/services/validated_qa_service.py](../../backend/services/validated_qa_service.py), add a new `async def review_answer_multi(rating_id: str, action: str, corrected_answer: Optional[str], reviewer_email: str, variant_texts: list[str]) -> dict` helper. It MUST:
   1. Resolve shared fields **once** by replicating the answer_ratings lookup and validated_answer resolution pattern from the existing `review_answer` (do not import or call `review_answer` itself — it has single-row semantics that don't compose).
   2. For each variant in `variant_texts`, call `await embed_single(variant)` and build a per-row dict where `question_text` = variant, `question_embedding` = that variant's 768-vector stringified, and every other field (`validated_answer`, `validated_by`, `rating_id`, `manual_ids`, `source_chunks`, `equipment_type`, `fault_code`) is the shared value.
   3. If any embedding call raises, abort before any insert (satisfy FR-013 atomicity — no partial state).
   4. Perform a single `supabase.table("validated_qa").insert([...rows...]).execute()` batch call.
   5. Update `answer_ratings.review_status` once.
   6. Log one `log_activity` entry summarising the batch (`detail=f"{action} -> {new_status} ({len(rows)} variants)"`).
   7. Return `{"inserted_count": N, "validated_qa_ids": [...], "rating_id": rating_id, "status": new_status}`.
   **Do not modify `review_answer` or `check_validated_match`.** INV-1, INV-2, INV-4.
- [ ] T013 [US1] In [backend/routers/manuals.py](../../backend/routers/manuals.py), add `POST /api/manuals/paraphrase-variants` per [contracts/generate_variants.md](./contracts/generate_variants.md):
   - Admin-only auth (match existing `/review-answer` dependency).
   - Pydantic request model: `question_text: str` (1..500), `rating_id: Optional[str] = None`.
   - Build prompt via `PARAPHRASE_PROMPT_TEMPLATE.format(q=question_text)`.
   - Call `await resolver.generate(prompt)` inside try/except. On any exception from the resolver chain, log at WARN and return `{"variants": []}` with HTTP 200 (INV-3; research.md R6).
   - On success: parse with `parse_paraphrase_output(raw, question_text)`, return `{"variants": parsed}`.
- [ ] T014 [US1] In [backend/routers/manuals.py](../../backend/routers/manuals.py), add `POST /api/manuals/review-answer-with-variants` per [contracts/approve_with_variants.md](./contracts/approve_with_variants.md):
   - Admin-only auth.
   - Pydantic request: `rating_id: str`, `action: Literal["approve", "correct", "retro_expand"]`, `corrected_answer: Optional[str] = None`, `existing_validated_qa_id: Optional[str] = None`, `variants: list[str]` (1..10).
   - Validate: trim each variant, drop whitespace-only (FR-014). If list becomes empty → HTTP 400. If `action == "correct"` and `corrected_answer` is None → HTTP 400. If `action == "retro_expand"` and `existing_validated_qa_id` is None → HTTP 400.
   - For `action in ("approve", "correct")`: call `await validated_qa_service.review_answer_multi(...)`.
   - For `action == "retro_expand"`: (P2 — leave as `raise HTTPException(501, "retro_expand implemented in P2")` if you're only shipping MVP; wire it in Phase 4).
   - Return the service's result dict.
- [ ] T015 [P] [US1] Add backend integration tests to [backend/tests/test_paraphrase_generation.py](../../backend/tests/test_paraphrase_generation.py) using FastAPI TestClient and Supabase client mocks (follow the style of existing backend tests in that folder if present). Required test cases:
   - `test_paraphrase_endpoint_happy_path`: mock `resolver.generate` to return a 4-line string; POST to `/api/manuals/paraphrase-variants`; assert 200, `variants` length 4, original not in list.
   - `test_paraphrase_endpoint_provider_failure`: mock `resolver.generate` to raise `RuntimeError`; POST; assert 200 with `{"variants": []}` (INV-3).
   - `test_approve_with_variants_inserts_n_rows`: mock `embed_single` to return a deterministic 768-float vector (e.g., `[0.01] * 768` but with unique tweaks per variant), mock Supabase `insert` to capture the payload; POST `/review-answer-with-variants` with action=approve and 3 variants; assert exactly 3 rows in the insert payload, each with distinct `question_text`, distinct `question_embedding` strings, identical `validated_answer`, identical `rating_id`.
   - `test_approve_with_variants_rejects_empty_after_trim`: POST with `variants=["   ", ""]`; assert 400.
   - `test_approve_with_variants_rejects_over_10`: POST with 11 variants; assert 400.
   Each test must assert on **actual response content or captured insert payload**, not just mock call counts (Rule #3).

### Frontend

- [ ] T020 [US1] Create [frontend/lib/screens/manual_assistant/widgets/variants_modal.dart](../../frontend/lib/screens/manual_assistant/widgets/variants_modal.dart): a `Future<List<String>?> showVariantsModal({required BuildContext ctx, required String originalQuestion, required List<String> generatedVariants, String? notice})` function that opens a `BottomSheetContainer` modal. Inside:
   - Seed the chip list with `[originalQuestion, ...generatedVariants]`.
   - Render each chip as an editable `InputChip` wrapping a `TextField` (inline edit) with an `X` delete button.
   - Render an **Add variant** `FilledButton.tonal` below the chip list that appends an empty chip.
   - Render the `notice` string above the chip list if non-null (used for "automatic variants could not be generated").
   - **Save all** button: returns the current chip texts (trimmed, non-empty ones only). Disabled when zero non-empty chips.
   - **Cancel** button: returns `null`.
   - Per-variant length guard: reject paste content longer than 500 chars client-side.
- [ ] T021 [US1] Extend [frontend/lib/screens/manual_assistant/review_queue_tab.dart](../../frontend/lib/screens/manual_assistant/review_queue_tab.dart): change the existing Approve handler so it (a) calls `POST /api/manuals/paraphrase-variants` with the pending question; (b) whatever it returns (including `{"variants": []}` on failure), opens `showVariantsModal` — pass the `notice` "Automatic variants could not be generated." iff the list came back empty (INV-3, INV-5); (c) on a non-null modal return, calls `POST /api/manuals/review-answer-with-variants` with `action="approve"`, the `rating_id`, and the returned list; (d) shows a success toast "N verified answers saved" and refreshes the tab. The original direct single-row Approve call path is REMOVED — the modal is now the only path in the Review tab (INV-5 is satisfied because an empty variants list collapses the modal to "original only" → one row saved).
- [ ] T022 [P] [US1] Add [frontend/test/variants_modal_test.dart](../../frontend/test/variants_modal_test.dart) using `flutter_test`:
   - `variants_modal shows all seeded chips`: pump the widget with 1 original + 3 generated; find 4 chip widgets.
   - `variants_modal Save all returns non-empty trimmed texts`: seed with `["a", "  ", "b"]`, simulate Save all, expect result `["a", "b"]`.
   - `variants_modal Cancel returns null`: simulate Cancel, expect null.
   - `variants_modal Save all disabled when all chips empty`: pump with `["", "  "]`, assert Save button is disabled.
   - `variants_modal shows notice when provided`: pump with `notice: "Automatic variants could not be generated."`, find the notice text.
   Assert on **rendered widgets and return values**, not on any mocked service (Rule #3).

**Checkpoint US1 complete**: Backend endpoints live, tests green (`pytest backend/tests/test_paraphrase_generation.py -v`), modal widget and Review-tab wiring green (`flutter test test/variants_modal_test.dart`). Manual verification: run quickstart.md P1 scenario end-to-end. MVP may ship here.

---

## Phase 4: User Story 2 — Retro-Expand Existing Verified Entries (P2)

**Story goal**: Admin can paraphrase-expand entries already in the `validated_qa` table, via per-row trigger or tab-level "Generate variants for all", without re-verifying them.

**Independent test**: Pick one existing `validated_qa` row. Trigger retro-expand. Modal opens with paraphrases. Save all. New rows exist sharing the original row's `validated_answer` and `rating_id`; the original row is untouched.

- [ ] T030 [US2] Extend `validated_qa_service.review_answer_multi` (or add a sibling `retro_expand_multi`) to accept an `existing_validated_qa_id` path: read shared fields from that existing row instead of the answer_ratings row; do not update `answer_ratings.review_status`; otherwise identical loop (embed each variant → batch insert). Keep the shared-field resolution in one place so invariants INV-1/INV-2 cannot drift between approve and retro flows.
- [ ] T031 [US2] Wire the `retro_expand` branch in `POST /api/manuals/review-answer-with-variants` (previously stubbed in T014) to call the T030 helper.
- [ ] T032 [US2] Extend [frontend/lib/screens/manual_assistant/verified_answers_tab.dart](../../frontend/lib/screens/manual_assistant/verified_answers_tab.dart):
   - Add a per-row "Generate variants" icon button on each verified-answer card. On click: POST `/paraphrase-variants` with the row's `question_text`; open `showVariantsModal`; on non-null return, POST `/review-answer-with-variants` with `action="retro_expand"` and `existing_validated_qa_id` set.
   - Add a tab-level "Generate variants for all" button that iterates the loaded list client-side, opening the modal sequentially per entry. Cancel on any one entry skips that entry and advances. A failure on any single entry (empty paraphrase response, endpoint error) MUST NOT abort the sequence — surface the notice on the modal and continue.
- [ ] T033 [P] [US2] Add backend test `test_retro_expand_shares_existing_row_fields` to [backend/tests/test_paraphrase_generation.py](../../backend/tests/test_paraphrase_generation.py): mock Supabase `.select` to return a canned existing validated_qa row, POST with `action="retro_expand"` and 2 variants; assert the captured insert payload's rows share the existing row's `validated_answer` and `rating_id`, and that `answer_ratings` was NOT updated.

**Checkpoint US2 complete**: P2 quickstart scenario passes.

---

## Phase 5: User Story 3 — Graceful Degradation When All Providers Fail (P3)

**Story goal**: When `resolver.generate` fails for every provider in the chain, the admin can still complete the approval — the modal opens with only the original question, and Save all inserts exactly one `validated_qa` row.

**Independent test**: Force `resolver.generate` to raise (disable providers or mock in an integration harness). Run the P3 scenario from [quickstart.md](./quickstart.md). One row inserted, identical to pre-feature behaviour.

*Most of P3 is already implemented by T013 (endpoint returns empty list) and T021 (modal opens with notice when list is empty). This phase adds only the explicit test coverage and a smoke check.*

- [ ] T040 [P] [US3] Add backend test `test_approve_with_variants_single_row_fallback` to [backend/tests/test_paraphrase_generation.py](../../backend/tests/test_paraphrase_generation.py): POST `/review-answer-with-variants` with `action="approve"` and `variants=[original_question_only]`; assert the captured insert payload contains exactly 1 row, and it carries the same shared fields as a multi-row happy-path case would. Confirms INV-5.
- [ ] T041 [P] [US3] Add frontend widget test `variants_modal_with_notice_is_savable_with_only_original` to [frontend/test/variants_modal_test.dart](../../frontend/test/variants_modal_test.dart): pump the modal with only the original question seed and `notice="Automatic variants could not be generated."`; simulate Save all; assert return is `[original]` (single-element list) and Save button was enabled throughout.
- [ ] T042 [US3] Manually execute quickstart.md scenario P3 (temporarily disable providers) and record the observed behaviour in T-last item 8 as a smoke-test disclosure.

**Checkpoint US3 complete**: P3 quickstart scenario passes; fallback tests green.

---

## Phase 6: Polish & Handoff

- [ ] T050 Run the full backend test file once more: `cd backend && pytest tests/test_paraphrase_generation.py -v`. Capture full output.
- [ ] T051 Run the full frontend test file once more: `cd frontend && flutter test test/variants_modal_test.dart`. Capture full output.
- [ ] T052 Run `git status` and confirm only files from the ALLOWED list in "Scope boundary" are modified or created. If anything else is touched, revert or justify.
- [ ] T053 Execute quickstart.md scenarios P1, P2, P2b, P3 manually in the app. Record any deviation from expected behaviour in T-last item 6 or 8.
- [ ] T054 Commit per the chosen strategy (combined or backend+frontend split). **Do not commit `backend/version.json`** — per project feedback it's managed on the server.

---

## T-last: Handoff report (final, mandatory)

- [ ] T-last Produce an 8-item handoff report as a single comment block at the end of your final response. Every item is required; write "none" when genuinely empty but never omit a numbered item.

  1. **Commit SHA(s)** — one for backend, one for frontend, or one combined. State which strategy you used.
  2. **Full `git diff HEAD~1`** — unified diff of the commit(s). If split, provide both diffs.
  3. **Full `pytest backend/tests/test_paraphrase_generation.py -v` output** — complete stdout, not a summary. Include any warnings.
  4. **Full `flutter test test/variants_modal_test.dart` output** — complete stdout.
  5. **Clean final `git status` output** — should show working tree clean after commit.
  6. **Design judgment calls** — anywhere the spec or contracts left ambiguity and you had to choose. Include the numbered-line parser behaviour from T011 (strip numbering vs drop the line), any Pydantic validator shape choices, toast wording, modal dimensions, etc. Quote the ambiguity and state your choice.
  7. **Scope concerns encountered** — anything that tempted you toward a FORBIDDEN file, or any point where the ALLOWED list felt insufficient. Empty list is a fine answer; write "none" if so.
  8. **Disclosures** — any shortcut, skipped task, re-interpreted invariant, failed attempt you backtracked from, or assumption not covered in the spec. Be explicit. "Skipped T042 because I couldn't safely disable providers in a dev session — flagging for review" is the right shape.

---

## Dependencies

- T001 gates everything.
- T002–T005 are read-only inspections; all four can run in parallel, all must complete before T010.
- T010 gates T011, T013 (T013 imports from T010).
- T012 gates T014 (T014 calls the helper); T012 is independent of T010–T011.
- T013 and T014 are in the same file; do T013 first, then T014.
- T015 requires T013 and T014 complete.
- T020 gates T021 and T022.
- US1 (T010–T022) must complete before US2 (T030–T033) starts — US2 extends T014 and T020's modal.
- US3 (T040–T042) depends only on US1 completion; does not need US2.
- T050–T054 run last, sequentially.
- T-last is the final task.

## Parallelisation opportunities

- **Setup read phase**: T002, T003, T004, T005 are all read-only and can run in parallel.
- **Backend+frontend split within US1**: after T010 and T012, one agent can drive T013/T014/T015 while another drives T020/T021/T022.
- **Test tasks marked [P]**: T011, T015, T022, T033, T040, T041 can each be authored while their sibling implementation task is being polished (but tests must still pass against the final implementation — don't claim done until both exist and both run green together).

## Implementation strategy

1. **MVP first**: complete Phase 1 → Phase 3 (US1) only. Ship. This delivers the primary P1 value: every new admin approval goes through the variants modal.
2. **Second increment**: Phase 4 (US2) retro-expansion — catches up the existing ~16 verified entries.
3. **Third increment**: Phase 5 (US3) — mostly test coverage for behaviour US1 already implemented.
4. **Polish + handoff**: Phase 6 and T-last.

Each increment is independently releasable and testable against its own quickstart.md scenario.

---

**Total tasks**: 5 setup + 10 US1 + 4 US2 + 3 US3 + 5 polish + 1 handoff = **28 tasks**.
**MVP task count (P1 only)**: 5 setup + 10 US1 + 5 polish + 1 handoff = **21 tasks**.
