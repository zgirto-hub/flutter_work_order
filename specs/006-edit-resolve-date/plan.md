# Implementation Plan: Edit Resolve Date

**Branch**: `006-edit-resolve-date` | **Date**: 2026-04-02 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/006-edit-resolve-date/spec.md`

## Summary

Allow users to edit the resolve date of already-resolved system status issues and optionally set a custom resolve date during resolution. This ensures uptime reports accurately reflect actual resolution timelines. Changes span backend (model + endpoints) and frontend (service + UI sheets).

## Technical Context

**Language/Version**: Python 3 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client (backend); http, Flutter Material (frontend)
**Storage**: Supabase (PostgreSQL) — `system_status_reports` table
**Testing**: Manual verification via UI and API
**Target Platform**: Web (Flutter PWA) + Linux server (FastAPI)
**Project Type**: Full-stack web application (mobile-friendly PWA + REST API)
**Performance Goals**: N/A (low-traffic admin feature)
**Constraints**: No database schema changes needed (`resolved_at` column already exists as a nullable timestamp)
**Scale/Scope**: Single table, 4 files modified

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Changes span backend endpoint, frontend service, and frontend screen |
| II. Explicit Over Automatic | PASS | Resolve date becomes explicitly user-settable rather than auto-generated |
| III. Role-Based Access Control | PASS | No new permissions needed; same users who can resolve can edit resolve date |
| IV. Server-First File Storage | N/A | No file storage involved |
| V. Client-Side Computation | N/A | No client-side computation changes |
| VI. Audit Everything | NOTE | `system_status.py` currently has NO audit logging. Adding it is out of scope for this feature but flagged for future work |
| VII. Simplicity & YAGNI | PASS | Minimal changes to existing patterns; no new abstractions |

## Project Structure

### Documentation (this feature)

```text
specs/006-edit-resolve-date/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── system_status.py        # Modify: UpdateIssueBody, ResolveIssueBody, endpoints

frontend/
├── lib/
│   ├── services/
│   │   └── system_status_service.dart   # Modify: resolveIssue(), updateIssue()
│   └── screens/
│       └── system_status_screen.dart    # Modify: _showResolveSheet(), _showEditIssueSheet()
```

**Structure Decision**: Existing full-stack structure (backend/ + frontend/) — no new files needed, only modifications to 3 existing files.
