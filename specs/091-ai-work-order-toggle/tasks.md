# Tasks: AI Work Order Toggle

**Input**: Design documents from `/specs/091-ai-work-order-toggle/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Database migration for the new `ai_work_order_enabled` setting

- [x] T001 Create migration file `supabase/migrations/20260421000000_ai_work_order_toggle.sql` that seeds `ai_work_order_enabled = false` into `app_settings` table (INSERT ... ON CONFLICT DO NOTHING)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Backend infrastructure that MUST be complete before any user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T002 Implement in-memory `RateLimiter` class in `backend/services/rate_limiter.py` with `check(user_email) -> (allowed, retry_after_seconds)` method enforcing 10 requests/min and 100 requests/day per user, pruning expired timestamps on each check
- [x] T003 [P] Add `getAiWorkOrderEnabled` and `setAiWorkOrderEnabled` methods to `frontend/lib/services/ai_provider_service.dart` following the existing `getSmartPreprocessing`/`setSmartPreprocessing` pattern (GET/PUT `/settings/ai-work-order?admin_email={email}`)
- [x] T004 [P] Add `autofillWorkOrder` method to `frontend/lib/services/ai_assist_service.dart` that POSTs to `/ai/autofill-work-order` with description, language, departments, types, statuses; handles 403/422/429/502/503 error responses

**Checkpoint**: Foundation ready — rate limiter exists, frontend service methods exist

---

## Phase 3: User Story 1 — Admin disables/enables AI Work Order globally (Priority: P1) 🎯 MVP

**Goal**: Admin can toggle AI Work Order ON/OFF in a new "AI Features" settings section. When OFF, no AI element is visible on the Add Work Order screen. When ON, AI Assist entry appears.

**Independent Test**: Set toggle OFF in Admin settings; confirm no AI element on Add Work Order screen for any role. Set ON; confirm AI Assist entry appears. Non-admin cannot access AI Features section.

### Implementation for User Story 1

- [x] T005 Add GET `/api/settings/ai-work-order` endpoint in `backend/routers/ai_providers.py` following the `get_smart_preprocessing` pattern: verify admin via `admin_email` query param, read `ai_work_order_enabled` from `app_settings`, return `{enabled: bool, updated_at: str}`
- [x] T006 Add PUT `/api/settings/ai-work-order` endpoint in `backend/routers/ai_providers.py` following the `set_smart_preprocessing` pattern: verify admin, upsert `ai_work_order_enabled` via `set_setting`, log to `user_activity_log` with `category='admin'` and `action='ai_work_order_toggled'`
- [x] T007 Add "AI Features" section to `frontend/lib/screens/settings_page.dart` containing an "AI Work Order" toggle tile (SurfaceCard + Switch pattern matching `SmartPreprocessingSection`), visible only to admin users, using `AiProviderService.getAiWorkOrderEnabled`/`setAiWorkOrderEnabled` with optimistic UI update and rollback on error
- [x] T008 Modify `frontend/lib/screens/Work_Orders/add_work_order.dart` to fetch `_aiWorkOrderEnabled` via `AiProviderService.getAiWorkOrderEnabled` in `initState()` (default `false` on failure), and wrap the existing `NlInputCard` (line 1510) with `_aiWorkOrderEnabled` condition so it is hidden when the toggle is OFF
- [x] T009 Ensure `_aiWorkOrderEnabled` is NOT fetched for edit-mode screens (add a role-based fetch or skip when `widget.workOrder != null`) — the AI assist entry is only for new work orders

**Checkpoint**: At this point, User Story 1 is fully functional — admin can toggle, and all users see/hide the AI entry based on toggle state

---

## Phase 4: User Story 2 — Technician uses AI to draft a work order (Priority: P2)

**Goal**: When toggle is ON, any user can tap AI Assist, enter a description, receive field suggestions, and confirm overwrite choices for conflicting fields.

**Independent Test**: With toggle ON, any authenticated user taps AI Assist, types a description ≥ 20 chars, receives populated form fields. If some fields are pre-filled, the overwrite dialog shows. Error handling works (timeout, server error).

### Implementation for User Story 2

- [x] T010 Add POST `/api/ai/autofill-work-order` endpoint in `backend/routers/ai_assist.py` with: (1) auth check — require `user_email` query param, reject 401 if missing; (2) toggle check — read `ai_work_order_enabled` from `app_settings`, reject 403 if OFF; (3) rate limit check — call `rate_limiter.check(user_email)`, reject 429 if exceeded; (4) validate description 20–500 chars, reject 422; (5) call `resolver.generate()` with engineered English prompt; (6) parse and return structured JSON with title, description, priority, category, asset_name, fault_description, action_taken, outcome
- [x] T011 Create `frontend/lib/widgets/ai_overwrite_dialog.dart` implementing a side-by-side conflict preview dialog: receives `{String fieldName, String current, String proposed}[]`, each row has "Keep mine" (default) / "Use AI" radio buttons, "Apply" and "Cancel" actions; returns a `Map<String, bool>` indicating which fields to overwrite
- [x] T012 Modify `frontend/lib/screens/Work_Orders/add_work_order.dart` `_generateFromNl()` method to: (1) call `AiAssistService.autofillWorkOrder` instead of just description suggestion; (2) for each returned field, if the corresponding controller/dropdown is empty, fill immediately; (3) if any controller/dropdown has user-entered text and AI proposes a different value, collect conflicts and show `AiOverwriteDialog`; (4) apply only user-confirmed overwrites; (5) handle errors (502/503/429) by showing a SnackBar and preserving form state
- [x] T013 [US2] Add input validation in `NlInputCard` or the calling code in `add_work_order.dart`: before calling the autofill endpoint, check description length ≥ 20 chars; if shorter, show a user-facing message "Description must be at least 20 characters" and do not make the API call; also reject descriptions > 500 chars
- [x] T014 [US2] Add loading/cancel UX to the AI Assist flow in `add_work_order.dart`: show blocking spinner with "Usually a few seconds..." hint text and a Cancel button while the autofill request is in flight; Cancel aborts the request, preserves the description input, and returns the user to the input surface

**Checkpoint**: At this point, User Stories 1 AND 2 both work — AI Assist is togglable and the autofill + overwrite flow works end-to-end

---

## Phase 5: User Story 3 — Server refuses autofill when feature is disabled (Priority: P2)

**Goal**: Server-side enforcement ensures that even if a client bypasses the UI, the autofill endpoint refuses requests when the toggle is OFF or the user is not authenticated. Non-admin cannot change the toggle setting.

**Independent Test**: Disable toggle, send a direct POST to `/ai/autofill-work-order`, confirm 403 response and no AI provider call. Send unauthenticated request → 401. Send toggle-change request as non-admin → 403.

### Implementation for User Story 3

- [x] T015 [US3] Verify the `/api/settings/ai-work-order` GET and PUT endpoints both enforce admin-only access by checking `user_type == 'admin'` from the `users` table (already done in T005/T006 but confirm explicitly): non-admin returns 403, unauthenticated returns appropriate error
- [x] T016 [US3] Verify the `/api/autofill-work-order` endpoint enforces: (1) `user_email` parameter is required — return 401/403 if missing or user not found; (2) toggle check is first gate before rate limiting or AI calls; (3) rate limiting returns 429 with `Retry-After` info; (4) input validation (20–500 chars) returns 422 before any AI call
- [x] T017 [US3] Add audit logging to the autofill endpoint in `backend/routers/ai_assist.py`: log successful autofill calls to `user_activity_log` with `category='ai'`, `action='autofill_work_order'`, `target_id=None`, `detail` containing provider used and latency (no PII from the description); log failures similarly with `action='autofill_work_order_failed'`

**Checkpoint**: All three user stories are now independently functional. Server-side gates are verified.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Edge case handling, UX polish, and final validation

- [x] T018 Handle edge case in `add_work_order.dart`: when `_aiWorkOrderEnabled` fetch fails in `initState()`, default to `false` (hide AI entry) per FR-010 / edge case "Toggle state load fails at screen open"
- [x] T019 Handle edge case in `add_work_order.dart`: validate AI-returned dropdown values (priority, category/type, outcome, department) against known dropdown options; silently drop unknown values (do not set them in form fields)
- [x] T020 Handle edge case in `backend/routers/ai_assist.py`: when `app_settings.get_setting('ai_work_order_enabled')` returns `None` (key missing from table), treat as `'false'` (OFF) — this covers the "fresh install" and "migration not yet run" cases
- [x] T021 Add rate limiter cleanup to `backend/services/rate_limiter.py`: periodic pruning of old entries to prevent memory growth over time (e.g., `asyncio.Task` or a cleanup method called on each `check()` invocation to remove entries older than 24 hours for users with no recent activity)
- [x] T022 Run through `quickstart.md` validation scenarios end-to-end: toggle ON/OFF, autofill success, autofill refusal when disabled, non-admin toggle rejection, description length validation, rate limiting

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Phases 1+2 — this is the MVP
- **User Story 2 (Phase 4)**: Depends on Phases 1+2+3 (needs toggle to be in place so autofill can be conditionally shown)
- **User Story 3 (Phase 5)**: Depends on Phases 1+2 (server-side gates, can be developed in parallel with US1/US2 since it verifies existing endpoints)
- **Polish (Phase 6)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2. No dependency on other stories. **This is the MVP.**
- **US2 (P2)**: Depends on US1 being complete (needs the toggle infrastructure + conditional NlInputCard rendering to be in place)
- **US3 (P2)**: Can start after Phase 2. Verifies server-side enforcement. Independent of US1 frontend work but shares the autofill endpoint from US2.

### Within Each User Story

- Backend endpoints before frontend integration
- Service methods before screen modifications
- Core implementation before edge case handling

### Parallel Opportunities

- T003 and T004 can run in parallel (different frontend service files)
- T002 can run in parallel with T003/T004 (different backend file)
- T007 and T008 can run in parallel (different screen files)
- T011 can run in parallel with T010 (different files, different server/client)
- T015, T016, T017 can be done in parallel (different concerns within the same endpoint)

---

## Parallel Example: User Story 1

```text
# Phase 2 — run in parallel:
Task T002: Implement RateLimiter in backend/services/rate_limiter.py
Task T003: Add AI Work Order methods to ai_provider_service.dart
Task T004: Add autofillWorkOrder method to ai_assist_service.dart

# Phase 3 — run in parallel:
Task T005: Add GET /api/settings/ai-work-order endpoint
Task T006: Add PUT /api/settings/ai-work-order endpoint
# Then sequential:
Task T007: Add AI Features section to settings_page.dart
Task T008: Conditional NlInputCard in add_work_order.dart
Task T009: Skip AI fetch in edit mode
```

## Parallel Example: User Story 2

```text
# These can be developed in parallel:
Task T010: Implement autofill endpoint (backend)
Task T011: Implement AiOverwriteDialog widget (frontend)
# Then sequential:
Task T012: Integrate autofill + overwrite flow in add_work_order.dart
Task T013: Client-side description length validation
Task T014: Loading/cancel UX in the AI Assist surface
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (migration seed)
2. Complete Phase 2: Foundational (rate limiter + frontend service methods)
3. Complete Phase 3: User Story 1 (admin toggle + conditional NlInputCard)
4. **STOP and VALIDATE**: Toggle ON/OFF works, AI entry appears/disappears correctly
5. Deploy/demo if ready

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add User Story 1 → Admin toggle controls AI visibility → Deploy/Demo (MVP!)
3. Add User Story 2 → Full autofill flow with overwrite dialog → Deploy/Demo
4. Add User Story 3 → Server-side enforcement hardened → Deploy/Demo
5. Polish → Edge cases handled, production-ready

### Suggested MVP Scope

**User Story 1 only** — the admin toggle and conditional visibility of the AI Assist entry. This delivers immediate governance value without requiring the autofill backend.

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- No test tasks included (spec does not request automated tests)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- The existing `/api/ai/parse-work-order` endpoint is NOT modified — the new `/api/ai/autofill-work-order` is a separate endpoint
- The existing `NlInputCard` widget is NOT modified — only its visibility is controlled by the toggle