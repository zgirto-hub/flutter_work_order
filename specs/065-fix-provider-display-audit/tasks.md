# Tasks: AI Provider Manager — Phase 2 Cleanups (Display Truth + Fallback Audit)

**Feature Branch**: `065-fix-provider-display-audit`
**Feature Dir**: `specs/065-fix-provider-display-audit/`
**Implementer**: Opencode (or other coding agent)
**Reviewer**: Claude Code via `superpowers:code-reviewer` skill

---

## BRANCH LOCK — READ BEFORE YOU TOUCH ANY CODE

**You MUST stay on branch `065-fix-provider-display-audit` for the entire implementation.**

- Verify before every commit: `git branch --show-current` → must print `065-fix-provider-display-audit`.
- Do NOT switch to `main`, `063-ai-provider-manager`, or any other branch.
- Do NOT merge anything into this branch.
- Do NOT push. Commits only.
- Do NOT rebase.
- Work in the repo at `c:/Development/flutter_work_order` (the main checkout). This branch does NOT require a worktree — the file set is tiny.
- If `git status` shows files outside the scope list below as modified, stop and ask.

## SCOPE LOCK

**Only these 6 files may be modified.** Do NOT touch anything else:

1. `backend/services/ai_providers/resolver.py`
2. `backend/services/manual_rag_service.py`
3. `backend/routers/manuals.py`
4. `frontend/lib/models/manual_ask_response.dart` (or equivalent — locate during T003)
5. `frontend/lib/widgets/ai_provider_chip.dart`
6. `frontend/lib/screens/manual_rag_screen.dart` (or whichever screen hosts the Ask-the-AI chat — locate during T003)

**No migrations. No new files. No new dependencies. No new endpoints. No new packages.**

If the task list seems to require a seventh file, stop and ask.

## HANDOFF PROTOCOL

When all tasks are checked and local smoke test passes:

1. Commit all changes on branch `065-fix-provider-display-audit` with a clear message.
2. Do NOT merge to main. Do NOT push.
3. Post a completion report listing: files changed, commits made, any deviations from the plan, and any questions.
4. Claude Code will then invoke `superpowers:code-reviewer` against this branch.
5. Iterate on review feedback on the same branch until SHIP verdict.

---

## Phase 1: Setup

- [x] T001 Verify branch is `065-fix-provider-display-audit` by running `git branch --show-current` in repo root `c:/Development/flutter_work_order`. If not, stop and ask.
- [x] T002 Read the following artifacts in full before writing any code: `specs/065-fix-provider-display-audit/spec.md`, `specs/065-fix-provider-display-audit/plan.md`, `specs/065-fix-provider-display-audit/research.md`, `specs/065-fix-provider-display-audit/data-model.md`, `specs/065-fix-provider-display-audit/contracts/ask_response_contract.md`, `specs/065-fix-provider-display-audit/quickstart.md`.
- [x] T003 Locate the exact Flutter files for the Ask-the-AI chat screen and the response model. Grep `frontend/lib/` for `/manuals/ask`, `manualRagScreen`, `ManualAskResponse`, or equivalent. Record the confirmed paths in the task notes before proceeding.

## Phase 2: Foundational

- [x] T004 Read the current implementation of `backend/services/ai_providers/resolver.py` end-to-end. Identify: the module-level TTL cache, the `generate()` function that orchestrates fallback, the exact tuple shape currently returned, and where `GeneratorModelError` is caught.
- [x] T005 Read `backend/services/manual_rag_service.py` and find every call site that invokes the resolver's `generate()` function (the spec notes three such sites from feature 063: cross-manual sub-answers, cross-manual synthesis, single-manual synthesis). List the exact file:line for each site before modifying.
- [x] T006 Read `backend/routers/manuals.py` and find the `/manuals/ask` handler. Locate where the requesting user's email is available (query param, token, or request body). Record the exact identifier name and flow.

## Phase 3: User Story 1 — Truthful provider/model label (P1)

**Story goal**: `/manuals/ask` response carries `provider_display_name`; Flutter chat footer renders it. Legacy `model` field kept as alias for one release.

**Independent test**: Switch active provider to Groq. Ask a question. Confirm response JSON has both `provider_display_name` and `model` set to the same string (`"Groq (Llama 3.3 70B)"`), and the chat footer under the answer shows that string — not `gemma4:e2b`.

- [x] T007 [US1] In `backend/services/ai_providers/resolver.py`, change the return contract of `generate()` so it returns the provider's `display_name` alongside the existing `(answer, provider_used, fallback_used)`. New tuple: `(answer, provider_used, provider_display_name, fallback_used)`. Compute `provider_display_name` from the concrete provider instance that actually produced the answer (including the fallback branch → Local's `display_name`). Do NOT change any other behavior.
- [x] T008 [US1] In `backend/services/manual_rag_service.py`, update every call site identified in T005 to unpack the new 4-tuple. Propagate `provider_display_name` into the response dict alongside the existing `provider_used` and `fallback_used`. Stamp `model` with the same string value as `provider_display_name` (backwards-compat per FR-009). Add a short inline comment referencing spec 065 next to the `model` stamp noting it is a deprecated alias slated for removal in a future spec. Do NOT remove `model`.
- [x] T009 [US1] In the Flutter `ManualAskResponse` model (path located in T003), add a nullable `String? providerDisplayName` field. Parse it from the JSON key `provider_display_name`. Keep the existing `model` field parsed as-is; do NOT remove it.
- [x] T010 [US1] In the Flutter Ask-the-AI chat screen (path located in T003), locate the footer line that currently renders `model` (something like `Text('${response.model} · ${duration}')`). Change it to prefer `providerDisplayName` with fallback to `model` then `'Unknown'`: `response.providerDisplayName ?? response.model ?? 'Unknown'`. Preserve everything else about the footer's styling and layout.
- [x] T011 [US1] Run the backend (`sudo systemctl restart document_server.service` or local equivalent). Switch active provider to Groq via curl. Ask a question via the Flutter app. Verify both the chip and the footer show `Groq (Llama 3.3 70B)`, and the response JSON in the Network tab contains both `provider_display_name` and `model` with identical values.

## Phase 4: User Story 2 — Fallback audit row (P1)

**Story goal**: Every fallback event produces exactly one `user_activity_log` row with action `ai_provider_fallback` and a closed-taxonomy `detail`.

**Independent test**: Invalidate a cloud provider's API key, switch active to that provider, ask a question. Verify one new `user_activity_log` row with `action='ai_provider_fallback'`, correct `target_label`/`target_id`, and `detail` ∈ `{quota_exceeded, timeout_30s, empty_response, missing_credentials, unknown}`. Verify no row is written for successful active-provider calls or for Local-fails-without-fallback.

- [x] T012 [US2] In `backend/routers/manuals.py`, thread the requesting user's email from the `/manuals/ask` handler into the call chain down to the resolver. If the email is already passed to `manual_rag_service` functions, extend the path; otherwise, add `user_email: str` as an explicit parameter on each function down to `resolver.generate()`. Do NOT fall back to "unknown" or "system" — if the email is missing from the request, raise the same HTTP error as any other missing-auth case.
- [x] T013 [US2] In `backend/services/manual_rag_service.py`, update every call to `resolver.generate()` to pass the threaded `user_email` parameter.
- [x] T014 [US2] In `backend/services/ai_providers/resolver.py`, add a closed-taxonomy classifier helper that maps an exception (or the reason string of a `GeneratorModelError`) to exactly one of: `quota_exceeded`, `timeout_30s`, `empty_response`, `missing_credentials`, `unknown`. Order:
    1. `asyncio.TimeoutError` → `timeout_30s`
    2. `GeneratorModelError` whose reason contains `"quota"` or `"429"` → `quota_exceeded`
    3. `GeneratorModelError` whose reason == `"missing_credentials"` → `missing_credentials`
    4. `GeneratorModelError` whose reason == `"empty_response"` → `empty_response`
    5. Anything else → `unknown`

    The helper MUST NOT return the raw exception message. Raw exception text goes to `logger.error(...)` only.

- [x] T015 [US2] In `backend/services/ai_providers/resolver.py`, extend `generate(...)` to accept the new `user_email: str` parameter. When fallback fires (non-Local active provider failed and Local succeeded), call `log_activity(...)` from `backend/utils/activity.py` exactly once with:
    - actor: `user_email`
    - `category='admin'` (matching the pattern used by `ai_provider_changed` in spec 063)
    - `action='ai_provider_fallback'`
    - `target_label=<failed_provider_key>`
    - `target_id=<fallback_provider_key>` (`'local'` in phase 1)
    - `detail=<classifier result from T014>`

    This call MUST be fire-and-forget (follow the existing pattern in the project; do NOT `await` it if the existing pattern doesn't). Do NOT write the row when the active provider succeeds. Do NOT write the row when the active provider IS Local and Local fails.

- [x] T016 [US2] Restart backend. Invalidate a cloud provider's key in `.env`, restart, switch active to that provider via curl, ask a question via Flutter, confirm fallback fires, then query `user_activity_log` (Supabase SQL editor or MCP) for the most recent `ai_provider_fallback` row. Verify all five columns match the spec. Also confirm NO row is written when you ask a successful question (after restoring the key). Also confirm NO row is written when active is Local and Local is simulated-down.

## Phase 5: User Story 3 — Chip reacts to fallback (P1)

**Story goal**: The Ask-the-AI chip transitions to `⚠ <display_name> (fallback)` warning state whenever the most recent response has `fallback_used: true`, and returns to healthy state on a successful active-provider response.

**Independent test**: Force fallback, verify chip turns amber and text becomes `⚠ Local (Ollama) (fallback)` without reloading. Restore key, ask another question, verify chip returns to `● <active_provider_display_name>` healthy state.

- [x] T017 [US3] In `frontend/lib/widgets/ai_provider_chip.dart`, add two optional parameters: `bool? fallbackUsed` and `String? displayNameOverride`. When `fallbackUsed == true`: render a warning visual state (amber/orange color scheme consistent with existing warning styling in the project; match whatever hue/icon the app already uses for warning chips elsewhere) with text `⚠ ${displayNameOverride ?? <active_provider_display_name>} (fallback)`. When `fallbackUsed == false`: render the existing healthy state but prefer `displayNameOverride` over the screen-open active provider. When both are null: behave exactly as today. Keep the existing API (constructor, named args) backwards-compatible.
- [x] T018 [US3] In the Ask-the-AI chat screen (path located in T003), track the last response's `providerDisplayName` and `fallbackUsed` as screen state. After each response is appended to the chat, update this state. Pass both values into `AiProviderChip` on the next rebuild.
- [x] T019 [US3] Smoke test: invalidate the key, switch active to a cloud provider, ask a question, confirm chip turns amber/warning with `⚠ Local (Ollama) (fallback)` text. Restore key, ask another question, confirm chip returns to `● <cloud_display_name>` healthy state. Confirm this happens WITHOUT reloading the page.

## Phase 6: Polish & Cross-cutting

- [x] T020 Run the full quickstart from `specs/065-fix-provider-display-audit/quickstart.md` end-to-end. All three stories' smoke tests must pass against a single running instance.
- [x] T021 Verify no regressions in the existing Ask-the-AI flow by asking 3 normal questions (no fallback) and confirming: answer renders, chip is healthy, footer shows the active provider's display name, no `ai_provider_fallback` rows appear in `user_activity_log`.
- [x] T022 Verify Arabic works: ask one Arabic question (e.g., `ما هو إجراء الفحص اليومي للمولد الاحتياطي؟`) and confirm the answer renders with proper RTL layout AND the chip/footer show the provider display name (which is Latin script — that's fine; the chip and footer do not need to be translated).
- [x] T023 Inspect the `/manuals/ask` response JSON one more time and confirm NO new field contains any API key, secret, or raw exception/stack trace (preserves SC-005 and spec 063 FR-016).
- [x] T024 Commit all changes on branch `065-fix-provider-display-audit`. Use a commit message of the form:

    ```
    feat(spec-065): truthful provider label, fallback audit row, chip warning state

    - Adds `provider_display_name` to /manuals/ask response (model retained as alias for 1 release)
    - Writes exactly one `ai_provider_fallback` row to user_activity_log on fallback
    - Chip transitions to ⚠ <display_name> (fallback) when fallback fires
    ```

    Do NOT push. Do NOT merge to main. Report completion.

---

## Dependency Graph

```
T001 (branch check)
  ↓
T002 (read docs)
  ↓
T003 (locate Flutter files)
  ↓
T004, T005, T006 (foundational reads — can run in any order, all must complete before phase 3)
  ↓
┌─────────────────┬─────────────────┬─────────────────┐
│                 │                 │                 │
US1 (T007-T011)   US2 (T012-T016)   US3 (T017-T019)
│                 │                 │
└─────────────────┴─────────────────┴─────────────────┘
                  ↓
     Polish (T020-T024)
```

**Note**: US1, US2, US3 each modify a disjoint subset of files:
- US1 touches resolver.py, manual_rag_service.py, ManualAskResponse model, chat footer line
- US2 touches resolver.py (different concern: audit call), routers/manuals.py, manual_rag_service.py (user_email threading)
- US3 touches ai_provider_chip.dart, chat screen state

Because US1 and US2 both touch `resolver.py` and `manual_rag_service.py`, do US1 fully FIRST, then US2. Do NOT parallelize US1 and US2. US3 is Flutter-only and CAN be done in parallel with US2, but it's a small feature — do it sequentially for review simplicity.

**Recommended order**: T001 → T002 → T003 → T004 → T005 → T006 → T007 → T008 → T009 → T010 → T011 → T012 → T013 → T014 → T015 → T016 → T017 → T018 → T019 → T020 → T021 → T022 → T023 → T024.

## Implementation Strategy

**MVP** = User Story 1 alone. If you had to ship before finishing everything, US1 (truthful footer) removes the most user-visible confusion. US2 (audit) is also P1 but less user-visible in the short term. US3 (chip warning) is P1 and also user-visible during fallback.

The spec has all three as P1 because together they close the FR-010, FR-014, FR-015 gaps from spec 063. Do all three.

## Deviations from plan (recorded 2026-04-15, post-merge)

1. **Audit write moved from resolver to router.** T015 said `log_activity(...)` is called from inside `resolver.generate()`. The merged implementation instead has the resolver return a `_fallback_info` dict and `backend/routers/manuals.py` performs the write. Call sites in `manual_rag_service.py` must propagate the dict upward. Documented in `resolver.generate()` docstring so future callers don't silently drop audit rows.
2. **Scope lock was 6 files; actual modified = 7.** `backend/services/agentic_tools.py` was added to the modified set to thread `user_email` through the agentic path — without it, FR-003 breaks whenever the agentic router handles the request. Necessary deviation; the original scope list was wrong about the call graph.
3. **Flutter file paths differ from scope-lock guesses.** Actual files touched: `frontend/lib/models/manual_qa_answer.dart` (not `manual_ask_response.dart`), `frontend/lib/screens/manual_assistant/chat_tab.dart` (not `manual_rag_screen.dart`), `frontend/lib/screens/manual_assistant/widgets/answer_card.dart` (footer line). `ai_provider_chip.dart` was NOT modified — it already supported the warning state from spec 063. All resolved under T003.
4. **Post-review follow-up patch (uncommitted at time of writing):**
   - `chat_tab.dart` fallback detection simplified from `providerUsed == 'local' && fallbackUsed == true` to just `fallbackUsed == true` (robust to future cloud-to-cloud fallback).
   - `manuals.py` audit-row `target_label` / `target_id` defaults changed from `"local"` to `"unknown"` (so a missing `failed_provider` in `_fallback_info` isn't indistinguishable from a real Local-destination audit row).
   - `resolver.generate()` gained a module-level docstring documenting the caller contract for `_fallback_info` propagation (mitigates deviation #1).

## Format validation

All tasks use the required format: `- [ ] TNNN [P?] [USN?] Description with file path`. Setup/foundational/polish phases have no story label; user-story phases have the story label.

Total: 24 tasks.
- Setup: 3
- Foundational: 3
- US1: 5
- US2: 5
- US3: 3
- Polish: 5

No parallel `[P]` markers used — everything is strictly sequential to keep the review simple.
