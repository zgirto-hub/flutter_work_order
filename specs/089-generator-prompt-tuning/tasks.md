---
description: "Task list for spec 089 — Generator Prompt Tuning (RAG Over-Refusal Fix)"
---

# Tasks: Generator Prompt Tuning (RAG Over-Refusal Fix)

**Input**: Design documents from `/specs/089-generator-prompt-tuning/`
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/prompt-contract.md](./contracts/prompt-contract.md), [quickstart.md](./quickstart.md)

**Tests**: This spec does NOT generate new unit/integration test files. The validation harness is the existing `backend/tests/test_rag_quality.py` suite, which is *modified* (not created) in US2. No new test framework.

**Organization**: Two user stories. US1 (P1, MVP) is the prompt rewrite itself. US2 (P2) is the merge-blocking must-refuse regression gate — independent file, independently testable, protects US1.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2)
- Exact file paths in every description

## Path Conventions

Web application — paths per [plan.md § Project Structure](./plan.md). All relative to repo root `C:\Development\flutter_work_order\`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Load current state, gather few-shot candidates, confirm assumptions.

- [ ] T001 Read [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py) lines 200–305 and quote the full current `DOCUMENT_QA_SYSTEM_PROMPT` + all three `_NOT_FOUND_*` constants + the `VALIDATED_QA_SYSTEM_PROMPT` verbatim into a scratch note (will become the "Before" section of the PR description).
- [ ] T002 [P] Grep [backend/services/ollama_generator.py](../../backend/services/ollama_generator.py) and [backend/services/](../../backend/services/) for any other occurrence of `DOCUMENT_QA_SYSTEM_PROMPT` or the refusal string — confirm single source of truth (plan §3 assumption).
- [ ] T003 [P] Run the `validated_qa` selection query from [quickstart.md §2](./quickstart.md) against the production Supabase (via MCP `mcp__claude_ai_Supabase__execute_sql` or dashboard) — obtain the top 20 candidate rows.

**Checkpoint**: current prompt captured, validated_qa candidate pool in hand.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Irreversibility guard — ensure rollback path is clean before touching production files.

- [ ] T004 Confirm branch `089-generator-prompt-tuning` has a clean tree relative to its starting commit (`git status` should show no uncommitted changes at task start) — if not, commit or stash before proceeding. The branch already contains: `specs/089-generator-prompt-tuning/*` + the baseline `rag_quality_results.json`. No other files should be modified yet.

**Checkpoint**: branch clean, ready for atomic US1+US2 edits.

---

## Phase 3: User Story 1 — Rewrite `DOCUMENT_QA_SYSTEM_PROMPT` (Priority: P1) 🎯 MVP

**Goal**: Replace the `"only answer if explicitly stated"`-style refusal rule in `DOCUMENT_QA_SYSTEM_PROMPT` with balanced ANSWER / REFUSE / NEVER INVENT rules plus four few-shot examples (three sourced from `validated_qa`, one synthetic refuse). Deliver the prompt edit atomically so `git revert` works.

**Independent Test**: After US1 alone (without US2), re-run `python backend/tests/test_rag_quality.py --base-url https://zorin.taila92fe8.ts.net` and compare aggregate score + Cat 6 + `rag_diagnostic_log` reason-code distribution to the 33/87 baseline. US1 is "done" when these numbers meet SC-001, SC-002, SC-003, SC-004, SC-007 floors. SC-005 (must-refuse) can only be verified once US2 lands, but SC-006 (no NEW hallucinations) can be verified by eyeballing the Cat 6 section of the results JSON.

### Implementation for User Story 1

- [ ] T005 [US1] Using the 20-row candidate pool from T003, hand-pick 3 `validated_qa` rows that together cover the three patterns from [spec.md §5.2.1](./spec.md) (terse-procedural, partial-information, paraphrased/alias-heavy). Record the chosen `id` values in a scratch note for the eventual PR description. If <3 qualifying rows exist after scanning the top 50, halt and flag per [spec.md §5.2.3](./spec.md).
- [ ] T006 [US1] Edit [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py): insert the ANSWERING RULES block from [contracts/prompt-contract.md §1.1](./contracts/prompt-contract.md) as the first rule block in `DOCUMENT_QA_SYSTEM_PROMPT`, immediately after the opening system description (between lines 236 and 237 in the current file).
- [ ] T007 [US1] Edit [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py): insert the EXAMPLES block from [contracts/prompt-contract.md §1.2](./contracts/prompt-contract.md) immediately after the ANSWERING RULES block. Fill the three Q/Chunks/A triples using the `validated_qa` rows selected in T005 (Q = `question_text` verbatim, A = `validated_answer` verbatim, Chunks = implementer's 1-line summary of the row's source section). Keep the synthetic "cloud database scaling" refuse example verbatim.
- [ ] T008 [US1] Edit [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py): **delete** the existing `INSUFFICIENT CONTEXT:` block (currently lines ~292–297) — it contradicts the new REFUSE clause in ANSWERING RULES. Do NOT also delete the `_NOT_FOUND_KNOWLEDGE_BASE` reference; it stays inside the new REFUSE clause via f-string substitution.
- [ ] T009 [US1] Verify the 7 invariants from [contracts/prompt-contract.md §3](./contracts/prompt-contract.md) using `git diff` + `grep`:
  - I-01: diff shows no changes on lines 215–226 (`VALIDATED_QA_SYSTEM_PROMPT`)
  - I-02: diff shows no changes on lines 210–212 (`_NOT_FOUND_*` constants)
  - I-03: diff shows no changes on `_SENTINEL_PHRASES` list
  - I-04: `grep -c "^DOCUMENT_QA_SYSTEM_PROMPT = " backend/services/manual_rag_service.py` returns `1`
  - I-05: `grep -c "_NOT_FOUND_KNOWLEDGE_BASE" backend/services/manual_rag_service.py` returns ≥ 2 (constant definition + prompt reference)
  - I-06: `grep -Ei "bos>|end_of_turn|i'll help you" backend/services/manual_rag_service.py` returns zero matches
  - I-07: The prompt string body is under 16 KB raw bytes (rough char count OK)

**Checkpoint**: US1 complete in working tree. Do NOT commit yet — US2 lands in the same atomic commit per spec §5.4.

---

## Phase 4: User Story 2 — Merge-Blocking Must-Refuse Regression Gate (Priority: P2)

**Goal**: Extend `backend/tests/test_rag_quality.py` with a `must_refuse: bool` per-entry flag and runner logic that exits non-zero if any flagged question flips from ungrounded to grounded. This is the SC-005 safety net: without it, over-loose prompt tuning in US1 could silently introduce hallucinations on credential-type questions.

**Independent Test**: Without changing any prompt, flip one Cat 6 entry's `must_refuse=True` flag and manually mutate the backend to return `grounded=True` for it; re-run the suite — expect exit code 2 and a `REGRESSION:` line in the output. Revert the manual mutation before proceeding. This proves the gate fires as specified.

### Implementation for User Story 2

- [ ] T010 [P] [US2] Edit [backend/tests/test_rag_quality.py](../../backend/tests/test_rag_quality.py): add `must_refuse: bool = False` to the `TestQuestion` dataclass (currently at lines 37–44). Default `False` preserves all existing entries' behavior.
- [ ] T011 [P] [US2] Edit [backend/tests/test_rag_quality.py](../../backend/tests/test_rag_quality.py): within the `TESTS: list[TestQuestion] = [...]` literal, add `must_refuse=True` to every entry currently in Category 6 (Hallucination Resistance — `category=6`) and to the specific entry with `question="amhs router login credentials"`. Do NOT add `must_refuse=True` to any entry in categories 1–5 or 7–12 in this task.
- [ ] T012 [US2] Edit [backend/tests/test_rag_quality.py](../../backend/tests/test_rag_quality.py) runner logic:
  - After the existing pass/fail evaluation per question, add a branch: if `test.must_refuse` and response's `grounded` is truthy → increment a new `regression_count` counter and print `REGRESSION: <question>` to the FAILURES section (distinct from the `Q:` / `FAIL:` format).
  - After the existing `RESULTS SUMMARY` block, if `regression_count > 0`, print a standalone line `SC-005 REGRESSION DETECTED — MERGE BLOCKED` and call `sys.exit(2)`.
  - All other existing outputs (per-category table, totals, hallucination list, avg latency) are preserved byte-for-byte.

**Checkpoint**: US2 complete in working tree. Ready for the atomic US1+US2 commit.

---

## Phase 5: Atomic Commit + Deploy (Shared, post-US1+US2)

**Purpose**: Land US1 + US2 as one `git revert`-friendly commit and bring the live backend up on the new prompt.

- [ ] T013 `git status` + `git diff --stat` — expect exactly two modified files: `backend/services/manual_rag_service.py` and `backend/tests/test_rag_quality.py`. No other changes.
- [ ] T014 Atomic commit per [quickstart.md §5](./quickstart.md):
  ```bash
  git add backend/services/manual_rag_service.py backend/tests/test_rag_quality.py
  git commit -m "spec 089: rewrite DOCUMENT_QA_SYSTEM_PROMPT to reduce over-refusal

  - Insert ANSWERING RULES + EXAMPLES blocks (few-shot sourced from
    validated_qa IDs <id1>, <id2>, <id3>).
  - Delete contradictory INSUFFICIENT CONTEXT block.
  - Preserve SAFETY RULES, REGULATORY REFERENCES, CONFLICT HANDLING,
    LANGUAGE, SYSTEM AMBIGUITY byte-for-byte.
  - VALIDATED_QA_SYSTEM_PROMPT untouched.
  - Test suite: add must_refuse flag + sys.exit(2) on flipped Cat 6 entries."
  ```
  Fill `<id1>`, `<id2>`, `<id3>` from T005. Do NOT amend; future iterations (if needed) land as fresh commits.
- [ ] T015 `git push -u origin 089-generator-prompt-tuning`.
- [ ] T016 Deploy to server: `ssh zorin@zorin.taila92fe8.ts.net 'cd ~/flutter_work_order && git fetch && git checkout 089-generator-prompt-tuning && git pull && sudo systemctl restart document_server.service'`. Wait ~10 s. Verify backend is up with `curl -s https://zorin.taila92fe8.ts.net/api/health | jq .`.

**Checkpoint**: live backend serving the new prompt; test suite ready to fire a hard gate.

---

## Phase 6: Validation — Iteration 1

**Purpose**: Run the 87-question suite + SC-007 query; compare against the 7 merge floors.

- [ ] T017 Run the suite: `python backend/tests/test_rag_quality.py --base-url https://zorin.taila92fe8.ts.net > backend/tests/results/089_iter_1.log 2>&1; echo "Exit: $?"`. Copy `backend/tests/rag_quality_results.json` to `backend/tests/results/089_iter_1.json`.
- [ ] T018 Run the SC-007 query from [quickstart.md §7.3](./quickstart.md) via Supabase MCP — record the `generator_refused_with_chunks` count.
- [ ] T019 Evaluate each SC per [quickstart.md §7.4](./quickstart.md). Build the SC pass/fail table for the PR description — fill columns: SC, floor, actual, status.
- [ ] T020 **Decision branch**: if all 7 floors green → skip Phase 7 and go to Phase 8 (PR). If any floor red → proceed to Phase 7 (iteration 2).

---

## Phase 7: Validation — Iteration 2 and 3 (conditional)

**Purpose**: Apply the targeted remediation per [quickstart.md §7.5](./quickstart.md) / [spec.md §6.5](./spec.md) and re-run. Maximum two more iterations (total cap = 3).

**Gate**: Only enter this phase if iteration 1 failed any floor. Each iteration = one focused prompt edit + one re-run.

- [ ] T021 **Iteration 2**: Based on which SC failed in T019, apply the corresponding remediation from [spec.md §6.5](./spec.md) (SC-001 fail → strengthen NEVER INVENT; SC-002 fail → add 5th few-shot; SC-005 fail → add "never synthesize credentials"; SC-007 fail → investigate deployment). Fresh commit on the branch (no amend). Push.
- [ ] T022 Re-deploy + re-run: repeat T016 + T017 + T018 + T019, saving to `089_iter_2.log` / `089_iter_2.json`.
- [ ] T023 Evaluate: all floors green → go to Phase 8. Any floor red → go to T024.
- [ ] T024 **Iteration 3** (final): Apply the next-tier remediation (if SC-001 still red, tighten further; if SC-002 still red, do not add more few-shot — admit prompt alone won't close gap). Fresh commit. Push.
- [ ] T025 Re-deploy + re-run, saving to `089_iter_3.log` / `089_iter_3.json`.
- [ ] T026 Final evaluation:
  - All floors green → go to Phase 8.
  - Any floor still red after iteration 3 → go to Phase 9 (abort).

---

## Phase 8: PR & Merge (only if all 7 SC floors green)

**Purpose**: Auditable handoff to reviewers and merge to main.

- [ ] T027 Compose PR body per [quickstart.md §8](./quickstart.md) template: Summary, Evidence (before/after numbers), SC Pass Table (all 7 rows), Iteration count, Changes list, Before prompt (verbatim from T001), After prompt (verbatim from current file), Results JSON (latest `089_iter_N.json`), validated_qa row IDs (from T005).
- [ ] T028 Open PR: `gh pr create --base main --head 089-generator-prompt-tuning --title "spec 089: generator prompt tuning — RAG over-refusal fix" --body-file <file>`.
- [ ] T029 Invoke Claude Code superpowers:code-reviewer on the PR diff. Address any blockers before merge.
- [ ] T030 After approval: merge to main (`gh pr merge --squash` or the team's standard), delete local branch (`git checkout main && git pull && git branch -d 089-generator-prompt-tuning`).

---

## Phase 9: Abort path (only if iteration cap reached without green floors)

**Purpose**: Clean rollback and immediate pivot to spec 090 per [spec.md §6.5](./spec.md) / [research.md D-05](./research.md).

- [ ] T031 Abandon PR (if opened): `gh pr close <number> --comment "iteration cap reached, pivoting to spec 090 per §6.5"`.
- [ ] T032 Return to main and delete branch: `git checkout main && git pull && git branch -D 089-generator-prompt-tuning` (force-delete is safe — branch has no useful changes since reverting prompt to baseline).
- [ ] T033 Scaffold spec 090: `git checkout main && git pull && /speckit.specify 090-acronym-query-expansion`. Carry over the baseline observation that after 3 prompt iterations, `generator_refused_with_chunks` remained > 15 and vocabulary-mismatch is the next lever.

---

## Phase 10: Polish & Cross-Cutting (post-merge, only on success path)

**Purpose**: Housekeeping after merge.

- [ ] T034 [P] Update the playbook memory `~/.claude/projects/c--Development-flutter-work-order/memory/project_spec088_weekly_analysis.md` to refresh the baseline number from "38/87 (43.7%)" to the post-089 merged value. The weekly analysis playbook reads this as its "beat-this" anchor.
- [ ] T035 [P] No `AI_ASSISTANT_FEATURES.md` changes needed (behavioral tuning only — per spec §10). Confirm nothing else in `docs/` references the old prompt behavior.
- [ ] T036 Optional: delete `backend/tests/results/089_iter_*.log` from the feature branch if they were committed — the `089_iter_*.json` files are useful artifacts for the PR description but the raw log files are noisy. (If they were not committed — no-op.)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately on branch `089-generator-prompt-tuning`.
- **Foundational (Phase 2)**: Depends on Setup. Blocks US1 and US2.
- **US1 (Phase 3)**: Depends on Foundational + T005 depends on T003.
- **US2 (Phase 4)**: Depends on Foundational. **Independent of US1** — touches a different file (`test_rag_quality.py` vs. `manual_rag_service.py`).
- **Atomic Commit + Deploy (Phase 5)**: Depends on US1 complete AND US2 complete.
- **Iteration 1 (Phase 6)**: Depends on Phase 5.
- **Iteration 2/3 (Phase 7)**: Conditional on Phase 6 failing; each iteration depends on the previous.
- **PR & Merge (Phase 8)**: Depends on any iteration reaching all-green floors.
- **Abort (Phase 9)**: Mutually exclusive with Phase 8.
- **Polish (Phase 10)**: Depends on Phase 8 (success path only).

### Within Each User Story

- **US1**: T005 → T006 → T007 → T008 → T009 (sequential; all touch the same file region).
- **US2**: T010 and T011 are [P] (both modify different sections of the same file but can be composed at edit time); T012 depends on T010 (needs the `must_refuse` attribute to exist).

### Parallel Opportunities

- **Phase 1**: T002 and T003 are [P] — different codebase vs. database reads.
- **Phase 3 + Phase 4**: US1 and US2 can be implemented in parallel by different agents (different files). Both must complete before Phase 5's atomic commit.
- **Phase 4 internals**: T010 [P] and T011 [P] can be done in a single edit pass since `TestQuestion` dataclass change (T010) and flag additions (T011) are in the same file.
- **Phase 10**: T034 [P] and T035 [P] — independent doc files.

---

## Parallel Example: Phase 1 + Phases 3 & 4

```bash
# Launch in parallel via separate agents:
Task: "Read manual_rag_service.py lines 200-305 and capture current prompt" (T001)
Task: "Grep ollama_generator.py for DOCUMENT_QA_SYSTEM_PROMPT references" (T002)
Task: "Query validated_qa for top 20 candidates" (T003)
```

```bash
# After T004 gate, launch US1 and US2 in parallel:
Agent A: Tasks T005–T009 (prompt rewrite in manual_rag_service.py)
Agent B: Tasks T010–T012 (must_refuse flag in test_rag_quality.py)

# Synchronize before T013 (atomic commit must see both edits in working tree).
```

---

## Implementation Strategy

### MVP First (US1 only)

Stopping after US1 alone is NOT recommended for spec 089 — SC-005 relies on US2's assertion to be merge-blocking. However, if schedule pressure demands it:

1. Phase 1 → Phase 2 → Phase 3 (US1 only) → Phase 5 (atomic commit of US1 alone, push, deploy)
2. Phase 6 iteration 1 — but SC-005 is advisory rather than gated (manual inspection of Cat 6 entries in results JSON)
3. Merge if all other floors green; file a follow-up ticket for US2.

**Default**: do NOT skip US2. It's one-file, ~10 LOC; cost is trivial.

### Incremental Delivery (recommended)

1. Phase 1 → Phase 2 (setup complete)
2. US1 + US2 in parallel → Phase 5 (one commit) → Phase 6 iteration 1
3. If green → Phase 8 PR & merge → Phase 10 polish
4. If red → Phase 7 iteration 2 (and 3 if needed) → back to Phase 8 or Phase 9

### Parallel Team Strategy

- **Agent A** handles US1 (prompt rewrite) — needs Supabase access for T003/T005.
- **Agent B** handles US2 (test suite extension) — needs only the repo.
- Sync point at T013 (both file edits landed in working tree).
- Single reviewer (Claude Code superpowers:code-reviewer) handles Phase 8 review.

---

## Notes

- **[P] tasks** = different files, no dependencies on incomplete tasks.
- **[Story] label** maps task to US1 or US2 for traceability. Setup, Foundational, Shared phases have no story label.
- **Tests**: no new test files created; the spec mutates `test_rag_quality.py` as part of US2 (this IS the testing apparatus).
- **Atomic commit**: US1 + US2 land in ONE commit (T014). Rollback is `git revert <sha>`.
- **Iteration cap**: 3 iterations total. Beyond iteration 3 → Phase 9 abort.
- **No amend**: each iteration is a fresh commit (preserves history for the PR's iteration log).
- **Avoid**: editing prompt files outside `manual_rag_service.py`; adding acronym-expansion logic (that's spec 090); touching `VALIDATED_QA_SYSTEM_PROMPT`.

---

## Task count summary

- **Phase 1 (Setup)**: 3 tasks (T001–T003)
- **Phase 2 (Foundational)**: 1 task (T004)
- **Phase 3 (US1)**: 5 tasks (T005–T009)
- **Phase 4 (US2)**: 3 tasks (T010–T012)
- **Phase 5 (Commit+Deploy)**: 4 tasks (T013–T016)
- **Phase 6 (Iteration 1)**: 4 tasks (T017–T020)
- **Phase 7 (Iteration 2–3, conditional)**: 6 tasks (T021–T026)
- **Phase 8 (PR & Merge)**: 4 tasks (T027–T030)
- **Phase 9 (Abort, conditional, exclusive w/ Phase 8)**: 3 tasks (T031–T033)
- **Phase 10 (Polish)**: 3 tasks (T034–T036)

**Total**: 36 tasks. Expected execution path (all-green on iteration 1): T001–T020, T027–T030, T034–T036 = 27 tasks. Worst case (iteration 3 then abort): T001–T026, T031–T033 = 29 tasks.
