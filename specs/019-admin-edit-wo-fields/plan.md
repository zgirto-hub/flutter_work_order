# Implementation Plan: Admin Edit WO Metadata Fields

**Branch**: `019-admin-edit-wo-fields` | **Date**: 2026-04-05 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/019-admin-edit-wo-fields/spec.md`

## Summary

Allow admin users to edit three normally-immutable work order fields — **Created By**, **Created At**, and **Closed At** — from the existing work order edit screen. The backend receives new optional fields in the update payload, validates them (admin-only, date constraints), persists the changes, and logs the activity. The frontend conditionally renders editable controls for these fields when the user is an admin.

## Technical Context

**Language/Version**: Python 3 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI, Supabase Python client (backend); http, Flutter Material, supabase_flutter (frontend)  
**Storage**: Supabase (PostgreSQL) — existing `work_orders`, `users` tables  
**Testing**: Manual testing (existing project pattern)  
**Target Platform**: Web (Flutter PWA), Linux server (FastAPI)  
**Project Type**: Web application (frontend + backend)  
**Performance Goals**: Standard web app — field updates complete in under 2 seconds  
**Constraints**: Admin-only access enforced at both backend and frontend layers  
**Scale/Scope**: ~3 new optional fields in update payload, ~1 new user-picker widget, modifications to 4-5 existing files

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Feature spans backend endpoint modification, frontend screen update, frontend service update. No new DB tables needed. |
| II. Explicit Over Automatic | PASS | All field changes are explicit admin actions. No auto-inference. |
| III. Role-Based Access Control | PASS | Backend enforces admin-only for these fields. Frontend hides edit controls from non-admins. |
| IV. Server-First File Storage | N/A | No file storage involved. |
| V. Client-Side Computation | N/A | No client-side computation changes. |
| VI. Audit Everything | PASS | Existing `log_activity` call in update endpoint covers updates. Enhanced detail param for metadata changes. |
| VII. Simplicity & YAGNI | PASS | Extends existing update endpoint and edit screen. No new abstractions or tables. |

## Project Structure

### Documentation (this feature)

```text
specs/019-admin-edit-wo-fields/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── work_orders.py       # MODIFY: Add optional fields to UpdateWorkOrderBody, admin validation
└── utils/
    └── activity.py           # NO CHANGE: Existing log_activity covers updates

frontend/
├── lib/
│   ├── screens/
│   │   └── Work_Orders/
│   │       └── add_work_order.dart  # MODIFY: Add admin-only editable fields
│   ├── services/
│   │   └── work_order_service.dart  # MODIFY: Add new fields to updateWorkOrder payload
│   └── widgets/
│       └── user_selector.dart       # NEW: Searchable user picker
```

**Structure Decision**: Extends existing web application structure. One new widget, rest are modifications to existing files.

## Complexity Tracking

No constitution violations. No complexity justification needed.
