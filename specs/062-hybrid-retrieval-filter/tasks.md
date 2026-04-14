---
description: "Tasks for Hybrid Retrieval — System Keyword Pre-filtering (spec 062). Written for opencode LLM implementation; Claude Code will do code review afterwards per memory."
---

# Tasks: Hybrid Retrieval — System Keyword Pre-filtering

**Input**: Design documents from `/specs/062-hybrid-retrieval-filter/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/retrieval_info.schema.md](contracts/retrieval_info.schema.md), [quickstart.md](quickstart.md)

**Implementer**: opencode LLM (autonomous). Each task is self-contained — all paths absolute, all signatures explicit, no tribal knowledge required. After opencode finishes each user story phase, stop and wait for Claude Code's superpowers review.

**Tests**: Minimal — one pytest file for the pure-logic registry (the only part worth automating in isolation). Integration correctness is verified via the manual benchmark in [quickstart.md](quickstart.md).

---

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different file, no dependency on incomplete tasks)
- **[Story]**: US1–US5 per [spec.md](spec.md)

## Path conventions (web app — Option 2)

- Backend Python: `backend/services/`, `backend/tests/`
- Frontend Flutter: `frontend/lib/models/`, `frontend/lib/screens/manual_assistant/widgets/`

---

## Phase 1: Setup

**Purpose**: Confirm environment. No new deps, no new dirs.

- [X] T001 Verify you are on branch `062-hybrid-retrieval-filter` (`git branch --show-current`). If not, run `git checkout 062-hybrid-retrieval-filter` before making any edits.
- [X] T002 Read [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md), and [contracts/retrieval_info.schema.md](contracts/retrieval_info.schema.md) end-to-end before writing code. These are the contract — do not deviate without updating the corresponding doc first.

---

## Phase 2: Foundational (blocking — must complete before any user story)

**Purpose**: Ship the pure-logic registry. Every user-story phase below depends on it.

- [X] T003 Create `backend/services/system_registry.py` with the following public surface (exact names; see [data-model.md](data-model.md) §"In-memory entities" for rationale):
  - Module-level `KNOWN_SYSTEMS: list[str]` — canonical names ordered longest-first: `["International Circuits", "INDRA CCTV", "Billing System", "CADAS-ATS", "CADAS-IMS", "AIDA-NG", "Permissions", "IRTOS", "AFTN", "UPS"]`.
  - Module-level `SYSTEM_ALIASES: dict[str, str]` — maps every alias (including each canonical itself) to its canonical. MUST include spacing/hyphenation variants: `"CADAS ATS"→"CADAS-ATS"`, `"CADAS-ATS"→"CADAS-ATS"`, `"CADAS IMS"→"CADAS-IMS"`, `"CADAS-IMS"→"CADAS-IMS"`, `"AIDA NG"→"AIDA-NG"`, `"AIDA-NG"→"AIDA-NG"`, plus the remaining canonicals mapping to themselves.
  - Module-level `_SORTED_ALIASES: list[tuple[str, str]]` — list of `(alias_lower, canonical)` sorted by `len(alias)` descending. Precomputed at import time so `detect_system` is O(n) on question length and registry size.
  - `def detect_system(question: str) -> Optional[str]`: lowercases `question`, scans `_SORTED_ALIASES`, returns the canonical of the first alias whose lowercase form appears as a substring in the lowercased question. Returns `None` on no match. MUST NOT match bare `"cadas"` (the registry contains no bare `"CADAS"` entry — this is intentional).
  - `async def get_manual_ids_for_system(system_name: str, supabase_client) -> list[str]`: given the canonical name, find every alias that maps to it, then query `supabase_client.table("manuals").select("id, title, file_name")` and filter in Python for rows where ANY alias (case-insensitive) is a substring of either `title` OR `file_name`. Returns the list of `id` UUID strings (deduplicated). Returns `[]` on no match. Wrap in try/except: on any error, log a warning with `logger.warning("[hybrid-retrieval] manual lookup failed: %s", e)` and return `[]`.
  - Use `from typing import Optional` and `import logging`; define `logger = logging.getLogger(__name__)` at top of file.
- [ ] T004 [P] Create `backend/tests/test_system_registry.py` covering all spec acceptance criteria for Task 1/2:
  - `detect_system("CADAS-ATS backup")` → `"CADAS-ATS"`
  - `detect_system("cadas ats backup")` → `"CADAS-ATS"` (case-insensitive, space variant)
  - `detect_system("CADAS-IMS restart")` → `"CADAS-IMS"` (NOT `"CADAS-ATS"`)
  - `detect_system("how to restart aida-ng?")` → `"AIDA-NG"`
  - `detect_system("general question")` → `None`
  - `detect_system("CADAS backup procedure")` → `None` (bare ambiguous token)
  - Longest-match-wins invariant test: assert that for any alias A, no *prefix* of A longer than 3 chars is also in `SYSTEM_ALIASES`.
  - Use `pytest` idioms; no DB/network mocks needed. Run with `cd backend && pytest tests/test_system_registry.py -v`. All must pass before proceeding to Phase 3.

**Checkpoint**: Registry module importable, unit tests green. Stop here and wait for Claude Code's review of Phase 2 before starting Phase 3.

---

## Phase 3: User Story 1 — Accurate answers for system-specific questions (P1) 🎯 MVP

**Goal**: When a user's question names a known system AND matching manuals exist, narrow cross-manual retrieval to those manuals and populate `retrieval_info` on the response.

**Independent test**: With CADAS-ATS and CADAS-IMS manuals both uploaded, ask "what is the backup for CADAS-ATS?". Verify `response.retrieval_info.detected_system == "CADAS-ATS"`, `filter_applied == true`, `filtered_manual_ids` non-empty, and every `sources[].manual_title` contains "CADAS-ATS".

- [X] T005 [US1] In `backend/services/manual_rag_service.py`, add import at top of file (alongside other `from services.` imports):
  ```python
  from services.system_registry import detect_system, get_manual_ids_for_system
  ```
- [X] T006 [US1] Modify `_retrieve_chunks_per_manual` (currently starts at [line 430](../../backend/services/manual_rag_service.py#L430)) to accept an optional filter:
  - Change signature to `async def _retrieve_chunks_per_manual(embedding_str: str, allowed_manual_ids: set[str] | None = None) -> dict[str, list[dict]]:`
  - After the `manuals_resp = supabase.table("manuals").select("id, title").execute()` line, if `allowed_manual_ids is not None`, filter `manuals_resp.data` in place: `manuals_resp.data = [m for m in (manuals_resp.data or []) if m["id"] in allowed_manual_ids]`.
  - Rest of the function is unchanged. When the input list is a subset, the per-manual loop naturally only iterates the subset and the synthesis downstream sees only those chunks.
- [X] T007 [US1] Modify `ask()` (entry point at [line 632](../../backend/services/manual_rag_service.py#L632)) to perform detection and build `retrieval_info`:
  1. Immediately after the function signature (before the empty-corpus check), initialize three locals:
     ```python
     detected_system = detect_system(question)
     retrieval_info: dict = {
         "detected_system": detected_system,
         "filtered_manual_ids": [],
         "filter_applied": False,
         "fallback_reason": None,
     }
     system_manual_ids: list[str] = []
     no_manuals_directive: str | None = None
     ```
  2. If `detected_system is not None AND manual_id_filter is None`, look up matching manuals right before the existing branch at [line 749](../../backend/services/manual_rag_service.py#L749):
     ```python
     if detected_system and manual_id_filter is None:
         system_manual_ids = await get_manual_ids_for_system(detected_system, supabase)
         if system_manual_ids:
             retrieval_info["filtered_manual_ids"] = system_manual_ids
             retrieval_info["filter_applied"] = True
             logger.info("[hybrid-retrieval] detected_system=%s filter_applied=true matched_manuals=%d",
                         detected_system, len(system_manual_ids))
         else:
             retrieval_info["fallback_reason"] = "no_manuals_for_system"
             no_manuals_directive = (
                 f"IMPORTANT: The user asked specifically about {detected_system}. "
                 f"No manuals for {detected_system} are currently uploaded to the system. "
                 f"Do NOT substitute content from other similar-sounding systems. "
                 f"Respond that specific information about {detected_system} is not available in the uploaded manuals."
             )
             logger.warning("[hybrid-retrieval] System '%s' detected but no manuals found, falling back to all",
                            detected_system)
     elif manual_id_filter is not None and detected_system:
         logger.info("[hybrid-retrieval] User selected manual — skipping filter (detected=%s)", detected_system)
     ```
  3. At the call site of `_retrieve_chunks_per_manual(embedding_str)`, pass the filter: when `retrieval_info["filter_applied"]` is True, call it as `_retrieve_chunks_per_manual(embedding_str, allowed_manual_ids=set(system_manual_ids))`; otherwise unchanged.
  4. Every `return` statement in `ask()` (there are several — validated-QA direct match at ~line 666, empty-corpus at ~line 650, single-manual path, cross-manual path) MUST include `"retrieval_info": retrieval_info` in the returned dict. Grep the function for `return {` and add the key to each. Empty-corpus return should keep `retrieval_info` with `detected_system` set (detection still ran).
- [X] T008 [US1] Thread `no_manuals_directive` into the generator prompt. Locate the `generate(...)` call(s) used by both the single-manual path and `_generate_sub_answers` (cross-manual synthesis, [line 479](../../backend/services/manual_rag_service.py#L479)). The simplest non-invasive approach:
  - Add a new optional parameter to `_generate_sub_answers`: `extra_prefix: str | None = None`. When set, prepend it (followed by two newlines) to the prompt text assembled inside that function before calling `generate`.
  - Pass `extra_prefix=no_manuals_directive` from the cross-manual branch of `ask()`.
  - For the single-manual path branch (only reached when `manual_id_filter` is set, which implies `filter_applied=false` AND no_manuals_directive is None), no change is needed — the directive only fires when the user did NOT pre-select a manual.

**Checkpoint at end of US1**: Run the 5 benchmarks from [quickstart.md](quickstart.md) §Step 2 manually (or at minimum benchmarks 1, 2, 3). Benchmarks 1–3 must show `filter_applied=true` and correct `detected_system`; benchmarks 4 and 5 must show `detected_system=null, filter_applied=false`. Stop here and wait for Claude Code's review before moving on.

---

## Phase 4: User Story 2 — Unchanged experience for general questions (P1)

**Goal**: Confirm no regression on questions with no system keyword. Implementation-wise, US1's code already handles this path correctly (`detect_system` returns None → no lookup → `_retrieve_chunks_per_manual` called without `allowed_manual_ids` → legacy behavior). This phase is primarily verification.

**Independent test**: Ask "what are the general maintenance rules?" and "backup procedure". Verify `retrieval_info.detected_system is null`, `filter_applied is false`, `filtered_manual_ids=[]`, and retrieved sources span multiple manuals as they did pre-feature.

- [ ] T009 [US2] Add an `assert`-style regression check to the `ask()` code path by running benchmarks 4 and 5 from [quickstart.md](quickstart.md) §Step 2 against your local backend. Capture the `manuals_consulted` lists and compare to a pre-feature baseline (if unavailable, confirm the list has more than one manual for at least one of the two questions).
- [X] T010 [US2] Search `backend/services/manual_rag_service.py` for any remaining code path that returns a response dict WITHOUT a `"retrieval_info"` key (use grep: `rg "return \{" backend/services/manual_rag_service.py`). For each hit inside `ask()`, ensure the `retrieval_info` key is present. This is a belt-and-suspenders check for FR-008/FR-009.

**Checkpoint**: General questions behave exactly as before. `retrieval_info` present on every `ask()` return.

---

## Phase 5: User Story 3 — Graceful fallback when a system is named but no manual exists (P2)

**Goal**: When detection finds a system but no uploaded manual matches, log warning, fall back to unfiltered retrieval, set `fallback_reason="no_manuals_for_system"`, and ensure the generated answer states information is unavailable rather than substituting near-neighbor content.

**Independent test**: Remove CADAS-ATS manual from dev DB. Ask "what is the backup for CADAS-ATS?". Verify `retrieval_info.fallback_reason=="no_manuals_for_system"`, `filter_applied=false`. Read `answer` text — it MUST state CADAS-ATS info is unavailable AND MUST NOT contain CADAS-IMS procedures.

- [X] T011 [US3] Most of this was implemented in T007 (the `else` branch setting `fallback_reason` and building `no_manuals_directive`) and T008 (threading the directive into the generator prompt). Verify both are in place.
- [ ] T012 [US3] Follow [quickstart.md](quickstart.md) §Step 4 end-to-end. In particular: after deletion of CADAS-ATS manual (or in an environment where it was never uploaded), assert via backend logs that `[hybrid-retrieval] System 'CADAS-ATS' detected but no manuals found, falling back to all` appears.

**Checkpoint**: Fallback semantics verified. SC-004 holds on the benchmark set.

---

## Phase 6: User Story 4 — User-selected manual takes precedence (P2)

**Goal**: When `manual_id_filter` is explicitly set by the caller (user picked a manual in the UI), skip system-keyword narrowing but still populate `retrieval_info.detected_system` for observability. `filter_applied` stays false.

**Independent test**: In Flutter app, select CADAS-IMS manual from dropdown. Ask "what is the backup for CADAS-ATS?". Verify `retrieval_info.detected_system=="CADAS-ATS"`, `filter_applied=false`, `filtered_manual_ids=[]`; `sources[*].manual_title` all contain "CADAS-IMS".

- [ ] T013 [US4] This was implemented in T007 via the `elif manual_id_filter is not None and detected_system:` log line and the condition `if detected_system and manual_id_filter is None:` gating the lookup. Verify that path: add a temporary unit test or exercise via curl with a known `manual_id` matching a CADAS-IMS manual's UUID.
- [ ] T014 [US4] Manually verify via the Flutter app per [quickstart.md](quickstart.md) §Step 5. No new code — this phase is a verification gate.

**Checkpoint**: Explicit user selection always wins. Observability is preserved (detection still logged).

---

## Phase 7: User Story 5 — Visible filter indication in the answer card (P3)

**Goal**: Show a "Filtered to: <system>" chip under the "Synthesized from N manuals" banner whenever `filter_applied=true` on the response. No chip otherwise. Pure Flutter work, independent of backend changes.

**Independent test**: Ask a system-named question → chip visible with correct canonical name. Ask a general question → no chip, layout unchanged.

- [X] T015 [P] [US5] Modify `frontend/lib/models/manual_qa_answer.dart`:
  1. Add a new class at top (after imports, before `ManualConsulted`):
     ```dart
     class RetrievalInfo {
       final String? detectedSystem;
       final List<String> filteredManualIds;
       final bool filterApplied;
       final String? fallbackReason;

       const RetrievalInfo({
         this.detectedSystem,
         this.filteredManualIds = const [],
         this.filterApplied = false,
         this.fallbackReason,
       });

       factory RetrievalInfo.fromJson(Map<String, dynamic> json) {
         return RetrievalInfo(
           detectedSystem: json['detected_system'] as String?,
           filteredManualIds: (json['filtered_manual_ids'] as List?)
                   ?.map((e) => e.toString())
                   .toList() ??
               const [],
           filterApplied: json['filter_applied'] as bool? ?? false,
           fallbackReason: json['fallback_reason'] as String?,
         );
       }
     }
     ```
  2. Add `final RetrievalInfo? retrievalInfo;` as the last field on `ManualQaAnswer`.
  3. Add `this.retrievalInfo,` to the constructor.
  4. In `ManualQaAnswer.fromJson`, parse defensively right before `return ManualQaAnswer(...)`:
     ```dart
     RetrievalInfo? retrievalInfo;
     if (json['retrieval_info'] != null) {
       retrievalInfo = RetrievalInfo.fromJson(
         Map<String, dynamic>.from(json['retrieval_info'] as Map));
     }
     ```
  5. Pass `retrievalInfo: retrievalInfo,` in the `ManualQaAnswer(...)` constructor call at the end of `fromJson`.
- [X] T016 [US5] Modify `frontend/lib/screens/manual_assistant/widgets/answer_card.dart`:
  1. Locate the "Synthesized from N manuals" banner (grep for `manualsConsulted` or `Synthesized`).
  2. Immediately after it, insert a conditional chip widget:
     ```dart
     if (answer.retrievalInfo?.filterApplied == true &&
         answer.retrievalInfo?.detectedSystem != null) ...[
       const SizedBox(height: 4),
       Container(
         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
         decoration: BoxDecoration(
           color: Colors.blue.shade50,
           borderRadius: BorderRadius.circular(6),
         ),
         child: Row(
           mainAxisSize: MainAxisSize.min,
           children: [
             Icon(Icons.filter_alt_outlined,
                 size: 12, color: Colors.blue.shade700),
             const SizedBox(width: 4),
             Text(
               'Filtered to: ${answer.retrievalInfo!.detectedSystem}',
               style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
             ),
           ],
         ),
       ),
     ],
     ```
  3. Do NOT modify any other layout logic — the chip is purely additive and conditional.
- [ ] T017 [P] [US5] Verify visually per [quickstart.md](quickstart.md) §Step 6 using `flutter run -d chrome` against a backend with the feature deployed.

**Checkpoint**: Chip appears iff `filter_applied=true`. No layout regression for any other response shape.

---

## Phase 8: Polish & Cross-Cutting

- [ ] T018 Run `cd backend && pytest tests/test_system_registry.py -v` — all green.
- [ ] T019 Run `cd frontend && flutter analyze` — no new warnings.
- [ ] T020 Execute all 7 steps of [quickstart.md](quickstart.md) on a dev environment; paste the output of the 5 benchmark `curl` commands into the PR description as evidence for SC-001, SC-002, SC-003, SC-004, SC-005.
- [X] T021 Update project AGENT.md (or equivalent architecture doc) with a one-line entry under the RAG pipeline section noting that retrieval can now be narrowed by detected system keyword (cross-link to this spec).
- [ ] T022 Do NOT commit `backend/version.json` (per project memory). Stage only the files listed in plan.md §"Source Code" + this tasks.md.

---

## Dependencies

```text
T001, T002 (Setup) → T003, T004 (Phase 2 Foundational)
                   → T005–T008 (US1)  ──┐
                                        ├→ T009, T010 (US2 verification)
                                        ├→ T011, T012 (US3 — uses code from T007, T008)
                                        └→ T013, T014 (US4 — uses code from T007)
T003 (registry) ────────────────────────→ T015, T016, T017 (US5 Flutter, independent of backend merge order but requires contract from T007)
T005–T017 ──→ T018–T022 (Polish)
```

- US1 is the MVP — once T003–T008 land, the feature delivers its primary value.
- US2 is verification-only; no new code.
- US3 and US4 are free riders on US1's code (T007/T008).
- US5 can be implemented in parallel with US3/US4 once the response contract (T007) is pinned.

## Parallel execution opportunities

Within a single user story phase:
- T004 `[P]` runs in parallel with T003 — different file, and the test file is green once T003 lands.
- T015 `[P]` and T017 `[P]` are Flutter-only and independent of backend testing.

Across stories:
- US5 (Flutter) can proceed concurrently with US3/US4 (verification) once T007/T008 land.

## Implementation strategy (MVP first)

1. **MVP slice**: T001 → T002 → T003 → T004 → T005 → T006 → T007 → T008 → manual benchmark 1 & 2. This delivers SC-001 and SC-002.
2. **Completeness slice**: T009–T014 closes out regression + fallback + user-selection stories.
3. **Polish slice**: T015–T017 adds the UI chip; T018–T022 ship it.

## Review gates

Per user memory (Opencode implements, Claude reviews):

- After Phase 2 (T003–T004): opencode stops. Claude Code runs superpowers-code-review on the registry module + tests.
- After Phase 3 (T005–T008 — MVP): opencode stops. Claude reviews the `ask()` + `_retrieve_chunks_per_manual` diff, benchmarks 1–3, and response shape against [contracts/retrieval_info.schema.md](contracts/retrieval_info.schema.md).
- After Phase 5/6 (T011–T014): Claude reviews fallback directive wording and log lines against [research.md](research.md) §R5.
- After Phase 7 (T015–T017): Claude reviews Flutter model + chip widget against FR-011 / [contracts/retrieval_info.schema.md](contracts/retrieval_info.schema.md) §"Flutter consumer contract".
- After Phase 8: final review against all SC-00x criteria; then commit & open PR.
