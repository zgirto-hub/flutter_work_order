# Implementation Plan: Civil Aviation Letter Generator

**Branch**: `026-civil-aviation-letter-gen` | **Date**: 2026-04-06 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/026-civil-aviation-letter-gen/spec.md`

## Summary

Build a full-stack feature for generating official Kuwait DGCA Arabic RTL cover letters. Users fill a form (reference, date, recipient, subject, body, signer, optional signature image), preview the letter, then generate a single-page PDF server-side via ReportLab. Letter field data (including signature as base64) is persisted to Supabase — no PDF file is stored. Letters serve as parent documents for payment certificates (one-to-many). A history tab within the same screen allows browsing and regenerating past letters.

## Technical Context

**Language/Version**: Python 3 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI, ReportLab, arabic_reshaper, python-bidi (backend); http, supabase_flutter, file_picker, Flutter Material (frontend)  
**Storage**: Supabase (PostgreSQL) — new `generated_letters` table; `payment_certificates` table gains `letter_id` FK  
**Testing**: Manual integration testing (project pattern)  
**Target Platform**: Flutter Web (PWA), FastAPI on Linux  
**Project Type**: Web application (frontend + backend)  
**Performance Goals**: PDF generation < 10 seconds  
**Constraints**: Single-page letter only; RTL Arabic throughout; Cairo/NotoSansArabic font for PDF  
**Scale/Scope**: Internal DGCA staff; low volume (tens of letters per day)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Feature spans: backend router, Supabase migration, Flutter model, service, screen, navigation wiring |
| II. Explicit Over Automatic | PASS | No auto-assignment; user explicitly fills and generates; no implicit state transitions |
| III. Role-Based Access Control | PASS | Letter generation available to all authenticated users (no special role gate needed per spec assumption); existing auth enforced |
| IV. Server-First File Storage | N/A | No file storage — PDF generated on-demand, only field data persisted to Supabase. Signature stored as base64 in DB, not filesystem |
| V. Client-Side Computation Where Possible | PASS | History list fetched once and filtered client-side; no per-view API calls beyond initial load |
| VI. Audit Everything | PASS | Letter creation/regeneration will log to `user_activity_log` with category `letter` |
| VII. Simplicity & YAGNI | PASS | Minimal feature set: form → preview → generate → history. No configurability beyond required fields |

All gates pass. No violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/026-civil-aviation-letter-gen/
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
│   └── letters.py                  # NEW — FastAPI router for letter generation
├── assets/
│   ├── NotoSansArabic-Regular.ttf  # NEW — Arabic font for PDF
│   ├── NotoSansArabic-Bold.ttf     # NEW — Arabic bold font for PDF
│   ├── logo_civilaviation.png      # EXISTING
│   ├── logo_emblem.png             # EXISTING
│   └── logo_newkuwait.png          # EXISTING
└── main.py                         # MODIFIED — register letters router

frontend/
├── lib/
│   ├── models/
│   │   └── generated_letter.dart   # NEW — Letter model
│   ├── services/
│   │   └── letter_service.dart     # NEW — API service for letters
│   └── screens/
│       └── letters/
│           ├── letter_generator_screen.dart  # NEW — Main screen with tabs
│           ├── letter_form_tab.dart          # NEW — Form tab
│           └── letter_history_tab.dart       # NEW — History tab
└─�� pubspec.yaml                    # UNCHANGED (file_picker already present)

supabase/
└── migrations/
    └── 20260406_generated_letters.sql  # NEW — Table + payment_certificates FK
```

**Structure Decision**: Follows existing project convention — new router in `backend/routers/`, new screen folder in `frontend/lib/screens/`, model + service in their respective directories. Tab components separated into individual files matching the `add_work_order.dart` pattern.

## Complexity Tracking

> No violations — table empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
