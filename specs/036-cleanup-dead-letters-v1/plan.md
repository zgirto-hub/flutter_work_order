# Implementation Plan: Cleanup Dead Letters V1 Code

**Branch**: `036-cleanup-dead-letters-v1` | **Date**: 2026-04-11 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/036-cleanup-dead-letters-v1/spec.md`

## Summary

Remove all dead code from the old letters v1 feature — the entire backend router file, its registration in main.py, and 5 dead v1 service methods in the frontend. Dependencies (`reportlab`, `arabic-reshaper`, `python-bidi`) are shared with `reports.py` and must NOT be removed.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI (backend), Flutter Material (frontend) — no new dependencies  
**Storage**: N/A — no data model changes  
**Testing**: Manual verification (backend starts, frontend compiles, v2 endpoints respond)  
**Target Platform**: Linux server (backend), Web PWA (frontend)  
**Project Type**: Web application (full-stack)  
**Performance Goals**: N/A — deletion only  
**Constraints**: Must not break v2 letter features or reports feature  
**Scale/Scope**: 3 files modified, 1 file deleted, ~400 lines removed

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | This is a cleanup, not a new feature. No incomplete layers. |
| II. Explicit Over Automatic | N/A | No state transitions or assignments involved. |
| III. Role-Based Access Control | N/A | No new endpoints or screens. |
| IV. Server-First File Storage | N/A | No file storage changes. |
| V. Client-Side Computation | N/A | No computation changes. |
| VI. Audit Everything | N/A | No new user actions introduced. Removal of dead endpoints doesn't require audit logging. |
| VII. Simplicity & YAGNI | PASS | Removing dead code aligns with Simplicity mandate. Letters v1 is fully superseded with zero callers — not a case where "document as unused" applies. See research.md R5. |

**Post-design re-check**: All gates pass. No violations.

## Project Structure

### Documentation (this feature)

```text
specs/036-cleanup-dead-letters-v1/
├── plan.md              # This file
├── research.md          # Phase 0 output — dependency analysis
├── data-model.md        # Phase 1 output — no changes needed
├── quickstart.md        # Phase 1 output — implementation guide
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── main.py                          # EDIT: remove letters v1 import + router registration
├── routers/
│   ├── letters.py                   # DELETE: entire file
│   └── letters_v2.py               # UNCHANGED
└── requirements.txt                 # UNCHANGED (shared deps with reports.py)

frontend/
└── lib/
    └── services/
        └── letter_service.dart      # EDIT: remove 5 dead v1 methods
```

**Structure Decision**: Existing web application structure. No new files or directories. Net reduction of 1 file and ~400 lines.

## Complexity Tracking

No constitution violations. Table not needed.
