---
description: "Task list for opencode implementation — spec 085 Verified Answer Variants"
---

# Tasks: Verified Answer Variants

**Input**: Design documents from `/specs/085-verified-answer-variants/`
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)
**Branch**: `085-verified-answer-variants` (already checked out)
**Implementer**: opencode · **Reviewer**: Claude Code (superpowers code review after completion)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- File paths are absolute or relative-from-repo-root

---

## Implementation policies (read first)

These rules override any contradicting defaults. If a task instruction conflicts with one of these, ask before proceeding.

1. **Reuse, don't rebuild.** The variants modal (`frontend/lib/screens/manual_assistant/widgets/variants_modal.dart`), the paraphrase endpoint (`POST /manuals/paraphrase-variants`), and the shared-`rating_id` grouping (`backend/services/validated_qa_service.py::review_answer_multi`, lines ~629-673) all exist. Extend them; do not duplicate their logic.
2. **Follow the atomic embedding pattern.** Pre-compute **all** embeddings before **any** DB write. Use `await embed_single(text)` (already imported in `validated_qa_service.py`). If any embedding raises, propagate the exception — do NOT swallow it, do NOT attempt partial writes. Mirror the comment style `# FR-008a atomicity` on the fail-fast block.
3. **Use existing helpers:** `log_activity` from `backend.utils.activity` (fire-and-forget, do not `await`), `_extract_equipment_type`, `_extract_fault_code` from `validated_qa_service.py`. Do not reimplement.
4. **Minimal comments.** Add a comment only when the *why* is non-obvious (hidden constraint, tricky invariant, fail-fast intent). Never write "// added for spec 085" or similar task-referencing comments.
5. **No backwards-compatibility shims, no feature flags, no config knobs, no new abstractions.** Change the code directly.
6. **No autosave.** The variants flow only writes on explicit "Save all." Do not add draft persistence, local storage, or auto-retry.
7. **Never commit `backend/version.json`** from the dev machine — it is managed on the server.
8. **No Arabic-specific UI handling.** This feature lives in the AI-assistant surface; English-only UI is fine (per project convention for AI-assistant features).
9. **Restart the backend** (`sudo systemctl restart document_server.service`) after deploying router changes. Frontend returns generic errors otherwise. This restart is the reviewer's responsibility at deploy time; you do not need to run it while implementing locally, but the task list must include the reminder.
10. **Do not add new Python or Dart dependencies.** Everything required is already in `requirements.txt` / `pubspec.yaml`.
11. **Follow the contracts exactly.** See [contracts/get-variants.md](./contracts/get-variants.md) and [contracts/put-variants.md](./contracts/put-variants.md). Request/response shapes and status codes are binding.
12. **Preserve existing Edit dialog behavior.** FR-013: no regression in question/answer editing, delete, or rating display. The "Generate variants" button is purely additive.

---

## Phase 1: Setup

**Purpose**: No setup work needed — branch is checked out, spec/plan/contracts are written, and no new dependencies are introduced. Skip directly to Phase 2.

---

## Phase 2: Foundational

**Purpose**: Shared service-layer primitives consumed by both endpoints in later phases.

**⚠️ CRITICAL**: No user-story phase may begin until T001 and T002 are complete.

- [ ] T001 Add `get_variants_group(qa_id: str) -> dict` to [backend/services/validated_qa_service.py](../../backend/services/validated_qa_service.py). Loads the target row, returns `{qa_id, rating_id, question_text, validated_answer, variants: [{id, question_text}]}` with `variants` sorted by `question_text` ASC. If `rating_id IS NULL`, `variants` is a list of one (the target row itself). Raises `ValueError("not found")` if `qa_id` has no row. No embedding calls, no writes, no audit log. Match the style and error-handling conventions of neighbors `update_verified_answer` and `delete_verified_answer` in the same file.

- [ ] T002 Add `async reconcile_variants(qa_id: str, submitted_variants: list[str], editor_email: str) -> dict` to [backend/services/validated_qa_service.py](../../backend/services/validated_qa_service.py). Implements the full reconcile described in [research.md R-2](./research.md) and [contracts/put-variants.md](./contracts/put-variants.md).
   - Input validation first (raise `ValueError` on violation):
     - Dedupe `submitted_variants` by `strip().casefold()`, preserving first-seen original casing.
     - If post-dedupe list is empty → `ValueError("at least one variant required")`.
     - If any variant length (after trim) > 500 → `ValueError("variant exceeds 500 characters")`.
   - Load target row. `ValueError("not found")` if missing.
   - If `rating_id IS NULL`, generate `str(uuid.uuid4())`, UPDATE that single row's `rating_id`, and continue with the new id. Use the same pattern as `create_verified_answer`'s `synthetic_rating_id` (line ~465).
   - Load all stored rows with `rating_id = <the id>`. Build `stored_by_norm` and `submitted_norm`.
   - Compute `to_delete` (ids) and `to_insert` (original strings) set-differences.
   - **Pre-compute all embeddings for `to_insert` first (fail-fast atomicity, FR-008a).** Mirror the pattern and comment style from `review_answer_multi` lines ~629-650.
   - DELETE `to_delete` by id, then INSERT `to_insert` rows. Each new row copies `validated_answer`, `manual_ids`, `source_chunks`, `is_reflagged` from an existing sibling (or from the target row itself if it's the last row and was about to be deleted — guard against that by reading shared fields *before* the delete). Set `validated_by=editor_email`, `validated_at=now()`, `rating_id=<the id>`, `question_embedding`, `equipment_type`, `fault_code` per variant.
   - Fire-and-forget `log_activity(editor_email, category="admin", action="updated_verified_answer_variants", target_label=<target row's original question, truncated to 80>, target_id=qa_id, detail=f"added={len(to_insert)}, removed={len(to_delete)}, final={len(submitted_variants)}")`.
   - Return `{qa_id, rating_id, added_count, removed_count, variants: [{id, question_text}, ...]}` where `variants` is the full final set sorted by `question_text` ASC.
   - **Do NOT modify `validated_answer`** anywhere in this function (INV-A from [data-model.md](./data-model.md)).

**Checkpoint**: Service layer ready. Both endpoints below depend on these functions.

---

## Phase 3: User Story 1 — Broaden with AI paraphrases (Priority: P1) 🎯 MVP

**Goal**: Admin clicks a verified answer row, clicks "Generate variants", sees saved siblings + AI paraphrases, edits/adds/removes, saves, and the full-replace reconcile persists the new variant set.

**Independent Test**: Run the User Story 1 section of [quickstart.md](./quickstart.md). Expected outcome: a user question matching any newly-saved phrasing returns the verified answer verbatim.

### Backend — endpoints

- [ ] T003 [US1] Add route handler `get_verified_answer_variants` in [backend/routers/manuals.py](../../backend/routers/manuals.py) for `GET /manuals/verified-answers/{qa_id}/variants`, matching [contracts/get-variants.md](./contracts/get-variants.md). Authorize via the same `user_email` admin check used by the neighboring `update_verified_answer` / `delete_verified_answer` routes. Call `validated_qa_service.get_variants_group(qa_id)`. Map `ValueError("not found")` → `HTTPException(404)`, unauthorized → `HTTPException(403)`.

- [ ] T004 [US1] Add route handler `update_verified_answer_variants` in [backend/routers/manuals.py](../../backend/routers/manuals.py) for `PUT /manuals/verified-answers/{qa_id}/variants`, matching [contracts/put-variants.md](./contracts/put-variants.md). Accept JSON body `{user_email, variants}`. Admin-check `user_email`. Call `await validated_qa_service.reconcile_variants(qa_id, variants, user_email)`. Error mapping:
   - `ValueError("not found")` → 404
   - `ValueError("at least one variant required")` / `ValueError("variant exceeds 500 characters")` → 400 (pass the message into `detail`)
   - Any exception whose message contains `"embedding"` (case-insensitive) OR any exception raised from inside the pre-compute-embeddings block → 503 with `detail="embedding service unavailable; please retry"`. Use a narrow try/except around the `embed_single` loop inside `reconcile_variants` that re-raises a typed sentinel (define `class EmbeddingUnavailable(RuntimeError): pass` near the top of `validated_qa_service.py`), and the router catches that.
   - Other exceptions → 500, re-raised.

### Backend — tests

- [ ] T005 [US1] Create [backend/tests/test_verified_answer_variants.py](../../backend/tests/test_verified_answer_variants.py) with pytest coverage for `reconcile_variants` only (pure service-level tests; mock `supabase.table(...)` and `embed_single` using the same patterns used in [backend/tests/test_paraphrase_generation.py](../../backend/tests/test_paraphrase_generation.py) and [backend/tests/test_validated_qa_lookup.py](../../backend/tests/test_validated_qa_lookup.py)). Required test cases:
   - `test_reconcile_insert_only`: target has 1 stored row, submitted list has 3 (including the existing). Expect 2 inserts, 0 deletes, embeddings called exactly twice.
   - `test_reconcile_delete_only`: target has 3 stored rows, submitted list has 1 (an existing one). Expect 0 inserts, 2 deletes, embeddings NOT called.
   - `test_reconcile_mixed`: target has 3 stored rows, submitted list replaces 1 with a new one. Expect 1 insert, 1 delete, embeddings called exactly once.
   - `test_reconcile_normalized_match`: stored `"Where are the locations?"`; submitted `"  WHERE ARE THE LOCATIONS?  "`. Expect zero inserts/deletes (matched by normalize).
   - `test_reconcile_empty_rejected`: submitted list is `[]` (or all whitespace after dedup). Expect `ValueError("at least one variant required")`; zero DB calls.
   - `test_reconcile_length_rejected`: submitted list has one 501-char string. Expect `ValueError("variant exceeds 500 characters")`; zero DB calls.
   - `test_reconcile_legacy_rating_id_backfill`: target row has `rating_id = None`. Expect an UPDATE call setting `rating_id` to a fresh UUID BEFORE any insert/delete, and the inserts using the same id.
   - `test_reconcile_embedding_failure_is_atomic`: first `embed_single` call succeeds, second raises. Expect `EmbeddingUnavailable` (or whatever sentinel chosen) and ZERO delete/insert calls to supabase.
   - `test_reconcile_logs_activity`: happy-path save triggers one `log_activity` call with `action="updated_verified_answer_variants"` and `detail` containing `"added=", "removed=", "final="`.
   - `test_reconcile_does_not_touch_validated_answer`: the DB update chain never contains the `validated_answer` key (INV-A).

### Frontend — service layer

- [ ] T006 [US1] In [frontend/lib/services/manual_assistant_service.dart](../../frontend/lib/services/manual_assistant_service.dart), add two methods:
   - `Future<Map<String, dynamic>> getVerifiedAnswerVariants({required String qaId, required String userEmail})` → GET `/manuals/verified-answers/{qaId}/variants?user_email=...`. Throw on non-200 with body message.
   - `Future<Map<String, dynamic>> updateVerifiedAnswerVariants({required String qaId, required String userEmail, required List<String> variants})` → PUT with body `{"user_email": userEmail, "variants": variants}`. On 503 throw a specific `Exception('embedding service unavailable — please retry')`. On 400 propagate the backend `detail` as the exception message. Match the style of the existing `updateVerifiedAnswer` and `deleteVerifiedAnswer` methods in the same file.

### Frontend — variants modal extension

- [ ] T007 [US1] Extend [frontend/lib/screens/manual_assistant/widgets/variants_modal.dart](../../frontend/lib/screens/manual_assistant/widgets/variants_modal.dart):
   - Add an optional `Set<String>? savedVariantNormalizedTexts` parameter to both `showVariantsModal` and `VariantsModal`. Null = treat all chips as "new" (preserves existing caller behavior from the review queue). Non-null = chip is "saved" iff `_normalize(controller.text) ∈ savedVariantNormalizedTexts`.
   - Plumb it into `_VariantChip` as `bool isSaved`.
   - When `isSaved == true`: prefix the chip's label with a small (14 px) `Icon(Icons.verified_outlined, color: Colors.green.shade700)` and keep the existing `surfaceContainerHighest` background.
   - When `isSaved == false` and no length error: use `surfaceContainer` background with a 1-dashed-pixel border (use `Border.all(color: theme.colorScheme.outlineVariant, width: 1)` if dashed is inconvenient — close enough). No icon.
   - Saved status is recomputed on each text change (so an admin editing a saved chip past the point of matching the saved text visually demotes it to "new"). Keep this in `build` with a synchronous check on the controller's text.
   - Add `String _normalize(String s) => s.trim().toLowerCase();` as a top-level private helper in the file. Export nothing else.
   - Preserve the existing caller in [frontend/lib/screens/manual_assistant/review_queue_tab.dart](../../frontend/lib/screens/manual_assistant/review_queue_tab.dart): no changes there. Not passing `savedVariantNormalizedTexts` keeps all chips "new" which matches current behavior.

### Frontend — Verified Answers tab wiring

- [ ] T008 [US1] In [frontend/lib/screens/manual_assistant/verified_answers_tab.dart](../../frontend/lib/screens/manual_assistant/verified_answers_tab.dart):
   - Add a "Generate variants" `TextButton` in the `actions` list of `_showEditDialog`'s `AlertDialog`, placed after the delete icon and before the Cancel button (so order is: Delete · Generate variants · Cancel · Save).
   - Its `onPressed` calls a new method `Future<void> _openVariantsFlow(Map<String, dynamic> entry, TextEditingController questionCtrl) async`.
   - `_openVariantsFlow` behavior:
     1. Fire `_service.getVerifiedAnswerVariants(qaId: entry['id'], userEmail: widget.userEmail)` and `_service.askParaphraseVariants(questionCtrl.text, userEmail: widget.userEmail)` in parallel via `Future.wait` with `eagerError: false` so a paraphrase failure doesn't cancel the siblings fetch. (If parallel error-handling gets ugly, sequential siblings-first is fine — prefer clarity.)
     2. On siblings-fetch failure, surface a snack-bar and return without opening the modal.
     3. On paraphrase failure, proceed with siblings only and pass `notice: 'AI paraphrases are unavailable right now. You can still edit, add, or remove variants and save.'` into `showVariantsModal`.
     4. Compose the modal's pre-filled list = existing siblings (as-is texts) + AI paraphrases (the successful ones). Deduplicate by normalized text so an AI paraphrase identical to an existing sibling does not appear twice.
     5. Build `savedVariantNormalizedTexts = siblings.map((s) => _normalize(s['question_text'])).toSet()` (inline, or import the modal's helper).
     6. Call `showVariantsModal(context: context, originalQuestion: entry['question_text'], generatedVariants: [existingSiblingsThenNewParaphrases minus the originalQuestion since it's already passed as `originalQuestion`], notice: <paraphrase-failure message or null>, savedVariantNormalizedTexts: <the set above>)`.
     7. If the modal returns a non-null list: call `await _service.updateVerifiedAnswerVariants(qaId: entry['id'], userEmail: widget.userEmail, variants: result)`. On success: show a snack-bar "Verified answer variants updated" and call `_loadEntries()` to refresh the list. On failure: show the error message in a snack-bar.
   - The existing Edit dialog's Save flow must remain untouched — admins can still save question+answer changes via the existing Save button without engaging the variants flow.

**Checkpoint**: US1 fully functional. A user asking a question that matches any of the saved variants returns the verified answer.

---

## Phase 4: User Story 2 — Remove a stale variant (Priority: P2)

**Goal**: Admin removes a chip and saves; reconcile deletes the corresponding stored row.

**Independent Test**: User Story 2 section of [quickstart.md](./quickstart.md).

### Implementation

- [ ] T009 [US2] Verify — no new code: the reconcile function already handles deletions (T002 covers delete-path). This task is a VERIFICATION task: manually run through the User Story 2 quickstart section. Mark complete only when the described behavior is observed end-to-end.

- [ ] T010 [US2] Confirm the modal's existing `_canSave` getter (already present in [variants_modal.dart](../../frontend/lib/screens/manual_assistant/widgets/variants_modal.dart), line ~65) correctly returns `false` when the admin has removed every chip. No code change expected; if `_canSave` evaluates `true` for an empty non-overflow list, add a guard: `_nonEmptyTexts.isNotEmpty`.

**Checkpoint**: US1 and US2 both work. Admin can grow AND prune the variant set.

---

## Phase 5: User Story 3 — Paraphrase service unavailable (Priority: P3)

**Goal**: When the paraphrase endpoint fails or times out, the admin still sees the modal with saved siblings + notice banner, and can save manual edits.

**Independent Test**: User Story 3 section of [quickstart.md](./quickstart.md) — stop Ollama, open the modal, observe the banner, add a manual variant, save.

### Implementation

- [ ] T011 [US3] Verify that T008's paraphrase-failure branch opens the modal with the correct `notice` banner and no AI paraphrase chips. Add a defensive try/catch around the `askParaphraseVariants` call (if not already implicit via `Future.wait(eagerError: false)`) so a thrown exception becomes a silent empty-list with the notice banner, not a full-screen error.

- [ ] T012 [US3] Spot-check: with paraphrase unreachable, the admin-added manual variant still saves successfully (because the embedder — a separate service — is still up). This is behavior verification, not code change. Include the manual test in the PR description.

**Checkpoint**: All three user stories work. Graceful degradation verified.

---

## Phase 6: Polish & Deploy Reminders

- [ ] T013 Run [quickstart.md](./quickstart.md) end-to-end in the dev environment. Check off every step that passes. File any failures as GitHub issues or fix inline.

- [ ] T014 `flutter analyze frontend/lib/services/manual_assistant_service.dart frontend/lib/screens/manual_assistant/widgets/variants_modal.dart frontend/lib/screens/manual_assistant/verified_answers_tab.dart` — must report zero new issues vs baseline. Existing unrelated lints (e.g. `depend_on_referenced_packages` on `http_parser`) are acceptable to leave.

- [ ] T015 `cd backend && python -m pytest tests/test_verified_answer_variants.py -v` — all tests green. Also run the full backend test suite (`python -m pytest`) and ensure no regressions.

- [ ] T016 Do NOT commit `backend/version.json`. Do NOT bump the Flutter version manually — that happens via `scripts/deploy_frontend.sh` during deploy.

- [ ] T017 Open a PR from `085-verified-answer-variants` to `main` with title `feat(085): verified answer variants` and body that includes:
   - A screenshot/GIF of the modal open with saved + new chips visibly distinguished.
   - A note that backend must be restarted on the server after merge: `sudo systemctl restart document_server.service`.
   - A link back to [spec.md](./spec.md) and [quickstart.md](./quickstart.md).
   - The list of FR IDs covered (FR-001…FR-015, FR-008a).

- [ ] T018 (Reviewer — Claude Code, not opencode) Run `superpowers:code-reviewer` agent against the final PR diff, referencing this tasks.md and [spec.md](./spec.md) as the source of truth. Address any returned findings before merging.

---

## Dependencies & Execution Order

### Serial chain
- T001, T002 → T003, T004 (router depends on service)
- T002 → T005 (tests need the function)
- T003, T004 → T006 (frontend service calls real endpoints for smoke-testing)
- T006, T007 → T008 (tab wiring needs both frontend service and the modal extension)
- T008 → T009, T010 (US2 verifies against the implemented flow)
- T008 → T011, T012 (US3 verifies against the implemented flow)
- T008–T012 → T013–T017
- T017 → T018

### Parallel opportunities
- T001 and T007 are different files, zero shared context → can run in parallel.
- T005 (backend tests) and T006 (frontend service methods) are different files and different layers → parallel.
- Within T005, each listed test case is independent and the file is serial (same file), but the test bodies can be authored in any order.

### Within each user story
- No test-first requirement imposed by the user; tests exist only at the backend service layer (T005). Frontend changes are verified via the quickstart flow.

---

## Parallel Example: kick off US1 after foundations

Once T001 + T002 are done:

```text
Agent 1: T003, T004     # backend endpoints (serial, same file)
Agent 2: T005           # backend tests (independent file)
Agent 3: T006, T007     # frontend service + modal extension (different files)
```

T008 cannot start until T006 and T007 land.

---

## Implementation Strategy

### MVP (stop here if time-boxed)

1. Phase 2: T001, T002 — service functions.
2. Phase 3: T003–T008 — endpoints, tests, UI.
3. **STOP and VALIDATE**: run User Story 1 section of quickstart.md. Deploy if clean.

### Full delivery

1. MVP + Phase 4 (US2 verification) + Phase 5 (US3 graceful degradation verification).
2. Polish (T013–T017). Open PR. Claude reviews (T018).

---

## Definition of Done (opencode self-check before handing off to reviewer)

Before marking implementation complete and opening the PR, confirm ALL of the following:

- [ ] Every task T001–T017 is checked off in this file and committed.
- [ ] Backend tests (T005) all pass locally.
- [ ] `flutter analyze` shows no new issues in the three touched frontend files.
- [ ] `git diff origin/main` contains **no** changes to `backend/version.json`, `frontend/pubspec.yaml`, `frontend/pubspec.lock`, or any migration file.
- [ ] Spec invariants INV-A through INV-E are visibly preserved in the reconcile function (skim `reconcile_variants` and confirm).
- [ ] The modal visually distinguishes saved vs new chips in the dev browser. Paste a screenshot into the PR.
- [ ] Opening "Generate variants" on a legacy entry with `rating_id IS NULL`, saving one new variant, and re-querying Supabase confirms the legacy row now has a non-null `rating_id` and the new variant shares it.
- [ ] No backwards-compatibility shims, no feature flags, no unused helper functions, no "TODO"s, no "// spec 085" reference comments.

If any box is unchecked, fix it before opening the PR. Reviewer will run `superpowers:code-reviewer` agent against the diff and against this file.

---

## Notes

- Spec 068 introduced shared-rating groups; this spec only adds reconcile-on-save on top. If you find yourself considering schema changes, stop and re-read [data-model.md](./data-model.md) — there should be none.
- The variants modal is already used by the review queue. Do not break that path: if `savedVariantNormalizedTexts` is `null`, the modal must render identically to today.
- Concurrent-edit conflict resolution is deliberately out of scope (last-write-wins). Do not add optimistic locking.
