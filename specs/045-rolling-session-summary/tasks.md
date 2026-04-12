# Tasks: Rolling Session Summary

**Input**: Design documents from `/specs/045-rolling-session-summary/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Not requested — no test tasks generated.

**Organization**: Tasks are grouped by user story. US1 (Seamless Long Conversations) and US2 (Transparent Compression) are both P1 and tightly coupled — US2 provides the transport mechanism for US1's compression. They share a single phase.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Foundational (Backend Compression Core)

**Purpose**: Build the compression function and prompt integration — the core engine that all stories depend on

**⚠️ CRITICAL**: All subsequent phases depend on this compression function existing

- [X] T001 [US1] Add `_compress_history()` async function to `backend/services/manual_rag_service.py` — accepts list of conversation turns + optional existing session_summary string, calls Ollama `generate()` with a summarization prompt that instructs the LLM to produce 3-4 sentences preserving all technical facts (part numbers, specs, procedures). Returns the summary string. Use the same model as the main generation (via `get_default_model()` or passed model param). Wrap the Ollama call in try/except and return `None` on any failure.
- [X] T002 [US1] Update `_build_prompt()` in `backend/services/manual_rag_service.py` — add optional `memory: str | None = None` parameter. When provided, insert a `CONVERSATION MEMORY:\n{memory}` block between the `MANUAL SECTIONS:` block and the `CONVERSATION HISTORY:` block. When `None`, behavior is unchanged from current.
- [X] T003 [US1] Add compression logging to `backend/services/manual_rag_service.py` — log at INFO level when compression is triggered (`[COMPRESS] Compressing {N} turns into summary`), when summary is reused (`[COMPRESS] Reusing existing summary`), and when compression fails with fallback (`[COMPRESS] Compression failed, falling back to last 10 turns: {error}`).

**Checkpoint**: `_compress_history()` and updated `_build_prompt()` exist and can be called. No integration yet.

---

## Phase 2: US1 + US2 — Seamless Long Conversations + Transparent Compression (Priority: P1) MVP

**Goal**: Full round-trip: backend compresses history, returns session_summary, frontend caches and sends it back. Conversations of 9+ turns use compressed memory.

**Independent Test**: Conduct a 12+ turn conversation in the manual assistant. After turn 9, verify the assistant remembers facts from early turns. Check backend logs for `[COMPRESS]` entries.

### Backend Integration

- [X] T004 [US1] Integrate compression into `ask()` method in `backend/services/manual_rag_service.py` — after chunk reranking and before `_build_prompt()`: check if `len(history) > 8`. If yes, determine if the incoming `session_summary` can be reused or needs re-compression (compare number of turns that should be compressed: `len(history) - 4` against what the summary covers). Call `_compress_history()` with the turns to compress + existing summary. Pass the resulting memory string to `_build_prompt()`. If compression returns `None` (failure), fall back to `history[-10:]` with no memory. Update `ask()` return dict to include `"session_summary"` key.
- [X] T005 [US1] Update `_build_prompt()` call site in `ask()` in `backend/services/manual_rag_service.py` — when compression is active, pass `history[-4:]` (last 4 raw turns) as history and the summary as memory. When compression is not active (≤8 turns), pass all history as before with `memory=None`.

### Backend Router

- [X] T006 [P] [US2] Add optional `session_summary: str | None = None` field to `AskRequest` Pydantic model in `backend/routers/manuals.py` — pass it through to the `manual_rag_service.ask()` call.
- [X] T007 [US2] Update the response dict in the `/manuals/ask` endpoint in `backend/routers/manuals.py` — include `session_summary` from the service result in the JSON response.

### Frontend Service

- [X] T008 [P] [US2] Update `askQuestion()` in `frontend/lib/services/manual_assistant_service.dart` — add optional `String? sessionSummary` parameter. Include `session_summary` in the request body JSON when not null. Parse `session_summary` from the response JSON and add it to the returned `ManualQaAnswer` model (or return it alongside — check the existing return type and extend as needed).

### Frontend UI

- [X] T009 [US2] Update `ChatTab` in `frontend/lib/screens/manual_assistant/chat_tab.dart` — (a) remove the `.sublist(_history.length - 10)` truncation so all history is sent, (b) add a `String? _sessionSummary` state field, (c) after receiving a response, store the returned `session_summary` in `_sessionSummary`, (d) pass `_sessionSummary` to `askQuestion()` in the service call.

**Checkpoint**: Full round-trip working. A 12+ turn conversation should show `[COMPRESS]` log entries on the backend. The assistant should remember early-conversation facts. Conversations ≤8 turns should work identically to before.

---

## Phase 3: US3 — Graceful Handling of Short Conversations (Priority: P2)

**Goal**: Verify no regression for conversations with ≤8 turns. No new code — this is a validation phase.

**Independent Test**: Conduct a 5-turn conversation and verify all turns appear as raw history with no compression. Verify `session_summary` is `null` in the response.

- [X] T010 [US3] Verify short conversation behavior in `backend/services/manual_rag_service.py` — confirm that when `len(history) <= 8`, the `ask()` method passes all turns to `_build_prompt()` with `memory=None` and returns `session_summary: null` in the result. No code change expected — this validates the conditional logic from T004.

**Checkpoint**: Short conversations (≤8 turns) behave identically to the current system.

---

## Phase 4: Polish & Cross-Cutting Concerns

**Purpose**: Edge case handling, fallback verification, documentation

- [X] T011 [US1] Verify incremental re-compression in `backend/services/manual_rag_service.py` — ensure that when a conversation grows from 9 to 13+ turns, the compression step re-compresses the existing summary (sent back from frontend) plus newly aged-out turns into an updated 3-4 sentence summary, rather than ignoring the old summary.
- [X] T012 [US1] Verify fallback behavior in `backend/services/manual_rag_service.py` — confirm that when `_compress_history()` returns `None` (Ollama failure), the `ask()` method falls back to passing `history[-10:]` to `_build_prompt()` with `memory=None`. Check that the `[COMPRESS] Compression failed` log entry is emitted.
- [X] T013 Run quickstart.md validation — follow the testing steps in `specs/045-rolling-session-summary/quickstart.md` end-to-end: 9+ turn conversation, verify memory retention, check logs, test failure fallback.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Foundational)**: No dependencies — can start immediately
- **Phase 2 (US1+US2)**: Depends on Phase 1 (T001, T002 must exist before T004/T005 integrate them)
- **Phase 3 (US3)**: Depends on Phase 2 (validation of behavior implemented in Phase 2)
- **Phase 4 (Polish)**: Depends on Phase 2 (edge case verification)

### User Story Dependencies

- **US1 (Seamless Long Conversations)**: Core compression — Phase 1 + Phase 2 backend tasks
- **US2 (Transparent Compression)**: Round-trip transport — Phase 2 router + frontend tasks. Can develop backend router (T006, T007) in parallel with US1 backend tasks (T004, T005) since they touch different files
- **US3 (Graceful Short Conversations)**: Validation only — no code, depends on Phase 2 completion

### Within Phase 2

- T004 depends on T001, T002 (uses the compression function and updated _build_prompt)
- T005 depends on T004 (modifies the same call site)
- T006 can run in parallel with T004/T005 (different file: manuals.py vs manual_rag_service.py)
- T007 depends on T006 (same file, sequential)
- T008 can run in parallel with T004-T007 (different file: Flutter service)
- T009 depends on T008 (uses the updated service method)

### Parallel Opportunities

```
Phase 1:  T001 → T002 (sequential, same file)
          T003 can run after T001 (same file, adds logging)

Phase 2:  T004,T005 (service)  ║  T006,T007 (router)  ║  T008 (Flutter service)
          └── all three streams can run in parallel ──────┘
          T009 depends on T008 only
```

---

## Parallel Example: Phase 2 Backend + Frontend

```
# These three streams can run in parallel (different files):
Stream A: T004 → T005  (backend/services/manual_rag_service.py)
Stream B: T006 → T007  (backend/routers/manuals.py)
Stream C: T008          (frontend/lib/services/manual_assistant_service.dart)

# Then sequentially:
T009 (frontend/lib/screens/manual_assistant/chat_tab.dart) — depends on T008
```

---

## Implementation Strategy

### MVP First (Phase 1 + Phase 2)

1. Complete Phase 1: Compression function + prompt update (T001-T003)
2. Complete Phase 2: Full round-trip integration (T004-T009)
3. **STOP and VALIDATE**: Test with 12+ turn conversation, verify memory retention
4. Deploy if ready — short conversations automatically work (US3)

### Incremental Delivery

1. Phase 1 → Compression engine ready (not yet wired in)
2. Phase 2 → Full feature working end-to-end (MVP!)
3. Phase 3 → Short conversation regression verified
4. Phase 4 → Edge cases validated, quickstart tested

---

## Notes

- No new files created — all changes modify existing files
- No database migrations required
- Frontend change is minimal: remove truncation, add one state field, pass it through
- The compression prompt in T001 should match the template in quickstart.md
- Fallback behavior (T012) is critical for production reliability
- The `session_summary` field is nullable in both request and response — `null` means no compression active
