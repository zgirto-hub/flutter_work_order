# Implementation Plan: Export PDF Report for Closed Work Orders

**Branch**: `015-export-wo-pdf` | **Date**: 2026-04-04 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/015-export-wo-pdf/spec.md`

## Summary

Add a server-side PDF export endpoint that generates a professional "Work Order Completion Report" containing all WO fields, assigned technicians, embedded signature images, and organizational logos. The backend uses reportlab (matching the existing server-side PDF pattern from the constitution). The frontend adds an "Export PDF Report" button on closed WO detail screens and an icon on closed WO cards in the list view, both opening the existing PdfPreviewScreen with the streamed PDF bytes.

## Technical Context

**Language/Version**: Python 3 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client, reportlab (backend — NEW dependency); http, Flutter Material (frontend)
**Storage**: Supabase (PostgreSQL) — existing `work_orders`, `work_order_signatures`, `users`, `departments` tables; server filesystem for signature/logo PNGs
**Testing**: Manual testing (existing project pattern)
**Target Platform**: Web (PWA) + mobile (Flutter)
**Project Type**: Web application (backend API + Flutter frontend)
**Performance Goals**: PDF generation and preview in under 10 seconds
**Constraints**: Signature and logo files on server filesystem only (no CDN/cloud); single Linux server
**Scale/Scope**: Single-user export at a time; typical WO fits on 1 page

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Backend endpoint + frontend service + two UI integration points |
| II. Explicit Over Automatic | PASS | No implicit behavior; user explicitly triggers export |
| III. Role-Based Access Control | PASS | Export endpoint enforces same RBAC as GET /work-orders/{id} |
| IV. Server-First File Storage | PASS | Reads signatures/logos from `backend/uploaded_files/` and `backend/assets/` |
| V. Client-Side Computation | N/A | PDF must be server-side (signature files are on server) |
| VI. Audit Everything | PASS | Must log `pdf_exported` action to `user_activity_log` |
| VII. Simplicity & YAGNI | PASS | Single endpoint, no abstractions, reuses existing patterns |

No violations. No complexity tracking needed.

## Project Structure

### Documentation (this feature)

```text
specs/015-export-wo-pdf/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── api-endpoints.md
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── reports.py            # ADD: export_work_order_pdf endpoint
├── utils/
│   └── activity.py           # EXISTING: audit logging (no changes)
├── assets/                   # EXISTING: logo PNGs (read-only)
└── uploaded_files/            # EXISTING: signature PNGs (read-only)

frontend/
├── lib/
│   ├── services/
│   │   └── report_service.dart     # MODIFY: add exportWorkOrderPdf()
│   ├── screens/
│   │   ├── Work_Orders/
│   │   │   └── add_work_order.dart # MODIFY: add Export PDF button
│   │   └── reports/
│   │       └── pdf_preview_screen.dart  # EXISTING: reuse (no changes)
│   └── widgets/
│       └── work_order_card.dart    # MODIFY: add Export PDF icon
└── lib/config.dart                 # EXISTING: AppConfig.baseUrl (no changes)
```

**Structure Decision**: Follows existing backend/frontend split. No new files created — only modifications to existing files plus the new endpoint function in reports.py. reportlab added to requirements.txt.
