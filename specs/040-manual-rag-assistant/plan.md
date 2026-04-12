# Implementation Plan: System Manual RAG Assistant

**Branch**: `040-manual-rag-assistant` | **Date**: 2026-04-11 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/040-manual-rag-assistant/spec.md`

## Summary

A standalone **Manual Assistant** screen where any authenticated user (reporter, technician, or admin) can (a) upload technical documents (PDF/DOCX/TXT/MD) into a searchable corpus, and (b) ask natural-language questions in Arabic or English whose answers are grounded strictly in uploaded-manual content, with citations.

**Technical approach**: extend the existing FastAPI backend with a new `/api/manuals/*` router. On upload, parse the file with `pymupdf` (PDF) / `python-docx` (DOCX) / raw read (TXT/MD), paragraph-first chunk with 500-word/50-word-overlap fallback, embed each chunk with **nomic-embed-text** via the existing Ollama server, and store both the original file on disk under `backend/uploaded_files/manuals/<uuid>.<ext>` (per constitution IV and [FR-019](./spec.md)) AND the chunks + vectors in a new Supabase `manual_chunks` table using the **pgvector** extension. On query, embed the question, cosine-similarity-search the top-5 chunks, inject into a grounding prompt, and call **Gemma 4** via Ollama (same pattern as existing AI features). The Flutter frontend gains a single `ManualAssistantScreen` with two tabs — **Chat** and **Manuals** — reusing existing widgets (`BottomSheetContainer`, `EmptyState`, `SectionLabel`, `StatusBadge`) and services (`UserService`, `http` client). No new Flutter packages are required.

Source citations render per [FR-012](./spec.md) / [FR-012a](./spec.md): manual title + page (when available) + chunk preview with the supporting sentence(s) visually highlighted via post-hoc substring matching against the LLM output. The previously deferred in-app document viewer stays out of scope and is captured as a follow-up spec.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend, primarily web target via PWA)
**Primary Dependencies**:
- Backend (NEW): `pymupdf` (PDF parsing with page awareness), `python-docx` (DOCX parsing), `pgvector` Postgres extension (enabled via migration)
- Backend (existing, reused): `fastapi`, `httpx` (for Ollama calls — already in requirements at 0.28.1), `supabase` Python client, `uvicorn`
- Frontend (existing, reused): `http`, `file_picker`, `supabase_flutter`, Flutter Material. **No new packages.**
**Storage**:
- Supabase PostgreSQL — two new tables (`manuals`, `manual_chunks`) with `pgvector` extension for 768-dim cosine similarity
- Server filesystem — `backend/uploaded_files/manuals/` for retained original files (per constitution IV + [FR-019](./spec.md)), served automatically at `/files/manuals/<uuid>.<ext>` via existing FastAPI `StaticFiles` mount (unused by UI in this feature; reserved for the future viewer spec)
**Testing**: `pytest` (backend router + services), Flutter integration test for the upload → chat round-trip. Manual acceptance against the spec's User Stories is authoritative; see `quickstart.md`.
**Target Platform**: FastAPI on Linux (Zorin) server behind Nginx; Flutter Web PWA (primary), same build target as the rest of the app.
**Project Type**: web-service (backend) + PWA (frontend) — matches the existing monorepo shape.
**Performance Goals**:
- First visible response ≤ **15 s** for a typical question against manuals under the per-manual cap ([SC-004](./spec.md))
- Upload of a 500-page PDF completes (parse + chunk + embed + persist) in under **3 minutes** end-to-end (derived from [SC-001](./spec.md) user-level target)
- ≥ **100** coexisting manuals with no query-time degradation ([SC-007a](./spec.md))
**Constraints**:
- Per-manual: **500 pages OR 20 MB**, whichever is hit first ([FR-004a](./spec.md))
- DB-side corpus ceiling: **400 MB** configurable, enforced at upload admission ([FR-004c](./spec.md))
- On-disk footprint implicitly bounded by per-manual cap × minimum-capacity guarantee ≈ 2 GB worst case (operator-managed)
- Nginx upload ceiling is 50 MB (constitution IV) — well above our 20 MB per-manual cap
- Ollama runs on the same server; **Gemma 4 E2B** (chosen over E4B for RAM budget) and **nomic-embed-text** are the two models used; `ollama pull nomic-embed-text` is a one-time server setup step
- Ollama endpoint: `http://localhost:11434` (constitution implied, matches existing AI features)
**Scale/Scope**:
- ~100+ manuals × up to ~445 chunks per full manual ≈ up to ~45k rows in `manual_chunks` at the corpus cap
- Single new Flutter screen with 2 tabs, ~5 new widgets, 3 new Flutter models, 1 new Flutter service
- 4 new backend endpoints (`POST /api/manuals/upload`, `GET /api/manuals/`, `DELETE /api/manuals/{id}`, `POST /api/manuals/ask`)
- 1 new Supabase migration enabling `pgvector` + creating the two tables + RLS policies
- All three roles (`reporter`, `technician`, `admin`) have identical access to this feature

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| **I. Full-Stack Ownership** | ✅ Pass | Feature spans backend router + migration + services, Flutter model + service + screen + nav wiring, and docs update. Tasks will enforce the AGENT.md new-feature checklist. |
| **II. Explicit Over Automatic** | ✅ Pass | Upload and delete are explicit user actions. No auto-state-transitions. Questions are only answered when explicitly submitted. No implicit preference cascades. |
| **III. Role-Based Access Control** | ✅ Pass with note | [FR-001](./spec.md) grants all three roles (`reporter`, `technician`, `admin`) identical access to this feature — upload, list, delete, and query. Per-manual access control is explicitly out of scope ([Assumptions](./spec.md)). RLS on `manuals` and `manual_chunks` MUST permit any authenticated user to read/write, providing defense-in-depth while the backend uses the service-role key as the primary access control. No admin-only gate applies because the feature is intentionally open to all roles. |
| **IV. Server-First File Storage** | ✅ Pass | [FR-019](./spec.md) places originals at `backend/uploaded_files/manuals/<uuid>.<ext>`. No cloud object store. Served via existing `StaticFiles` at `/files/manuals/<uuid>.<ext>` (routing by convention; unused by UI in this feature). Files are NOT images, so the 1920px Pillow compression rule does not apply. 20 MB per-manual cap is comfortably under the 50 MB Nginx ceiling. |
| **V. Client-Side Computation Where Possible** | ✅ Pass | The manuals list is loaded once (`GET /api/manuals/`) and filter/search in the Manuals tab runs client-side. Chat retrieval is necessarily server-side (embedding + vector search + LLM generation must run where Ollama lives). |
| **VI. Audit Everything** | ✅ Pass with plan | Uploads, deletes, and questions MUST be logged to `user_activity_log` via `backend/utils/activity.py` (fire-and-forget). Category: `file` for upload/delete, `admin` or a new `manual_qa` for question events — research task will pick the existing category or add one. Deletes additionally log via existing file-log patterns. Backend router tasks will wire this in. |
| **VII. Simplicity & YAGNI** | ✅ Pass with one deliberate complexity | Deliberate: [FR-004c](./spec.md)'s configurable 400 MB ceiling is a spec-mandated clarification answer, not premature abstraction. Everything else stays simple: no per-manual permissions, no version history, no OCR, no dedup, no soft-delete, no viewer. Highlight detection uses a simple post-hoc substring match rather than a second LLM call. |

**Pre-research verdict**: All gates pass. No violations to justify in Complexity Tracking.

**Post-design re-check (after Phase 1)**:

| Principle | Post-design status | Evidence |
|---|---|---|
| I. Full-Stack Ownership | ✅ Still passing | [data-model.md](./data-model.md) §2–§6 defines backend tables + filesystem; [contracts/manuals-api.md](./contracts/manuals-api.md) defines 4 endpoints; [data-model.md](./data-model.md) §8 defines Flutter models; [research.md](./research.md) §15 defines screen + nav wiring. |
| II. Explicit Over Automatic | ✅ Still passing | All four contract endpoints require explicit user action. The `/ask` contract has an explicit `grounded=false` sentinel path; no implicit state. |
| III. Role-Based Access Control | ✅ Still passing | [data-model.md](./data-model.md) §5 makes RLS grants explicit for all three roles; backend service-role key is the primary access layer. |
| IV. Server-First File Storage | ✅ Still passing | [data-model.md](./data-model.md) §6 places files under `backend/uploaded_files/manuals/`; no cloud. |
| V. Client-Side Computation | ✅ Still passing | `GET /api/manuals/` returns the full list; Manuals tab filters in memory. |
| VI. Audit Everything | ✅ Still passing | [contracts/manuals-api.md](./contracts/manuals-api.md) wires `activity.log` fire-and-forget on upload, delete, and ask. |
| VII. Simplicity & YAGNI | ✅ Still passing | Design avoided langchain, spaCy, streaming, viewer, dedup, soft-delete, per-manual ACL, version history. The one deliberate abstraction (configurable 400 MB ceiling) is spec-mandated. |

**Post-design verdict**: All gates still pass. No new Complexity Tracking entries needed.

## Project Structure

### Documentation (this feature)

```text
specs/040-manual-rag-assistant/
├── spec.md              # Feature specification (already written, with 7 clarifications)
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── manuals-api.md
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit.specify)
└── tasks.md             # Phase 2 output (NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── manuals.py                      # NEW — /api/manuals/* endpoints
├── services/
│   ├── manual_parser.py                # NEW — pymupdf/python-docx/txt/md → (text, page) tuples
│   ├── manual_chunker.py               # NEW — paragraph-first + 500-word window + 50-word overlap
│   ├── ollama_embedder.py              # NEW — nomic-embed-text client (batch + single)
│   ├── manual_rag_service.py           # NEW — orchestrates retrieve → prompt → Gemma → highlight
│   └── manual_storage_service.py       # NEW — disk write/delete under uploaded_files/manuals/
├── utils/
│   └── activity.py                     # EXISTING — reused for audit logging
├── uploaded_files/
│   └── manuals/                        # NEW (runtime-created, NOT committed)
└── tests/
    └── routers/
        └── test_manuals.py             # NEW — contract tests for 4 endpoints

supabase/
└── migrations/
    └── 20260411000000_create_manuals.sql   # NEW — pgvector + manuals + manual_chunks + RLS + ivfflat index

frontend/
└── lib/
    ├── models/
    │   ├── manual.dart                     # NEW
    │   ├── manual_source.dart              # NEW (citation row in an answer)
    │   └── manual_qa_answer.dart           # NEW
    ├── services/
    │   └── manual_assistant_service.dart   # NEW — wraps POST/GET/DELETE /api/manuals/*
    └── screens/
        └── manual_assistant/               # NEW
            ├── manual_assistant_screen.dart     # Root, TabBar(2)
            ├── chat_tab.dart                    # Chat thread + input + filter dropdown
            ├── manuals_tab.dart                 # List + FAB + delete
            └── widgets/
                ├── answer_card.dart             # Answer + collapsible Sources
                ├── source_card.dart             # Title + page + highlighted preview
                ├── upload_dialog.dart           # File picker → title → confirm
                └── empty_state_hint.dart        # "Upload a manual first" / "Your library is empty"
```

**Structure Decision**: Option 2 (Web application — backend/ + frontend/). This matches the existing monorepo layout and every prior 0xx feature in this repo. No new top-level directories are introduced.

## Complexity Tracking

> **Constitution Check passed.** No violations to justify.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| *(none)*  |            |                                     |
