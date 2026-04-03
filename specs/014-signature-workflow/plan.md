# Implementation Plan: Signature Workflow

**Branch**: `014-signature-workflow` | **Date**: 2026-04-03 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/014-signature-workflow/spec.md`

## Summary

Replace base64 signature storage with file-based storage, add saved signature management in Settings, add bulk signature status endpoint (fix N+1), add authorization enforcement, add activity logging for all signature events, fix the `_approveAndSign` sequencing bug, and add signature status badges to the work order list. This builds on existing signature infrastructure in `backend/routers/signatures.py`, `frontend/lib/services/signature_service.dart`, and `frontend/lib/widgets/signature_canvas.dart`.

## Technical Context

**Language/Version**: Python 3 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client (backend); http, signature, supabase_flutter, file_picker (frontend)
**Storage**: Supabase (PostgreSQL) for metadata; `backend/uploaded_files/` for signature PNG files served at `/files/<filename>`
**Testing**: Manual testing (existing project pattern — no automated test framework in use)
**Target Platform**: Web (Flutter PWA) + mobile
**Project Type**: Web application (FastAPI backend + Flutter frontend)
**Performance Goals**: Single bulk request for WO list signature status; sub-second response for all signature endpoints
**Constraints**: Constitution Principle IV — all files on server filesystem, no cloud storage. Principle VI — all actions must be logged.
**Scale/Scope**: ~50-100 concurrent users, ~1000 work orders

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Feature spans: migration, backend endpoints, Flutter model/service/screens, navigation (Settings integration) |
| II. Explicit Over Automatic | PASS | Signature submission is explicit user action; admin countersignature is auto-approved (explicit design decision per clarification) |
| III. Role-Based Access Control | PASS | Backend enforces: technician must be assigned, admin-only approve/reject, reporter excluded from signature UI |
| IV. Server-First File Storage | PASS | All signature PNGs stored in `uploaded_files/`, served via `/files/`. No cloud storage. |
| V. Client-Side Computation | PASS | Bulk endpoint returns status map; client renders badges from cached data. No per-view API calls for individual WOs. |
| VI. Audit Everything | PASS | All 4 signature actions logged via `log_activity()`: submitted, approved, rejected, saved_signature_updated |
| VII. Simplicity & YAGNI | PASS | Modifies existing code rather than building new abstractions. No new service layers or patterns introduced. |

**Post-Phase 1 Re-check**: All gates still pass. Data model adds two columns to existing tables. API contracts modify 3 existing endpoints and add 4 new ones — all following established FastAPI router patterns.

## Project Structure

### Documentation (this feature)

```text
specs/014-signature-workflow/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 research findings
├── data-model.md        # Phase 1 data model
├── quickstart.md        # Phase 1 quickstart guide
├── contracts/           # Phase 1 API contracts
│   └── api-endpoints.md
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── signatures.py          # MODIFY: file storage, bulk endpoint, user sig endpoints, activity log
├── utils/
│   └── activity.py            # EXISTING: log_activity() — used as-is
└── uploaded_files/             # RUNTIME: sig_*.png and usersig_*.png files

frontend/lib/
├── models/
│   └── work_order_signature.dart  # MODIFY: signatureData → signaturePath
├── services/
│   └── signature_service.dart     # MODIFY: add bulk, user sig methods
├── screens/
│   ├── settings_page.dart         # MODIFY: add "My Signature" section
│   └── Work_Orders/
│       ├── add_work_order.dart    # MODIFY: saved sig flow, fix _approveAndSign
│       └── work_order_home.dart   # MODIFY: bulk status fetch + badges
└── widgets/
    └── signature_canvas.dart      # EXISTING: no changes needed

supabase/migrations/
└── YYYYMMDD_signature_file_storage.sql  # NEW: ALTER tables
```

**Structure Decision**: Web application (Option 2) — existing `backend/` + `frontend/` structure. No new directories needed; all changes are modifications to existing files plus one new migration.

## Complexity Tracking

No constitution violations — table not needed.
