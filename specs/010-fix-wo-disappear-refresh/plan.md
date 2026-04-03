# Implementation Plan: Fix Work Order Disappears After Refresh

**Branch**: `010-fix-wo-disappear-refresh` | **Date**: 2026-04-03 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/010-fix-wo-disappear-refresh/spec.md`

## Summary

Work orders created by reporters disappear on refresh because the backend's `created_by` identity resolution can fail silently, storing a raw auth UUID instead of the database user ID. The list endpoint then filters by database user ID, excluding mismatched records. A secondary bug — frontend sends `department` but backend expects `department_id` — causes department filtering to silently not apply. This plan fixes both issues and includes a one-time data migration to repair existing broken records.

## Technical Context

**Language/Version**: Python 3 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI (backend), Supabase Python client, Flutter Material, http package  
**Storage**: Supabase (PostgreSQL) — `work_orders`, `users` tables  
**Testing**: Manual testing (create work order as reporter, refresh, verify persistence)  
**Target Platform**: Web (Flutter PWA) + Linux server (FastAPI behind Nginx)  
**Project Type**: Web application (Flutter frontend + FastAPI backend)  
**Performance Goals**: N/A (bug fix, no new performance requirements)  
**Constraints**: Must not break existing work orders; data migration must be safe and idempotent  
**Scale/Scope**: Affects all reporters creating work orders; migration touches existing `work_orders` table rows

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Fix spans backend (router fix + migration) and frontend (parameter fix). No new model/screen needed — this is a bug fix on existing layers. |
| II. Explicit Over Automatic | PASS | Identity resolution will explicitly fail with an error rather than silently storing a wrong value. |
| III. Role-Based Access Control | PASS | Reporter filtering logic preserved and fixed. No role changes. |
| IV. Server-First File Storage | N/A | No file storage changes. |
| V. Client-Side Computation Where Possible | PASS | Frontend local list insertion preserved. |
| VI. Audit Everything | PASS | Work order creation already logged. Data migration should log repaired records. |
| VII. Simplicity & YAGNI | PASS | Minimal targeted fixes. No new abstractions. |

**Technology Constraints**: All satisfied. Backend is FastAPI/Python, frontend is Flutter/Dart, database is Supabase PostgreSQL.

**Development Workflow**: Migration file required in `supabase/migrations/`. No new screens/models/services needed.

## Project Structure

### Documentation (this feature)

```text
specs/010-fix-wo-disappear-refresh/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── work_orders.py          # Fix: created_by resolution + error on failure
└── (no new files)

frontend/
├── lib/
│   ├── services/
│   │   └── work_order_service.dart  # Fix: department → department_id parameter
│   └── screens/
│       └── Work_Orders/
│           └── work_order_home.dart # No changes needed (uses service correctly)

supabase/
└── migrations/
    └── 20260403_fix_created_by_auth_uuid.sql  # One-time data repair migration
```

**Structure Decision**: Existing web application structure (backend/ + frontend/ + supabase/). No new directories needed.

## Complexity Tracking

> No constitution violations. No complexity justifications needed.
