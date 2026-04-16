# Quickstart: Smart Document Preprocessing

**Feature**: 073-smart-doc-preprocess  
**Date**: 2026-04-16

## Prerequisites

- `GEMINI_API_KEY` environment variable set on the server (already required by spec 063)
- Supabase database accessible with migration permissions
- Backend running (FastAPI on Uvicorn)
- Frontend running (Flutter web dev server)

## Files to Create

| File | Purpose |
|------|---------|
| `backend/services/document_preprocessor.py` | Core preprocessing service — sends page text to Gemini Flash, returns structured Markdown |
| `supabase/migrations/YYYYMMDD_smart_preprocessing.sql` | Migration: add `raw_content` column, update status CHECK, seed setting |

## Files to Modify

| File | Change |
|------|--------|
| `backend/services/document_service.py` | Insert preprocessing step in `index_document()` between text extraction and section detection |
| `backend/routers/manuals.py` (or `manual_rag_service`) | Insert preprocessing step in manual upload flow |
| `backend/routers/documents.py` | Add preprocessing setting endpoints (or integrate into existing admin settings) |
| `frontend/lib/screens/manual_assistant/documents_tab.dart` | Display "preprocessing" status label in UI |
| `frontend/lib/screens/manual_assistant/widgets/upload_dialog.dart` | Optional: update status display during upload |

## Verification Steps

1. **Migration**: Run the migration, verify `raw_content` column exists on both `document_chunks` and `manual_chunks`
2. **Setting**: Verify `smart_preprocessing_enabled = 'true'` in `app_settings`
3. **Upload slide deck**: Upload a terse slide-deck PDF, verify status transitions: pending → preprocessing → indexing → ready
4. **Check chunks**: Query `document_chunks` for the new document — verify `content` contains enriched Markdown and `raw_content` contains original text
5. **Search quality**: Search for a concept described only in terse bullets — verify it appears in top 5 results
6. **Upload dense manual**: Upload a dense prose document — verify search quality is not degraded
7. **Fallback**: Stop/block Gemini API access, upload a document — verify it completes using raw text (no preprocessing)
8. **Toggle**: Disable preprocessing in settings, upload a document — verify no AI calls made, `raw_content` is NULL
9. **Restart backend**: `sudo systemctl restart document_server.service`

## Key Design Decisions

- Preprocessing happens per-page, before chunking — enriched text flows through existing chunking pipeline unchanged
- Gemini Flash called directly (not through Q&A resolver) — fixed provider for batch workloads
- Per-page graceful fallback — if one page fails, others still get enriched
- Raw text retained in `raw_content` column — enables future re-preprocessing
- Sequential page processing — no parallelism to avoid rate limits
