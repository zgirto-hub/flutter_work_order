# Implementation Plan: Delete Legacy `manuals` Table & Dead Code

**Branch**: `090-delete-legacy-manuals` | **Date**: 2026-04-20 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/090-delete-legacy-manuals/spec.md`

## Summary

Remove the dead `manuals` / `manual_chunks` / `manual_corpus_stats` code path and its supporting routes/UI in three ordered stages — Story 1 (frontend UX cleanup), Story 2 (backend route & service removal), Story 3 (database migration) — each independently deployable. The live document corpus (`knowledge_documents` / `document_chunks`) is untouched. The `/manuals/*` URL prefix, the `manual_assistant_settings` table, and the `validated_qa.source_manual_id` / `manual_ids[]` columns are preserved by design. The plan is purely removal; no new tech, no new features.

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x (frontend), Python 3.10 (backend)
**Primary Dependencies**: Flutter Material, `http`, `supabase_flutter` (frontend, existing); FastAPI, Supabase Python client (backend, existing). **No new dependencies added. No existing dependencies removed — the packages that supported the removed paths (e.g., PDF parsing) remain in use by the live knowledge-documents pipeline.**
**Storage**: Supabase (PostgreSQL + pgvector) — drops three tables, three RPCs, one FK, and one column. Shared filesystem directory `backend/uploaded_files/manuals/` is **not** touched (also used by `knowledge_documents` — verified in specs 070/072).
**Testing**: pytest for backend (existing suite minus removed-route tests), `flutter analyze` + existing Dart widget tests for frontend. Manual end-to-end verification per quickstart.md at each story boundary.
**Target Platform**: Single Linux server (Zorin) behind Nginx; Flutter web PWA for frontend.
**Project Type**: Web application (Flutter frontend + FastAPI backend + Supabase DB), matching the existing `backend/`, `frontend/`, `supabase/migrations/` layout.
**Performance Goals**: No new performance requirement. Story 3 migration should complete in well under 1 second on the production DB (tiny tables, small amount of metadata).
**Constraints**: Production corpus must remain searchable throughout the deploy — the retained `/manuals/ask` pipeline reads from `document_chunks` so this holds trivially once the (already-dead) write paths are removed.
**Scale/Scope**: Three DB tables dropped, three RPCs dropped, one FK + column removed from `answer_ratings`, ~12 backend routes removed, ~12 frontend service methods removed, ~4 frontend files deleted, ~1 backfill script deleted. Net reduction on the order of 1–2k lines.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Rationale |
|---|---|---|
| **I. Full-Stack Ownership** | Pass | The deletion spans the full stack — DB migration, backend routes/services, frontend screens/models — in an ordered rollout per the spec's Stories 1–3. No layer is left half-removed. |
| **II. Explicit Over Automatic** | Pass | No state transitions or assignment behavior modified. The removal is explicit (drop by name). Pre-migration row-count gate in Story 3 prevents silent data loss. |
| **III. Role-Based Access Control** | Pass | Admin-only routes being removed were admin-gated; retained routes keep their current gating unchanged. No new permission paths introduced. |
| **IV. Server-First File Storage** | Pass | `backend/uploaded_files/manuals/` directory is shared with `knowledge_documents` and is explicitly preserved. No file I/O added or removed in a way that affects the storage model. |
| **V. Client-Side Computation Where Possible** | Pass | Not applicable — no filtering/caching behavior changed. |
| **VI. Audit Everything** | Pass | No existing audit hook disabled. The removed `/migrate-all`, `/migrate-cleanup` routes emit activity-log entries today; those routes go away because the activity they logged no longer exists. Retained routes keep their audit calls untouched. |
| **VII. Simplicity & YAGNI** | Pass (core intent of this feature) | This spec *is* YAGNI in action: the code exists for a use case that no longer exists. Removing it reduces cognitive load for every future developer. |

**Verdict**: Constitution Check passes with no waivers needed. Complexity Tracking table below is empty.

### Post-design re-check (after Phase 1)

No new code paths are introduced during Phase 1 — research.md, data-model.md, and contracts/ are purely descriptive of the planned removal. Constitution status is unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/090-delete-legacy-manuals/
├── plan.md                 # This file
├── spec.md                 # Feature specification (already written)
├── research.md             # Phase 0 output — decisions behind the plan
├── data-model.md           # Phase 1 output — DB objects dropped/retained
├── quickstart.md           # Phase 1 output — per-story verification recipe
├── contracts/
│   ├── removed-api.md      # Phase 1 output — routes being removed
│   └── retained-api.md     # Phase 1 output — routes being kept (incl. URL prefix note)
├── checklists/
│   └── requirements.md     # Spec quality checklist (already written)
└── tasks.md                # /speckit.tasks output (NOT created here)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   ├── manuals.py              # TRIM — remove ~12 CRUD routes (lines ~209–2685); retain AI-assistant routes
│   └── documents.py            # TRIM — remove /migrate-all, /migration-status, /migrate-cleanup + _run_migration helper
├── services/
│   ├── manual_rag_service.py   # TRIM — remove upload/delete functions + manual_corpus_stats reads/writes; retain ask-path helpers
│   ├── manual_parser.py        # UNCHANGED — also imported by document_service.py for knowledge_documents parsing
│   ├── manual_storage_service.py  # DELETE — sole caller is manual_rag_service.py upload/delete paths (being removed)
│   └── system_registry.py      # UNCHANGED — already redirected to knowledge_documents (commit f0cf05c)
├── scripts/
│   └── backfill_validated_qa_manual_ids.py   # DELETE — one-time script, already run in prod
└── tests/
    ├── routers/test_manuals_bulk_delete.py   # DELETE — covers removed bulk-delete chunks route
    ├── test_derive_manual_ids.py             # TRIM or DELETE — keep knowledge_documents-backed assertions only
    ├── test_manual_rag_latency.py            # TRIM — keep ask-path latency; drop upload-path fixtures if any
    └── (other tests touching removed routes) # DELETE entries that test removed endpoints

frontend/lib/
├── screens/manual_assistant/
│   ├── manuals_tab.dart          # DELETE — 186 lines, already not rendered in manual_assistant_screen.dart tab bar
│   ├── chunk_editor_screen.dart  # DELETE — 502 lines, only caller is manuals_tab.dart
│   ├── documents_tab.dart        # TRIM — remove "old manuals" migration block (~lines 420–500) and _checkOldManuals helper
│   └── widgets/
│       └── upload_dialog.dart    # DELETE — only caller is manuals_tab.dart
├── services/
│   └── manual_assistant_service.dart  # TRIM — remove list/upload/delete manual + chunk CRUD methods; retain all AI-assistant methods
└── models/
    └── manual.dart               # DELETE — last consumer goes away when service methods are trimmed

supabase/migrations/
└── 20260420_drop_legacy_manuals.sql  # NEW — pre-check row counts, drop answer_ratings.manual_id FK + column, drop RPCs, drop tables in FK-safe order
```

**Structure Decision**: Web-app layout (existing `backend/` + `frontend/` + `supabase/migrations/`). No new top-level directories. No restructuring.

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified.

No violations. Table intentionally empty.
