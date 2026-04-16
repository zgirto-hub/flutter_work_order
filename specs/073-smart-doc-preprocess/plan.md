# Implementation Plan: Smart Document Preprocessing

**Branch**: `073-smart-doc-preprocess` | **Date**: 2026-04-16 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/073-smart-doc-preprocess/spec.md`

## Summary

Add an AI preprocessing step to the document upload pipeline that transforms each page's raw extracted text into clean, structured Markdown before chunking and embedding. This fixes the search quality issue where terse slide bullet points (common in vendor training decks) produce poor embeddings and fail to surface in vector search. The preprocessing uses Gemini Flash as a dedicated fast/cheap provider, operates per-page with graceful fallback to raw text on any failure, and applies to both the knowledge documents and legacy manuals pipelines.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI, Supabase Python client, google-generativeai (existing), httpx (backend); http, Flutter Material (frontend)  
**Storage**: Supabase (PostgreSQL) with pgvector — `knowledge_documents`, `document_chunks`, `manual_chunks`, `app_settings` tables  
**Testing**: Manual integration testing (upload + search verification)  
**Target Platform**: Linux server (backend), Flutter web PWA (frontend)  
**Project Type**: Web application (full-stack)  
**Performance Goals**: Preprocessing adds ≤ 3x to current document processing time (SC-003)  
**Constraints**: Sequential page processing to respect Gemini Flash rate limits; 30s timeout per page  
**Scale/Scope**: A few documents per day, typical 10-100 pages each

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Backend service + migration + frontend status display. All layers covered. |
| II. Explicit Over Automatic | PASS | Preprocessing is toggle-controlled (app_settings). Fallback behavior is explicit and documented. No silent behavior changes. |
| III. Role-Based Access Control | PASS | Settings toggle is admin-only. Document upload is already role-gated. |
| IV. Server-First File Storage | N/A | No new file storage. Preprocessing operates on in-memory text. |
| V. Client-Side Computation | N/A | Preprocessing is correctly server-side (AI API calls cannot run client-side). |
| VI. Audit Everything | PASS | Preprocessing outcomes logged via existing activity logging. Status transitions recorded in document status field. |
| VII. Simplicity & YAGNI | PASS | Single service function, sequential processing, no abstraction layers. Raw text retention is justified by clarification (re-processing need). |

**Gate result**: PASS — no violations.

## Project Structure

### Documentation (this feature)

```text
specs/073-smart-doc-preprocess/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: research decisions
├── data-model.md        # Phase 1: schema changes
├── quickstart.md        # Phase 1: verification guide
├── contracts/           # Phase 1: API contracts
│   └── api-contracts.md
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── services/
│   ├── document_preprocessor.py    # NEW: core preprocessing service
│   ├── document_service.py         # MODIFIED: insert preprocessing step
│   └── ai_providers/
│       └── gemini.py               # EXISTING: Gemini SDK (reused directly)
├── routers/
│   ├── documents.py                # MODIFIED: settings endpoint
│   └── manuals.py                  # MODIFIED: preprocessing in manual upload
└── utils/
    └── app_settings.py             # EXISTING: get_setting/set_setting

frontend/
└── lib/
    └── screens/
        └── manual_assistant/
            ├── documents_tab.dart   # MODIFIED: display "preprocessing" status
            └── widgets/
                └── upload_dialog.dart # MINIMAL: status label update

supabase/
└── migrations/
    └── YYYYMMDD_smart_preprocessing.sql  # NEW: raw_content, status CHECK, setting
```

**Structure Decision**: Standard web application layout (backend/ + frontend/ + supabase/). One new service file, one migration, modifications to existing pipeline files.

## Complexity Tracking

> No violations to justify — all constitution gates pass.
