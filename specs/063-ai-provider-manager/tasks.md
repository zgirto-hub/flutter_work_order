---
description: "Task list for 063-ai-provider-manager implementation by opencode LLM"
---

# Tasks: AI Provider Manager — Extensible Multi-Provider System

**Input**: Design documents from `/specs/063-ai-provider-manager/`
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/ai_providers_api.md](./contracts/ai_providers_api.md), [quickstart.md](./quickstart.md)

---

## 🛑 READ FIRST — Instructions for the implementing LLM (opencode)

You are implementing feature **063-ai-provider-manager** on the Flutter + FastAPI + Supabase work-order project.

**Branch discipline (critical)**:
- The branch `063-ai-provider-manager` is **already created and checked out**. **DO NOT** create a new branch. **DO NOT** checkout main.
- Every commit for this feature MUST land on `063-ai-provider-manager`.
- Before your first commit, run `git status` and `git rev-parse --abbrev-ref HEAD` and confirm output is `063-ai-provider-manager`. If not, stop and ask.
- Commit after each logical group of tasks (small commits preferred). Conventional commit style matching recent history (`feat(spec-063): ...`, `fix(spec-063): ...`, `chore(spec-063): ...`).
- **Do not push, do not open a PR.** Claude Code will review after you finish and handle integration.
- **Never commit `backend/version.json`** (see memory: `project_infrastructure.md` — it conflicts with server's local state).
- Do not run `flutter build web` or `bump_version.sh` or any deploy script. Implementation only.

**Scope discipline (critical)**:
- Phase 1 scope per Clarifications is **Ask-the-AI (`/manuals/ask`) only**. Do NOT touch other AI-using features (WO description, analytics insights, NL search, query rewrite, HyDE, reranking, session summary, cross-manual synthesis, agentic tools, entity extraction).
- Do NOT implement `embed()` on any provider — base class raises `NotImplementedError`. That is the correct phase-1 behavior (clarification Q2).
- Do NOT add provider chip to any UI other than Ask-the-AI (clarification Q5).
- Do NOT retry the active provider before falling back (clarification Q4).
- Do NOT change `ollama_generator.py`; wrap it from `OllamaProvider`.

**Quality discipline**:
- Follow existing repo patterns. Look at neighbors first:
  - Routers: pattern from `backend/routers/manuals.py`, `backend/routers/ai_assist.py`.
  - Services: pattern from `backend/services/ollama_generator.py`, `backend/services/manual_rag_service.py`.
  - Flutter models: pattern from `frontend/lib/models/` neighbors.
  - Flutter services: `frontend/lib/services/` neighbors.
  - Activity log: use `backend/utils/activity.py` (`log_activity`) fire-and-forget.
- No comments that only restate what the code does. Comments only for non-obvious WHY.
- No premature abstraction, no unused helpers, no speculative config knobs.
- Dart: `const` constructors where possible, `ClaudeWidgets` / `AppColors` / `AppShadows` / `AppTheme` for anything user-visible, matching existing Flutter style.
- When in doubt, match the surrounding file's style.

**If you get stuck**:
- Re-read the spec's Clarifications section and FR-### you are working on.
- If a requirement conflicts with what you find in existing code, stop and leave a TODO note in `tasks.md` next to the task rather than guessing.

---

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no ordering dependency)
- **[Story]**: User story the task serves — [US1], [US2], [US3], [US4]
- Every task includes an exact file path.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Branch safety check, dependency installation, environment wiring.

- [ ] T001 Verify you are on branch `063-ai-provider-manager`; if not, stop. Command: `git rev-parse --abbrev-ref HEAD`. Expected output: `063-ai-provider-manager`.
- [ ] T002 Add `google-generativeai` to `backend/requirements.txt` (latest stable; pin to at least `>=0.8.0`). Do NOT upgrade any other pinned dep.
- [ ] T003 [P] Append the following line to `.env.example` at repo root (create the file if missing, preserve existing keys): `GEMINI_API_KEY=` (empty; admin configures on server). Do NOT write a real key here.
- [ ] T004 [P] Document the new env var in `AGENT.md` under the existing env-vars list (one line: `GEMINI_API_KEY — Google AI Studio key for Gemini 2.5 Flash provider (spec 063)`). If `AGENT.md` has no env-vars section, skip (do not create a new section — flag in tasks.md as a TODO for Claude review).

---

## Phase 2: Foundational (Blocking Prerequisites)

**⚠️ No user story work can begin until this phase is complete.**

- [ ] T005 Create migration file `supabase/migrations/20260415_app_settings.sql` implementing the schema in [data-model.md](./data-model.md) §`app_settings`. Include: `CREATE TABLE public.app_settings (...)`, RLS enable, a permissive SELECT policy for authenticated users, and INSERT of the two seed rows (`ai_provider='local'`, `ai_providers_available='["local","gemini"]'`). No UPDATE/DELETE policies for the client — backend writes via service-role key.
- [ ] T006 Create `backend/utils/app_settings.py` with: `async def get_setting(key: str) -> str | None`, `async def set_setting(key: str, value: str, updated_by: str | None) -> None`, both using the existing Supabase client import pattern from `backend/routers/manuals.py` (look for `from supabase_client import supabase` or equivalent). Use service-role writes. No caching in this module — caching lives in `resolver.py` (T010).
- [ ] T007 Create `backend/services/ai_providers/__init__.py` (empty package marker).
- [ ] T008 [P] Create `backend/services/ai_providers/base.py` defining `class AIProvider(ABC)` exactly as specified in [data-model.md](./data-model.md) "In-memory / transient entities". Include:
  - `display_name: str` abstract property
  - `async def generate(self, prompt: str, context_chunks: list[str]) -> str` abstract method
  - `async def health_check(self) -> bool` abstract method
  - `async def embed(self, text: str) -> list[float]` concrete method that raises `NotImplementedError("embed() is reserved for future providers; not implemented in phase 1")`. Do NOT make it abstract.
- [ ] T009 [P] Create `backend/services/ai_providers/registry.py` with a single module-level dict `PROVIDERS: dict[str, type[AIProvider]] = {"local": OllamaProvider, "gemini": GeminiProvider}`. Import both provider classes at the top of the file. Do NOT instantiate providers here — store classes.

---

## Phase 3: User Story 1 — Admin switches active AI provider (P1) 🎯 MVP

**Goal**: Admin can open Settings, pick a provider from a dynamically-populated selector, save, and have the active-provider value propagate to all `/manuals/ask` calls within 60 seconds.

**Independent Test**: Log in as Admin, switch from Local → Gemini in Settings, wait ≤60s, submit a question in Ask-the-AI, inspect the response JSON to confirm `provider_used: "gemini"`.

### Backend — providers

- [ ] T010 [US1] Create `backend/services/ai_providers/resolver.py` with:
  - Module-level cache: `_cache: dict = {"value": None, "expires_at": 0.0}`, `_TTL_SECONDS = 60`.
  - `async def get_active_provider_key() -> str` — returns cached key, refreshing from `app_settings` when `time.monotonic() >= expires_at`. On Supabase read failure, return last known value or `"local"` as hard default; log the error via existing logging.
  - `def _resolve_provider(key: str) -> AIProvider` — looks up in `PROVIDERS` registry, raises `ValueError` on unknown key.
  - `async def generate(prompt: str, context_chunks: list[str], user_email: str | None = None) -> tuple[str, str, bool]` — returns `(answer, provider_used, fallback_used)`. Implements the fallback orchestration from [research.md](./research.md) §R4: resolve active, wrap with `asyncio.wait_for(active.generate(...), timeout=30)`. Do NOT implement fallback in this task — leave a clear `raise NotImplementedError("fallback wired in T019")` placeholder for now OR implement a no-fallback version here and extend in T019. (**Recommendation**: stub the fallback path here; wire it in T019 to keep US2 as an independent slice.)
- [ ] T011 [P] [US1] Create `backend/services/ai_providers/local_ollama.py` defining `class OllamaProvider(AIProvider)`:
  - `display_name = "Local (Ollama)"`.
  - `generate()` wraps the existing `services.ollama_generator.generate()` with the existing prompt-construction pattern used in `manual_rag_service.py` for the Ask-the-AI synthesis step. Read how `manual_rag_service` currently builds the synthesis prompt and replicate the identical call so output quality is unchanged.
  - `health_check()`: return `True` if a short HTTP GET to `http://localhost:11434/api/tags` returns 200 within 5 seconds, else `False`. Reuse httpx if already imported elsewhere.
- [ ] T012 [P] [US1] Create `backend/services/ai_providers/gemini.py` defining `class GeminiProvider(AIProvider)`:
  - `display_name = "Gemini 2.5 Flash"`.
  - `__init__`: reads `GEMINI_API_KEY` from env via `os.getenv`. If missing, store `self._api_key = None` — don't raise; `health_check()` must return False cleanly.
  - `generate(prompt, context_chunks)`: uses `google-generativeai`, model `"gemini-2.5-flash"`. Assemble the prompt by prepending a short system instruction (copy the current system instruction from `manual_rag_service.py` synthesis if present) then the chunks then the user question — keep the prompt structurally identical to Ollama's to ensure comparable output quality.
  - On any Gemini SDK exception or empty text response, raise a subclass of `GeneratorModelError` (import from `services.ollama_generator`) so existing `/manuals/ask` error handling continues to work. Scrub the API key from any error message before re-raising.
  - `health_check()`: if api_key missing, return False. Otherwise issue a cheap generate call ("ping", max_output_tokens=4) wrapped in `asyncio.wait_for(..., timeout=10)`; return True on any non-empty text, False otherwise. Do NOT raise.
- [ ] T013 [US1] Create `backend/routers/ai_providers.py` with three endpoints from [contracts/ai_providers_api.md](./contracts/ai_providers_api.md):
  - `GET /api/ai/providers` — intersects `ai_providers_available` with `PROVIDERS` registry keys; returns `{providers: [{key, display_name}], active}`. Any authenticated user.
  - `POST /api/ai/provider` body `{provider: str}` — Admin-only. Validate membership in available list AND registry. On success, upsert setting, log via `log_activity(category="admin", action="ai_provider_changed", target_label=new, detail=f"old={prev}")`. Return `{active, updated_at}`.
  - `GET /api/ai/provider/health` — Admin-only. Calls `resolver.get_active_provider_key()`, instantiates provider, runs `health_check()`. Return `{provider, healthy, reason?}`. Map internal reasons to short strings: `missing_credentials`, `timeout`, `connection_refused`, `upstream_error`, `unknown`.
  - Role check: match existing pattern used elsewhere in routers for Admin-only endpoints (look at how `backend/routers/` gates Admin actions today — probably a dependency on `get_current_user` plus a role check; replicate that pattern, do not invent a new one).
- [ ] T014 [US1] Register the new router in `backend/main.py` next to existing router includes: `app.include_router(ai_providers.router, prefix="/api", tags=["ai-providers"])`. Preserve ordering relative to neighbors.
- [ ] T015 [US1] Modify `backend/routers/manuals.py` `/manuals/ask` handler (around line 324) OR the underlying `agentic_tools.run_agentic_loop` / `manual_rag_service` synthesis step — whichever actually performs the final answer generation — to route the synthesis call through `services.ai_providers.resolver.generate(prompt, chunks, user_email)`. Preserve ALL existing behavior upstream (greeting bypass, retrieval, agentic loop, history rewrite). Add `provider_used` and `fallback_used` to the response JSON. Do not remove any existing response field. If the call chain has multiple generation sites, route ONLY the user-facing final synthesis — do NOT touch helper-model calls like query rewrite or HyDE.

### Frontend — admin settings

- [ ] T016 [P] [US1] Create `frontend/lib/models/ai_provider.dart` with two immutable classes:
  - `AiProvider { final String key; final String displayName; }` with `fromJson` constructor.
  - `AiProvidersResponse { final List<AiProvider> providers; final String active; }` with `fromJson`.
- [ ] T017 [P] [US1] Create `frontend/lib/services/ai_provider_service.dart` with methods mirroring the contracts:
  - `Future<AiProvidersResponse> listProviders()` — GET `/api/ai/providers`.
  - `Future<void> setActiveProvider(String key)` — POST `/api/ai/provider`.
  - `Future<({String provider, bool healthy, String? reason})> getHealth()` — GET `/api/ai/provider/health`.
  - Reuse existing auth-header / base-URL wiring from a neighbor service (e.g., `work_order_service.dart` or `department_service.dart`) — do not invent new HTTP plumbing.
- [ ] T018 [US1] Modify `frontend/lib/screens/settings_screen.dart` (or the project's equivalent Admin settings screen — discover via grep) to add a new "AI Assistant" section visible only when the current user is Admin. UI:
  - A dropdown/segmented selector populated from `listProviders()`.
  - A health status indicator (small green dot = healthy, red dot = unhealthy) driven by `getHealth()`; refresh on screen open and after Save.
  - A Save button that calls `setActiveProvider(...)`, shows a success toast (`ScaffoldMessenger` snackbar matching existing toast style), and re-fetches health.
  - Non-Admin users must not see the section at all.
  - Use `AppColors` / `AppTheme` / shared widgets from `claude_widgets.dart` where available — do not introduce bespoke styling.

---

## Phase 4: User Story 2 — Automatic fallback when active provider fails (P1)

**Goal**: When a non-Local active provider fails (exception, >30s timeout, quota error, empty response), the system retries with Local Ollama, returns the answer with a fallback flag, and logs the event. If active IS Local and fails, return a clear error (no fallback).

**Independent Test**: With active=Gemini, invalidate `GEMINI_API_KEY`, restart backend, submit a question, verify user gets a Local answer with `fallback_used: true` and a `user_activity_log` row exists with `action='ai_provider_fallback'`.

- [ ] T019 [US2] Extend `backend/services/ai_providers/resolver.py` `generate()` to implement full fallback logic:
  - Wrap `active.generate(...)` in `asyncio.wait_for(..., timeout=30)`.
  - Catch `asyncio.TimeoutError`, any `Exception` from the provider call, and empty/invalid text responses (empty string, whitespace-only).
  - If `active_key != "local"`: on failure, call `OllamaProvider().generate(...)`; if that succeeds, return `(answer, "local", True)`; if it also fails, raise `GeneratorUnavailableError` (existing exception from `services.ollama_generator`).
  - If `active_key == "local"`: on failure, raise `GeneratorUnavailableError` directly — no fallback (clarification Q4).
  - On every fallback occurrence, call `log_activity(user_email, category="admin", action="ai_provider_fallback", target_label=active_key, target_id="local", detail=<short_reason>)`. `<short_reason>` is one of: `timeout>30s`, `quota_exceeded` (when Gemini SDK raises a quota error — detect by exception class name or message substring `quota`), `empty_response`, `exception:<ClassName>`.
  - Failure detection and logging MUST NOT themselves raise to the caller if logging fails — logging is fire-and-forget.
- [ ] T020 [US2] Verify that `backend/routers/manuals.py` `/manuals/ask` response already carries `provider_used` and `fallback_used` from T015. No new fields needed. Ensure existing `EmbedderUnavailableError` / `GeneratorUnavailableError` / `GeneratorModelError` → HTTP mapping continues to serve the right status codes and user messages.

---

## Phase 5: User Story 3 — Provider status visibility for all users (P2)

**Goal**: Every user on the Ask-the-AI chat screen sees a small read-only chip naming the active provider, with a distinct warning state when the last response used fallback.

**Independent Test**: Open the Ask-the-AI screen as any role; chip appears and matches the `active` returned by `GET /api/ai/providers`. After a fallback occurs, the chip flips to a fallback-warning variant.

- [ ] T021 [P] [US3] Create `frontend/lib/widgets/ai_provider_chip.dart` — a stateless widget taking `String providerDisplayName` and `bool fallbackUsed`. Default state: neutral chip with a small filled dot and the display name (e.g., `● Gemini 2.5 Flash`). Fallback state: amber/warning background with text like `⚠ Local (fallback)`. Use `AppColors` and match the app's existing chip/badge patterns (look at `StatusBadge` neighbor for styling cues). No tap action in phase 1.
- [ ] T022 [US3] Modify the Ask-the-AI chat screen (discover via grep for `/manuals/ask` or `manual_rag` in `frontend/lib/screens/`) to:
  - On screen open, fetch `listProviders()` once and store the active display name.
  - Render `AiProviderChip` in the screen header (or existing app-bar action slot — match surrounding style).
  - When a response from `/manuals/ask` arrives with `fallback_used: true`, set the chip to fallback state for the next render; clear it on the next non-fallback response.
  - Chip visible to ALL roles; do NOT role-gate it.
  - Do NOT add this chip to any other screen (clarification Q5).

---

## Phase 6: User Story 4 — Extensibility verification (P2)

**Goal**: Prove the architecture: a stub new provider appears in the Admin selector without a Flutter rebuild.

**Independent Test**: Follow the steps below, observe stub appears, then remove the stub.

- [ ] T023 [US4] Add a short "Extensibility verification" section to [quickstart.md](./quickstart.md) cross-referencing the Story-4 smoke test already documented there — no code changes needed; confirm the existing smoke-test section matches the real registry/setting names shipped in T005/T009. If any path drifted during implementation, update quickstart.md to match.

---

## Phase 7: Polish & Cross-Cutting

- [ ] T024 [P] Update `AGENT.md` and `ARCHITECTURE.md` (if present) with a short paragraph describing the AI Provider Manager: where the abstraction lives, how to add a provider, the 60s TTL semantic, the Local-only-no-fallback rule. Do not duplicate spec/plan content; link to them.
- [ ] T025 [P] Run the smoke tests in [quickstart.md](./quickstart.md) — Story 1, Story 2, Story 4. Record any discrepancies at the bottom of this file as `### Implementation notes` bullets. Do NOT mark tasks complete if smoke tests fail.
- [ ] T026 Grep the diff for accidental leakage: no hard-coded provider list in `frontend/`; no `GEMINI_API_KEY` printed or returned anywhere; no comment like `# TODO` or `# FIXME` without a clear next step; no modifications to AI features other than `/manuals/ask` synthesis. Fix any leak before finishing.
- [ ] T027 Final commit and stop. Do NOT push. Do NOT merge. Do NOT delete the branch. Leave `063-ai-provider-manager` in a clean committed state and report to Claude Code for review with the commit hash range.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: no deps.
- **Phase 2 (Foundational)**: depends on Phase 1. **Blocks all user stories.**
- **Phase 3 (US1 / P1 / MVP)**: depends on Phase 2.
- **Phase 4 (US2 / P1)**: depends on Phase 3 (specifically T010 resolver scaffold and T015 routing integration).
- **Phase 5 (US3 / P2)**: depends on T013 (GET /providers endpoint) and T015 (response shape). Independent of US2.
- **Phase 6 (US4 / P2)**: depends on Phase 5 quickstart text being accurate and T005/T009 naming being final.
- **Phase 7 (Polish)**: depends on all user stories complete.

### Within Phase 3 (US1)

- T010 before T013 (router imports resolver).
- T011, T012 can run in parallel ([P]) — different files.
- T013 after T011 + T012 (router instantiates providers via registry).
- T014 after T013 (main.py includes router).
- T015 after T010 (synthesis call uses resolver).
- T016, T017 can run in parallel with backend tasks — different files.
- T018 after T016 + T017.

### Parallel Opportunities

- T003, T004 in parallel after T002.
- T008, T009 in parallel after T007.
- T011, T012 in parallel after T008, T009.
- T016, T017 in parallel with backend T010–T015.
- T021 in parallel with backend T019, T020.
- T024, T025 in parallel after Phase 6.

---

## Parallel example: Phase 3 kickoff

```text
After T010 (resolver scaffold) lands:
- Agent A: T011 (local_ollama.py)
- Agent B: T012 (gemini.py)
- Agent C: T016 (ai_provider.dart model)
- Agent D: T017 (ai_provider_service.dart)
```

---

## Implementation Strategy

### MVP (minimum to demo)

Phase 1 → Phase 2 → Phase 3 (US1 only). At this point an Admin can switch provider and Ask-the-AI routes through it. Fallback is stubbed; if Gemini fails, the user sees an error — acceptable for MVP demo, blocker for production.

### Production-ready

MVP + Phase 4 (US2 fallback). At this point the system is resilient. Phases 5–7 are UX polish and docs.

---

## Implementation notes

*(opencode: append bullets here as you finish each phase. Record any spec/plan drift, any patterns you couldn't cleanly match, and any scope-edge decisions you had to make.)*

- _(leave blank initially)_

---

## Review handoff

When you finish T027, report back with:

1. Confirmation you are still on branch `063-ai-provider-manager` and have NOT pushed.
2. Commit hash range (`git log --oneline` output since branching from main).
3. A short list of any deviations from this tasks.md (with rationale).
4. Any failing smoke tests from T025.

Claude Code will then run a **superpowers:code-reviewer** pass against this plan and the constitution, and either ship or request changes.
