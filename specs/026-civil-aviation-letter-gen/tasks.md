# Tasks: Civil Aviation Letter Generator

**Input**: Design documents from `/specs/026-civil-aviation-letter-gen/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Target Audience**: These tasks are written for an LLM code agent to implement precisely. Each task contains exact file paths, data structures, and implementation details. Follow the instructions literally — do not add features, abstractions, or patterns beyond what is described.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Backend**: `backend/` (Python/FastAPI)
- **Frontend**: `frontend/lib/` (Dart/Flutter)
- **Migrations**: `supabase/migrations/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Database migration, font assets, and shared model/service files

- [x] T001 Create Supabase migration file `supabase/migrations/20260406_generated_letters.sql` with the following SQL:
- [x] T002 Download NotoSansArabic-Regular.ttf and NotoSansArabic-Bold.ttf from Google Fonts (Noto Sans Arabic) and place them in `backend/assets/`. These files are required for Arabic PDF rendering.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Backend letter PDF builder function and Flutter model/service that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete.

- [x] T003 Create the Flutter model file `frontend/lib/models/generated_letter.dart`
- [x] T004 Create the Flutter service file `frontend/lib/services/letter_service.dart`
- [x] T005 Create the backend router file `backend/routers/letters.py`
- [x] T006 Register the letters router in `backend/main.py`

**Checkpoint**: Foundation ready — backend can generate PDFs, frontend can call APIs. User story implementation can now begin.

---

## Phase 3: User Story 1 — Fill and Generate Official Letter (Priority: P1) MVP

**Goal**: User fills an Arabic RTL form, previews the letter, and generates a single-page DGCA-formatted PDF.

**Independent Test**: Fill all form fields with Arabic text, upload a signature image, tap Preview (verify layout), tap Generate PDF (verify PDF downloads with correct header/body/footer/signature).

### Implementation for User Story 1

- [x] T007 [US1] Create the main screen file `frontend/lib/screens/letters/letter_generator_screen.dart`
- [x] T008 [US1] Create the form tab file `frontend/lib/screens/letters/letter_form_tab.dart`
- [x] T009 [US1] Wire the letter generator screen into the app's navigation

**Checkpoint**: At this point, User Story 1 should be fully functional — users can fill the form, preview, and generate a PDF. The letter record is saved to Supabase.

---

## Phase 4: User Story 2 — Preview Letter Before Generating (Priority: P2)

**Goal**: Mandatory preview step before PDF export.

**Independent Test**: Fill form, attempt to tap "Generate PDF" without previewing first (should be disabled), tap Preview (verify layout), then Generate PDF should become enabled.

### Implementation for User Story 2

- [x] T010 [US2] This story's core functionality is already built into T008 (the `_hasPreviewedOnce` gate and the `_showPreview()` dialog). Validate and refine:
- [x] T011 [P] [US3] Create the history tab file `frontend/lib/screens/letters/letter_history_tab.dart`
- [x] T012 [US3] Update the `GET /api/letters` endpoint in `backend/routers/letters.py`
- [x] T013 [US3] Update `frontend/lib/models/payment_certificate.dart` to add an optional `String? letterId` field

**Checkpoint**: All user stories should now be independently functional — form, preview, generate, history, regenerate, payment certificate linkage.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final integration, navigation, and audit logging

- [x] T014 [P] Add activity logging for letter operations
- [x] T015 [P] Update `CLAUDE.md` with the new feature entry
- [x] T016 Run the quickstart checklist

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (migration must be applied, fonts available)
- **User Story 1 (Phase 3)**: Depends on Phase 2 (model, service, router must exist)
- **User Story 2 (Phase 4)**: Depends on Phase 3 (preview is part of the form screen built in US1)
- **User Story 3 (Phase 5)**: Depends on Phase 2 (needs service and router), can run parallel with US1/US2
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Foundational — no dependency on other stories
- **User Story 2 (P2)**: Integrated into US1 screen — implemented as refinement of T008
- **User Story 3 (P3)**: Depends on Foundational — can start after Phase 2, independent of US1/US2 (it only needs the backend API and model)

### Within Each User Story

- Models before services (T003 → T004)
- Backend router before frontend service wiring (T005 → T004 uses it)
- Form screen (T008) before navigation wiring (T009)

### Parallel Opportunities

- T003 and T005 can run in parallel (different languages, different files)
- T011 (history tab) can run in parallel with T008 (form tab) — different files
- T014 and T015 can run in parallel (different files)

---

## Parallel Example: Foundational Phase

```
# These can run at the same time:
Task T003: "Create GeneratedLetter model in frontend/lib/models/generated_letter.dart"
Task T005: "Create letters router in backend/routers/letters.py"

# Then sequentially:
Task T004: "Create LetterService in frontend/lib/services/letter_service.dart" (needs T003)
Task T006: "Register router in backend/main.py" (needs T005)
```

## Parallel Example: User Story Phases

```
# After Foundational is done, these can run in parallel:
Task T008: "Create letter form tab" (US1)
Task T011: "Create letter history tab" (US3)

# Then:
Task T007: "Create main screen with tab switching" (US1, needs T008 and T011)
Task T009: "Wire into navigation" (US1, needs T007)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (migration + fonts)
2. Complete Phase 2: Foundational (model, service, router)
3. Complete Phase 3: User Story 1 (form, preview, generate)
4. **STOP and VALIDATE**: Test letter generation end-to-end
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test → Deploy/Demo (MVP!)
3. Add User Story 2 → Refine preview gating → Deploy/Demo
4. Add User Story 3 → Add history + payment cert linkage → Deploy/Demo
5. Polish → Audit logging, docs update, quickstart validation

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story is independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- The tasks are written for precise LLM implementation — follow file paths and data structures exactly as described
- Use existing project patterns (service pattern from `payment_certificate_service.dart`, tab pattern from `add_work_order.dart`, router pattern from `payment_certificates.py`)
