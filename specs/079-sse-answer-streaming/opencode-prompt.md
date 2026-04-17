# Implementation Instructions: 079 — AI Assistant Answer Streaming (SSE)

**Branch**: `079-sse-answer-streaming` (already checked out)  
**Task file**: `specs/079-sse-answer-streaming/tasks.md`  
**Plan**: `specs/079-sse-answer-streaming/plan.md`  
**Contract**: `specs/079-sse-answer-streaming/contracts/sse-stream-endpoint.md`  
**Research**: `specs/079-sse-answer-streaming/research.md`

---

## What to do

Read and implement every task in `specs/079-sse-answer-streaming/tasks.md`, in order from T001 to T022. Each task has the exact file path to edit, the code pattern to follow, and the acceptance criteria. Do not skip tasks or reorder them unless a task explicitly says [P] (parallelizable).

## Rules — read these BEFORE writing any code

### 1. Raw outputs only, never summaries
Do not paraphrase command output. Paste the full terminal output verbatim inside a code block. Summaries are forbidden. If a command errored, paste the error exactly as printed — do not claim "works" based on a subset that passed.

### 2. Banned phrases
You may not write any of: "verified via direct Python", "pre-existing environment issue", "core logic verified", "manual verification recommended". If you cannot run the required command, STOP and write "blocked by \<specific reason\>" and nothing else. Do not pivot to a weaker form of verification.

### 3. Plumbing tasks require call-site proof
When you add a method or parameter to a function/class, list the exact callers you updated. No bulk claims like "all call sites updated". Show the grep output.

### 4. One logical change per commit; stop after the batch
Commit after each numbered task (T001, T002, etc.). One task = one commit. Do not batch unrelated changes into one commit. Commit message format: `feat(079): T0XX — <short description>`.

### 5. No tangential commits
Do not modify any file not explicitly listed in the task. If you think another file should change, write a "Deviations proposed" section with the reason and **wait** — do not make the change. Never run `bump_version.sh`, never edit `version.json`, never edit `pubspec.yaml` version field.

### 6. Do not break the existing endpoint
The existing `POST /manuals/ask` endpoint must remain untouched. Do not modify its function body, its response schema, or its imports. The new streaming endpoint lives alongside it — it does not replace it.

### 7. Preserve existing code patterns
Read each file before editing. Match the existing code style: same import conventions, same error handling patterns, same logging patterns. Do not add type annotations, docstrings, or reformatting to code you didn't change.

### 8. Follow the contract exactly
The SSE event format is defined in `specs/079-sse-answer-streaming/contracts/sse-stream-endpoint.md`. Token events are `data: <text>\n\n`. Metadata is `event: metadata\ndata: <json>\n\n`. Error is `event: error\ndata: <json>\n\n`. Do not invent additional event types or change the format.

### 9. Provider generate_stream() must match generate()
Each provider's `generate_stream()` must build the prompt identically to its `generate()`. Copy the prompt construction — do not rewrite it. The only difference is the generation call (streaming vs awaited).

### 10. Frontend: no new packages
Use the `http` package (already in pubspec) for SSE parsing. Do not add `eventsource`, `sse_client`, or any other package. Parse SSE lines manually from the chunked byte stream.

---

## Execution order

```
Phase 1: T001 (setup — add sse-starlette to requirements.txt)
Phase 2: T002, then T003+T004+T005+T006+T007 in parallel, then T008
Phase 3: T009, T010, T011, T012, T013, T014 (sequential — each builds on previous)
Phase 4: T015, T016
Phase 5: T017, T018
Phase 6: T019, T020, T021, T022
```

After completing Phase 3, STOP and report. This is the MVP checkpoint. I will review before you continue to Phase 4.

## Key files to read before starting

Before writing any code, read these files to understand the existing patterns:

- `backend/services/ai_providers/base.py` — provider ABC
- `backend/services/ai_providers/resolver.py` — generation + fallback logic
- `backend/services/ollama_generator.py` — Ollama HTTP calls
- `backend/services/ai_providers/local_ollama.py` — how providers delegate
- `backend/services/ai_providers/gemini.py` — Gemini SDK usage
- `backend/services/manual_rag_service.py` (lines 606-750) — the `ask()` function
- `backend/routers/manuals.py` (lines 341-511) — the existing ask endpoint
- `frontend/lib/services/manual_assistant_service.dart` (lines 211-269) — `askQuestion()`
- `frontend/lib/screens/manual_assistant/chat_tab.dart` (lines 79-129) — `_sendQuestion()`
- `frontend/lib/screens/manual_assistant/widgets/answer_card.dart` — AnswerCard widget
- `server/nginx/flutter_app.conf` — Nginx config (SSE block goes before line 40)

---

**Honesty discipline**: Pass/fail is determined by command output, not your assessment. If a command fails, the task has failed — regardless of how small the failure looks. "Blocked" is an acceptable state; "done with caveats" is not. If the task list says run X and X fails, the next line in your report is the failure, not a workaround you substituted. Trust in your reports is the only thing that makes the review cycle shorter than the implementation cycle, and it is easy to lose permanently.
