---
description: "Task list for spec 066 — per-stage RAG latency breakdown on Ask-the-AI answer card"
---

# Tasks: Per-Stage RAG Pipeline Latency on Ask-the-AI Answer Card

**Input**: Design documents from `/specs/066-stage-latency-breakdown/`
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/manuals-ask-response.md](./contracts/manuals-ask-response.md), [quickstart.md](./quickstart.md)
**Executor**: opencode LLM. **Reviewer**: Claude Code (superpowers `code-reviewer` agent) after completion.

**Tests**: INCLUDED (per research.md Decision 9 — contract, unit, widget tests).

**Organization**: Tasks grouped by user story. US1 = P1 footer visibility. US2 = P2 expandable diagnostic panel. US3 = P2 consistent formatting (moved into Foundational because both US1 and US2 consume it — see Note at end of Foundational).

---

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Safe to run in parallel (different files, no cross-task state).
- **[Story]**: US1 / US2 / US3 — the user story this task advances.
- **Checkbox-ID-labels-path** format is mandatory (see plan §Constitution Check compliance).

## Path conventions (this repo)

- Backend: `backend/services/`, `backend/routers/`, `backend/tests/`
- Frontend: `frontend/lib/`, `frontend/test/`
- All paths are absolute from repo root `c:\Development\flutter_work_order\`.

---

## Guardrails for the implementing agent (read once before starting)

1. **Additive only.** Do not rename or remove any existing field, function, class, or endpoint. The `/manuals/ask` response contract is extended per [contracts/manuals-ask-response.md](./contracts/manuals-ask-response.md).
2. **No new packages.** Zero additions to `backend/requirements.txt` or `frontend/pubspec.yaml`.
3. **No database changes.** No migration file, no Supabase table touch, no `user_activity_log` writes (spec FR-010).
4. **No pipeline behavior change.** Provider selection, fallback, the 30 s timeout, greeting bypass semantics, stage ordering — all unchanged (spec FR-012). Instrumentation is observation-only.
5. **All seven keys always present** in the emitted `latency_breakdown` object. Skipped/failed = `null`. `total_ms` is never `null`.
6. **Do not commit `backend/version.json`.** It is server-managed.
7. Follow [research.md Decision 2](./research.md) exactly for `_StageTimer` — it must NOT suppress exceptions and MUST record `None` on error so the key is present.
8. Follow [research.md Decision 3](./research.md) for generator timing location: inside the resolver, post-fallback, so `generator_ms` reflects the provider that actually answered.
9. Formatter rules are non-negotiable. Boundaries at `<100` → `<1s`, `<60000` → `X.Ys`, `≥60000` → `Xm Ys`, `null` → `—`. Test them.
10. Keep Arabic and English identical — no locale branching in the formatter (research Decision 6).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify the baseline is clean. No new deps, no scaffolding.

- [ ] T001 Verify branch `066-stage-latency-breakdown` is checked out and up-to-date with `main` (spec 065 merged at `105799e` or later); run `git status` and `git log --oneline -5` and confirm before any edits.
- [ ] T002 Read [plan.md](./plan.md), [research.md](./research.md), [data-model.md](./data-model.md), and [contracts/manuals-ask-response.md](./contracts/manuals-ask-response.md) end-to-end. Do not start T003 until this is done.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared primitives consumed by US1 and US2: the backend timing helper and the Pydantic response model on the backend; the `LatencyBreakdown` Dart model and the `formatStageLatency` formatter on the frontend (formatter implements US3 format rules that both US1 and US2 display through).

**⚠️ CRITICAL**: No user story work can begin until T003–T008 are complete.

### Backend foundation

- [ ] T003 Add `_StageTimer` context manager and `LatencyBreakdown` Pydantic model to `backend/services/manual_rag_service.py`. Implementation per [research.md Decision 2](./research.md) and shape per [data-model.md §Python representation](./data-model.md). Use `time.perf_counter()` and `round((end - start) * 1000)`. The `__exit__` method MUST set the dict key to `None` when `exc_type is not None` and MUST return `False` (never suppress). Place the class at module top alongside existing types, not inside a function.
- [ ] T004 [P] Add the response-field wiring helper `def _empty_latency_breakdown() -> dict:` in `backend/services/manual_rag_service.py` that returns a dict with all seven keys initialized to `None` (except `total_ms`, which starts unset and is filled at response time). This is the canonical initializer the request handler uses so every response path has the same shape.

### Frontend foundation

- [ ] T005 [P] Create `frontend/lib/models/latency_breakdown.dart` with the `LatencyBreakdown` immutable class and `fromJson` factory per [data-model.md §Dart representation](./data-model.md). Constructor takes `int?` for six stage fields and `required int totalMs`. No default values, no copy methods (YAGNI — spec principle VII). No logging, no debugPrint.
- [ ] T006 [P] Create `frontend/lib/utils/latency_formatter.dart` exposing a single top-level function `String formatStageLatency(int? ms)` that implements the format rules from [research.md Decision 6](./research.md) and [spec.md FR-007](./spec.md). Do not import `intl`. Do not branch on locale.
- [ ] T007 [P] Create `frontend/test/utils/latency_formatter_test.dart` with boundary tests: null → `—`, 0 → `<1s`, 99 → `<1s`, 100 → `0.1s`, 999 → `1.0s` (rounding-aware; specify `expect(..., anyOf('1.0s','0.9s'))` if the rounding at 999 is borderline — but `999/1000 = 0.999 → toStringAsFixed(1) = '1.0s'` is the expected result), 1000 → `1.0s`, 1200 → `1.2s`, 22400 → `22.4s`, 59999 → `60.0s` (expected; this is the asymptotic edge), 60000 → `1m 0s`, 75000 → `1m 15s`, 125000 → `2m 5s`. Run `flutter test test/utils/latency_formatter_test.dart` and confirm all pass.
- [ ] T008 Modify `frontend/lib/models/manual_qa_answer.dart` to add `final LatencyBreakdown? latencyBreakdown;` to the class and update `fromJson` to parse `json['latency_breakdown']` when non-null (using `LatencyBreakdown.fromJson`), set `null` otherwise (FR-009 backward compat). Update `toJson` similarly (emit the object or omit the key when `null`). Preserve existing constructor param ordering; add `latencyBreakdown` as a trailing named optional. Do not change any other field.

**Checkpoint**: Backend timer + Pydantic model + initializer in place; frontend model + formatter + passing formatter tests in place. US1 and US2 can now proceed in parallel.

**Note on US3**: User Story 3 (consistent formatting) is fully realized by T006 + T007 and is consumed by US1 (T013) and US2 (T018). No separate US3 implementation tasks — the story is delivered as a foundational dependency rather than as an independent phase. This is the pragmatic expression of the story's cross-cutting nature and does not violate independent-testability (T007 proves US3 stand-alone).

---

## Phase 3: User Story 1 — See that the active provider generates fast (P1) 🎯 MVP

**Goal**: On every answered Ask-the-AI question, the footer shows the generator latency prominently alongside the provider label, with the total in a secondary position. Users who switched to Groq/Mistral see that generator ≈ 1–2 s even when total is much larger.

**Independent Test**: Ask a question with Groq as the active provider; verify the answer-card footer reads `Groq (Llama 3.3 70B) · 1.2s · pipeline 22s` (actual numbers vary) with no raw-millisecond leakage.

### Backend instrumentation (US1)

- [ ] T009 [US1] In `backend/services/manual_rag_service.py`, in the main `/ask` orchestration function (typically `async def answer_query(...)` or similar — identify by the function currently building the `ManualQaAnswer` response), initialize `breakdown = _empty_latency_breakdown()` and `_total_start = time.perf_counter()` at function entry. Immediately before returning, set `breakdown["total_ms"] = round((time.perf_counter() - _total_start) * 1000)` and attach `breakdown` to the returned payload (new key `latency_breakdown`). Do not alter any other logic in this function. For the greeting-bypass short-circuit path, follow the same pattern — `total_ms` populated, other keys remain `None`.
- [ ] T010 [US1] In `backend/services/ai_providers/resolver.py`, locate the point in the resolver where the successful provider call completes (post-fallback selection). Wrap ONLY the successful generation call with `_StageTimer(breakdown, "generator_ms")` — the resolver accepts the shared `breakdown` dict via a new optional parameter `latency_breakdown: dict | None = None`. If the parameter is `None` (legacy callers), do not time anything. The manual_rag_service call site from T009 passes the dict through. Do NOT wrap the failed-primary attempt — per [research.md Decision 3](./research.md), `generator_ms` must reflect the provider that actually answered. The wall-clock cost of the failed primary is captured in `total_ms` and nowhere else.
- [ ] T011 [US1] In `backend/routers/manuals.py`, locate the `/ask` endpoint handler. Ensure the response body emitted to the client includes the `latency_breakdown` key populated from the service return. If the handler constructs a Pydantic model for the response, add `latency_breakdown: LatencyBreakdown` (importable from `manual_rag_service`) as an optional field on that model; if the handler returns a dict directly, ensure the dict carries the key. Do not remove any existing response field. Do not change the HTTP status or error-path behavior.

### Frontend footer (US1)

- [ ] T012 [US1] In `frontend/lib/services/manual_assistant_service.dart`, locate the method that consumes the `/manuals/ask` response (currently building `ManualQaAnswer.fromJson`). Verify that because T008 already taught `ManualQaAnswer.fromJson` to parse `latency_breakdown`, no change to the service file is required beyond possibly passing the full JSON map to the model. If the service currently strips unknown keys before calling `fromJson`, stop stripping. Add a short code comment in the service only if behavior genuinely changed.
- [ ] T013 [US1] In `frontend/lib/screens/manual_assistant/widgets/answer_card.dart`, refactor the footer row to display three segments when `answer.latencyBreakdown != null && answer.latencyBreakdown!.generatorMs != null`:
    1. Provider label (existing, unchanged from spec 065)
    2. A middle-dot separator `· ` followed by `formatStageLatency(answer.latencyBreakdown!.generatorMs)` — this is the PROMINENT generator latency
    3. A middle-dot separator `· pipeline ` followed by `formatStageLatency(answer.latencyBreakdown!.totalMs)` — SECONDARY, rendered one visual step quieter (use `Theme.of(context).textTheme.bodySmall` with `color: Theme.of(context).colorScheme.onSurfaceVariant` or the existing muted footer color in the file; match the file's existing secondary-text convention).
  When `latencyBreakdown == null` (legacy backend) the footer renders exactly as pre-066 — preserve that branch. When `generatorMs == null` but `latencyBreakdown != null` (greeting bypass), omit the generator segment but still render `pipeline …` so the user always sees a total.
- [ ] T014 [US1] Add a widget test `frontend/test/widgets/answer_card_latency_test.dart` that pumps `AnswerCard` with three fixtures: (a) full breakdown + Groq provider → expect `Groq` + `1.2s` + `pipeline 22.4s` text found, (b) `generatorMs == null` (greeting bypass) + `totalMs = 2` → expect `pipeline <1s` found and no standalone generator segment, (c) `latencyBreakdown == null` → expect rendering does not throw and pre-066 footer text still present. Use `Finder` with `find.textContaining` for robustness against layout whitespace.

### Backend contract test for US1

- [ ] T015 [US1] Create `backend/tests/test_manual_rag_latency.py`. Add contract test `test_response_contains_latency_breakdown_with_all_seven_keys` that calls the service/handler with a stub-mocked Ollama + Supabase path and asserts `response["latency_breakdown"]` contains exactly the seven keys from [data-model.md](./data-model.md), with `total_ms` as an `int` and each stage key as `int` or `None`. Follow the project's existing pytest conventions (imports, fixtures). If existing fixtures in `backend/tests/` provide a mocked `manual_rag_service` entrypoint, reuse them; otherwise construct the minimum stub.

**Checkpoint**: US1 complete. Footer shows generator + total; contract holds; legacy footer path preserved. This is a shippable MVP.

---

## Phase 4: User Story 2 — Diagnose where time is spent (P2)

**Goal**: Always-visible chevron on the footer expands a panel showing all seven stage timings with clear labels. Skipped stages render as `—`.

**Independent Test**: Expand an answered question's breakdown; confirm seven labeled rows (Embed, HyDE, Rewrite, Retrieval, Rerank, Generator, Total) are present with formatted values, and that tapping the chevron again collapses the panel. Arabic UI renders identically.

### Frontend expansion panel (US2)

- [ ] T016 [US2] Convert `AnswerCard` in `frontend/lib/screens/manual_assistant/widgets/answer_card.dart` to a `StatefulWidget` (if not already) OR add a `_LatencyFooter` child `StatefulWidget` that owns the `bool _expanded = false;` state. Prefer the child-widget approach to keep `AnswerCard`'s blast radius small. The chevron is an `IconButton(icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more), onPressed: () => setState(() => _expanded = !_expanded))`, wrapped in a `Semantics(label: 'Show pipeline timing breakdown', button: true, ...)` per [research.md Decision 7](./research.md). The button is ALWAYS rendered when `latencyBreakdown != null` — never hidden behind a hover or long-press. When `latencyBreakdown == null`, render no chevron (preserves legacy layout).
- [ ] T017 [US2] When `_expanded == true`, render below the footer row an `AnimatedSize`-wrapped `Column` with seven `Row` children. Each row is `[label, Spacer(), value]` where label is one of: "Embed", "HyDE", "Rewrite", "Retrieval", "Rerank", "Generator", "Total". Value is `formatStageLatency(lb.embedMs)` etc. (use `lb.totalMs` for the Total row — same formatter, never `null`). Keep styling consistent with the existing card's body text scale (use `Theme.of(context).textTheme.bodySmall`). No animations beyond the default `AnimatedSize` curve. No Arabic-specific branching — the labels are English-only in phase 1 as per existing `manual_assistant` screen convention (all other labels in this widget tree are English-only). Verify this assumption by grepping the file for `AppLocalizations` / `.tr()`; if the existing widget uses translated labels, add the seven new strings to the same translation file following the file's convention. Otherwise, use plain English string literals.
- [ ] T018 [US2] Extend the widget test file from T014 with `testWidgets('tapping chevron expands breakdown panel with 7 labeled rows', ...)`: pump `AnswerCard` with a full `LatencyBreakdown` fixture; find the chevron via `find.byIcon(Icons.expand_more)`; tap it; pump; assert each of the seven row labels is present and its formatted value is present. Then tap `find.byIcon(Icons.expand_less)` and assert the panel collapsed (labels no longer found).

### Backend contract tests for US2 skip-path shapes

- [ ] T019 [US2] [P] Add to `backend/tests/test_manual_rag_latency.py` the test `test_greeting_bypass_returns_all_nulls_except_total`: invoke the greeting-bypass code path (e.g., question = "hi") and assert every stage key is `None` and `total_ms` is an `int >= 0`.
- [ ] T020 [US2] [P] Add `test_hyde_disabled_returns_null_hyde_other_stages_populated`: flip the HyDE feature-setting off (use the existing mechanism, see `backend/services/manual_rag_service.py` for how HyDE is gated), run a normal query, assert `hyde_ms is None` while `embed_ms`, `rewrite_ms`, `retrieval_ms`, `rerank_ms`, `generator_ms`, `total_ms` are all non-`None` ints.
- [ ] T021 [US2] Add `test_fallback_generator_ms_reflects_successful_provider`: monkeypatch the resolver so the primary provider raises and a secondary provider succeeds; assert `generator_ms` is set and falls in a bounded range (e.g., `> 0 and < total_ms`) and that this value corresponds to the successful call (you can verify by monkeypatching the successful provider to sleep a known amount).
- [ ] T022 [US2] [P] Add `test_stage_timer_records_none_on_exception_and_propagates`: construct a `_StageTimer` on a dict, raise an `RuntimeError` inside the `with` block, assert the key is `None` on the dict and the exception propagates unchanged.

**Checkpoint**: US2 complete. All skip-path shapes locked by contract tests. Chevron is accessible and discoverable.

---

## Phase 5: User Story 3 — Consistent formatting (P2)

**Delivery note**: US3 is delivered by T006 (implementation) and T007 (exhaustive boundary tests) in Foundational. No additional implementation tasks. To confirm US3 independent test-passability as a story, run:

- [ ] T023 [US3] Run `flutter test test/utils/latency_formatter_test.dart` and include the PASS output in the completion report. This is the story's independent-test gate.
- [ ] T024 [US3] [P] Manually verify Arabic rendering: launch the app, switch the locale (Settings → language toggle), open any answered card, expand the breakdown, confirm the numerals and units render identically to the English view (same digits `1.2s`, `1m 15s` — no Arabic-Indic digit substitution, no unit localization). If the app currently forces Arabic-Indic digits in some locales, document that as a pre-existing constraint and do NOT attempt to fix it in this spec.

**Checkpoint**: US3 verified.

---

## Phase 6: Polish & Cross-Cutting

- [ ] T025 [P] Run `pytest backend/tests/test_manual_rag_latency.py -v` and paste the full output into the completion report. All tests must pass.
- [ ] T026 [P] Run `flutter test test/utils/latency_formatter_test.dart test/widgets/answer_card_latency_test.dart` and paste the output. All tests must pass.
- [ ] T027 [P] Run `flutter analyze` on the frontend and confirm no new errors/warnings introduced by changed files.
- [ ] T028 Manually walk through [quickstart.md §Acceptance walkthrough](./quickstart.md) steps 1–7 against a dev environment. Record PASS/FAIL per step in the completion report.
- [ ] T029 Final verification of the hard invariants (these are not tests — they are visual confirmations on a running app):
    - FR-002: Inspect a sample `/manuals/ask` response in the browser Network tab; confirm all seven keys are present.
    - FR-009: Simulate a legacy backend response by deleting `latency_breakdown` from a mocked response; confirm the answer still renders (use a local mock or a quick dev-only flag).
    - FR-010: `grep -r "user_activity_log" backend/services/manual_rag_service.py backend/routers/manuals.py backend/services/ai_providers/resolver.py` — no new writes. Paste the grep output.
    - FR-012: Re-run any existing `/manuals/ask` integration tests in `backend/tests/` (grep for `manuals/ask`) — none should fail.
- [ ] T030 Do NOT commit `backend/version.json` (project memory). Do NOT run `bump_version.sh`. Do NOT push.
- [ ] T031 Write a completion report at the bottom of this `tasks.md` file (append under a `## Implementation Report` heading) with:
    1. Commits made (hashes + subjects)
    2. Files touched with line-count deltas
    3. Test command outputs from T025, T026, T027
    4. Quickstart walkthrough results from T028
    5. Hard-invariant check outputs from T029
    6. Any deviations from this tasks.md with justification

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (Phase 1)**: T001 → T002 (sequential)
- **Foundational (Phase 2)**: Requires T002. T003 first (defines `_StageTimer` used by the initializer shape). T004 after T003 (same file). T005/T006/T007 are `[P]` with each other (different files). T008 requires T005.
- **Phase 3 US1**: Requires all of Phase 2. T009 before T010 (T010 receives the shared dict plumbed by T009). T010 before T011 (the router threads through what the service produces). T012 requires T008. T013 requires T012 + T006. T014 requires T013. T015 is independent of frontend and can run any time after T011.
- **Phase 4 US2**: Requires T013 (the footer row US2's expansion hangs off). T016 before T017. T018 after T017. T019/T020/T022 are `[P]`. T021 after T010 (resolver wiring must exist to test).
- **Phase 5 US3**: Requires T006 + T007. T023/T024 independent of anything else.
- **Phase 6 Polish**: Requires all of Phases 3–5.

### User-story independence

- **US1 (P1)** is the MVP. On completion of Phases 1+2+3, the footer improvements ship without US2 or US3 needing to complete (US3 gate is already met by T007 in Phase 2).
- **US2 (P2)** is additive. It does not modify any US1 behavior.
- **US3 (P2)** is foundationally delivered; no story-level integration risk.

### Parallel opportunities

```text
# After Phase 1:
T005  T006  (parallel — different files, no deps)

# After Phase 2 (US1 + US2 + US3 tests can overlap):
T015  T019  T020  T022  T023  T024  (parallel — different files)

# Frontend tests:
T014  T018  (sequential — same file; both under T013)

# Polish:
T025  T026  T027  (parallel)
```

---

## Implementation Strategy

### Recommended path for opencode

1. **Phase 1** (10 min) — read the docs, verify branch state.
2. **Phase 2 backend first** — T003, T004 (one file). Then Phase 2 frontend T005, T006, T007, T008.
3. **Phase 3 US1** — implement end-to-end so you can see the feature work in a dev environment. Run T014 locally.
4. **Phase 4 US2** — layer the expansion panel on top of the working footer.
5. **Phase 5 US3** — run the formatter tests.
6. **Phase 6 Polish** — verify every invariant, fill in the Implementation Report, and stop.

### Stop conditions (do not push beyond these)

- Do not commit or push.
- Do not bump version.
- Do not open a PR.
- Do not deploy.
- If any test from T025 or T026 fails, STOP and write the failure into the Implementation Report rather than papering over it.
- If you discover an ambiguity that is not covered by plan/research/data-model/contracts, STOP and note it under "Open questions for reviewer" at the bottom of the Implementation Report.

---

## Review Handoff

When opencode completes Phase 6 and writes the Implementation Report, Claude Code will invoke the `superpowers:code-reviewer` agent with:

- Spec: [spec.md](./spec.md)
- Plan: [plan.md](./plan.md)
- Research: [research.md](./research.md)
- Data model: [data-model.md](./data-model.md)
- Contract: [contracts/manuals-ask-response.md](./contracts/manuals-ask-response.md)
- Tasks: this file
- Implementation Report: the appended section at the bottom of this file
- Working tree: the modified files

The reviewer will specifically check:

1. **Invariant compliance**: FR-002 (seven keys), FR-003 (total wall-clock), FR-007 (format rules), FR-009 (additive), FR-010 (no persistence), FR-012 (no pipeline behavior change), FR-013 (fallback generator attribution).
2. **Exception safety of `_StageTimer`**: exceptions propagate, `None` recorded, no side-effects.
3. **Resolver wiring**: `generator_ms` measures the successful provider only.
4. **Greeting-bypass shape**: six stage keys `None`, `total_ms` populated.
5. **Frontend backward compatibility**: `answer.latencyBreakdown == null` path renders pre-066 footer.
6. **Constitution gates** (from [plan.md §Constitution Check](./plan.md)): no violations introduced.
7. **Test coverage**: every FR with a testable observable has a corresponding test.
8. **Task fidelity**: every checkbox is actually checked; any unchecked boxes are explained.

---

## Notes

- Keep commits clean and scoped (backend vs frontend; tests separate from impl is ideal but not required).
- If any file contains a large unrelated diff after your edits (formatter churn, import reordering), revert the unrelated parts before handing back.
- If a test fixture is missing in `backend/tests/` and you have to stub Ollama/Supabase for the first time for this endpoint, document the stub approach in the Implementation Report so the reviewer can validate it's not masking real behavior.

## Implementation Report

_(opencode fills this section in at the end of Phase 6. Leave empty until then.)_
