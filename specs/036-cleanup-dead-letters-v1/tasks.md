# Tasks: Cleanup Dead Letters V1 Code

**Input**: Design documents from `/specs/036-cleanup-dead-letters-v1/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, quickstart.md

**Tests**: No automated tests — verification is manual (backend starts, frontend compiles).

**Organization**: Tasks are grouped by user story. US1 (backend) and US2 (frontend) can be done in parallel since they touch different codebases.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Path Conventions

- **Backend**: `backend/` at repository root
- **Frontend**: `frontend/lib/` at repository root

---

## Phase 1: User Story 1 - Remove Old Letters V1 Backend Code (Priority: P1) 🎯 MVP

**Goal**: Delete the entire `backend/routers/letters.py` file and remove its import/registration from `backend/main.py`, so no v1 endpoints are exposed.

**Independent Test**: Start the backend server — it must boot without import errors. Requests to any v1 endpoint (`POST /api/letters/generate`, `GET /api/letters`, `PUT /api/letters/{id}`, `POST /api/letters/{id}/regenerate`, `PATCH /api/payment-certificates/{id}/link-letter`) must return 404. All v2 endpoints (`/api/letters-v2/*`) must still work.

### Implementation for User Story 1

- [x] T001 [US1] Remove the `letters` import from the import block in `backend/main.py` (line 28 — remove only the `letters,` line, keep `letters_v2,`)
- [x] T002 [US1] Remove the `app.include_router(letters.router, prefix="/api")` line from `backend/main.py` (line 88 — keep the `letters_v2.router` line on line 89)
- [x] T003 [US1] Delete the entire file `backend/routers/letters.py`

**⚠️ CRITICAL — DO NOT modify these files:**
- `backend/requirements.txt` — `reportlab`, `arabic-reshaper`, `python-bidi` are shared with `backend/routers/reports.py`
- `backend/routers/letters_v2.py` — this is the active v2 router, do not touch
- Any database tables — `generated_letters` table is shared between v1 and v2

**Checkpoint**: Backend starts without errors. V1 endpoints return 404. V2 endpoints work normally.

---

## Phase 2: User Story 2 - Remove Dead V1 Service Methods from Frontend (Priority: P2)

**Goal**: Remove the 5 dead v1 methods from `frontend/lib/services/letter_service.dart` that call the now-deleted v1 backend endpoints.

**Independent Test**: Run `flutter build web` — compilation must succeed with zero errors. All letter v2 features (create, edit, regenerate, export, delete) must still work in the app.

### Implementation for User Story 2

- [x] T004 [US2] Remove the `fetchAll()` method from `frontend/lib/services/letter_service.dart` (lines 11-23 — the method that calls `GET /letters` without `-v2`)
- [x] T005 [US2] Remove the `generate()` method from `frontend/lib/services/letter_service.dart` (lines 25-39 — the method that calls `POST /letters/generate` without `-v2`)
- [x] T006 [US2] Remove the `regenerate()` method from `frontend/lib/services/letter_service.dart` (lines 41-48 — the method that calls `POST /letters/$letterId/regenerate` without `-v2`, NOT `regenerateV2()` on lines 50-58)
- [x] T007 [US2] Remove the `update()` method from `frontend/lib/services/letter_service.dart` (lines 127-140 — the method that calls `PUT /letters/$letterId` without `-v2`, NOT `updateV2()` on lines 143-168)
- [x] T008 [US2] Remove the `linkPaymentCertificate()` method from `frontend/lib/services/letter_service.dart` (lines 178-189 — the method that calls `PATCH /payment-certificates/$certId/link-letter`)

**⚠️ CRITICAL — DO NOT remove these v2 methods (they are actively used):**
- `fetchAllV2()` (lines 60-72)
- `fetchOneV2()` (lines 74-81)
- `generateV2()` (lines 84-109)
- `uploadImage()` (lines 111-124)
- `updateV2()` (lines 143-168)
- `delete()` (lines 170-176)
- `exportLetterWithAttachments()` (lines 191-217)
- `regenerateV2()` (lines 50-58)
- `CertificatesAlreadyLinkedException` class (lines 220-226)

**Checkpoint**: `flutter build web` succeeds. All v2 letter features work in the app.

---

## Phase 3: Verification & Polish

**Purpose**: Final verification that all cleanup is complete and nothing is broken.

- [x] T009 Verify no remaining references to old v1 letter endpoints exist in the codebase — search all `.py` and `.dart` files for `/letters/generate`, `/letters?`, `letters/$letterId/regenerate` (without `-v2` prefix), and `/link-letter`
- [x] T010 Verify `backend/requirements.txt` was NOT modified (reportlab, arabic-reshaper, python-bidi must still be present for reports.py)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (US1 — Backend)**: No dependencies — can start immediately
- **Phase 2 (US2 — Frontend)**: No dependencies on Phase 1 — can run in **parallel** with Phase 1 (different codebase)
- **Phase 3 (Verification)**: Depends on both Phase 1 and Phase 2 completion

### Within Each Phase

- **Phase 1**: T001 and T002 must complete before T003 (edit main.py before deleting the file it imports)
- **Phase 2**: T004-T008 all edit the same file (`letter_service.dart`), so they must be done **sequentially** in order from top to bottom to maintain correct line numbers. Alternatively, do them all in a single edit pass.

### Parallel Opportunities

- Phase 1 (backend) and Phase 2 (frontend) can run fully in parallel since they touch completely different files

---

## Parallel Example

```text
# These two phases can run simultaneously:
Agent A: T001 → T002 → T003 (backend cleanup)
Agent B: T004 → T005 → T006 → T007 → T008 (frontend cleanup)

# Then both verify:
T009 → T010
```

---

## Implementation Strategy

### Recommended Approach (Single Agent)

1. Complete Phase 1 (T001-T003) — backend cleanup
2. Complete Phase 2 (T004-T008) — frontend cleanup
3. Complete Phase 3 (T009-T010) — verification
4. **DONE** — commit all changes

### Practical Tip for T004-T008

Since all 5 methods are in the same file, it's most efficient to edit `letter_service.dart` once, removing all 5 dead methods in a single pass rather than 5 separate edits. The task IDs are listed separately for traceability, but the implementation can batch them.

---

## Notes

- This is a **deletion-only** cleanup — no new code is written
- Total lines removed: ~400 (359 from letters.py + ~40 from letter_service.dart methods)
- Net file change: -1 file deleted, 2 files edited
- The `generated_letters` database table is untouched — old records remain accessible via v2
- Commit after all changes with a message like: "chore: remove dead letters v1 code (superseded by v2)"
