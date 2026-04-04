# Implementation Plan: Supervisor & Superintendent Signature Approval Chain

**Branch**: `016-signature-approval-chain` | **Date**: 2026-04-04 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/016-signature-approval-chain/spec.md`

## Summary

Replace the existing two-step admin-only signature workflow (technician signs, admin approves) with an extensible multi-level approval chain: Technician signs -> Supervisor approves (department-scoped) -> Superintendent approves (all departments) -> Completed. Admin is excluded from the chain but retains read-only audit access. Additionally, work order technician assignment changes from multi-technician to single-technician, and a new "Pending Approvals" screen is added for approvers.

## Technical Context

**Language/Version**: Python 3 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client (backend); http, supabase_flutter, Flutter Material (frontend)
**Storage**: Supabase (PostgreSQL) — `users`, `work_orders`, `work_order_signatures`, `work_order_assignments`, `technician_departments` tables
**Testing**: Manual testing against production Supabase instance
**Target Platform**: Web (PWA) primarily, mobile secondary
**Project Type**: Full-stack web application (FastAPI + Flutter)
**Performance Goals**: Standard web app expectations — approval actions complete within 2 seconds
**Constraints**: Single Linux server, no CDN, server-first file storage, offline not required for approvals
**Scale/Scope**: ~50 users, ~1000 WOs, 3-5 departments

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Feature spans all layers: migration, backend routers, frontend models/services/screens, navigation, AGENT.md |
| II. Explicit Over Automatic | PASS | All state transitions are explicit via `signature_status` field. No implicit auto-assignment. Approval level skip is logged explicitly. |
| III. Role-Based Access Control | PASS | Extended with supervisor/superintendent. Admin excluded from chain via 403. Authorization matrix enforced backend-side. Constitution says 3 roles — we are adding approval flags (not new user_types), which is additive. |
| IV. Server-First File Storage | PASS | Signature images continue to use `backend/uploaded_files/`. No change to storage pattern. |
| V. Client-Side Computation Where Possible | PASS | Pending approvals screen fetches filtered data from backend (filter requires DB join with department scope). Badge status comes from bulk API. |
| VI. Audit Everything | PASS | All chain transitions logged to `user_activity_log`. Rejected signatures preserved. |
| VII. Simplicity & YAGNI | PASS | Approval chain uses simple integer level + status string. No over-abstraction. Future Manager level documented but not built. |

**Note on Principle III**: Constitution defines three roles (`reporter`, `technician`, `admin`). This feature does NOT add new `user_type` values. Instead, it adds boolean flags (`is_supervisor`, `is_superintendent`) and an `approval_level` integer as additive columns. This is consistent with the constitution — `user_type` remains the identity role while approval roles are operational flags.

## Project Structure

### Documentation (this feature)

```text
specs/016-signature-approval-chain/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   ├── signatures.py        # MODIFY — approval chain logic, level resolver, admin block
│   ├── users.py             # MODIFY — approval-role endpoint, list filters
│   └── work_orders.py       # MODIFY — signature_status in responses, single-tech assignment
├── utils/
│   └── notification_service.py  # MODIFY — level-based routing
└── uploaded_files/          # No change (signature PNGs stored here)

frontend/
├── lib/
│   ├── models/
│   │   ├── user.dart                    # MODIFY — add approval fields
│   │   ├── work_order.dart              # MODIFY — add signatureStatus field
│   │   ├── technician_assignment.dart   # No change
│   │   └── nav_screen.dart              # MODIFY — add approvals nav item
│   ├── services/
│   │   ├── user_service.dart            # MODIFY — approval role CRUD
│   │   └── work_order_service.dart      # MODIFY — single-tech assignment
│   ├── screens/
│   │   ├── admin/
│   │   │   └── user_management_screen.dart  # MODIFY — approval role UI
│   │   ├── Work_Orders/
│   │   │   ├── add_work_order.dart          # MODIFY — signature section, single-tech
│   │   │   └── work_order_home.dart         # MODIFY — signature badges
│   │   ├── approvals/
│   │   │   └── pending_approvals_screen.dart # NEW — dedicated approval queue
│   │   └── main_screen.dart                 # MODIFY — conditional nav item
│   └── config.dart          # No change

supabase/
└── migrations/
    └── 20260404_supervisor_superintendent.sql  # NEW — schema changes
```

**Structure Decision**: Existing `backend/` + `frontend/` web application structure. New screen added under `frontend/lib/screens/approvals/`. No new backend routers — existing `signatures.py` and `users.py` are extended.

## Complexity Tracking

> No constitution violations — table left empty.
