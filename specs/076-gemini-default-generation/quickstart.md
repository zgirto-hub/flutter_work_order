# Quickstart: 076 — Default Q&A Generation to Gemini Flash

**Date**: 2026-04-16

## What This Feature Does

Changes the default AI generation provider from local Ollama to Gemini Flash for the Ask-the-AI Q&A assistant. All other RAG pipeline stages (query rewrite, HyDE, embedding, reranking) remain on local Ollama.

## Files to Change (4 files)

1. **`backend/services/ai_providers/resolver.py`** — Change `_DEFAULT_PROVIDER` from `"local"` to `"gemini"`
2. **`backend/main.py`** — Add one-time migration call in `lifespan` to rewrite existing `"local"` → `"gemini"` in `app_settings`
3. **`supabase/migrations/20260415_app_settings.sql`** — Update seed value from `'local'` to `'gemini'`
4. **`backend/tests/test_provider_default.py`** — New test file for default provider and migration

## Prerequisites

- `GEMINI_API_KEY` environment variable must be set on the server
- Gemini provider already registered in `backend/services/ai_providers/__init__.py`

## Verification

```bash
# After deployment, check server logs for:
# - "ai_provider_migrated" activity log entry (one-time)
# - Subsequent /manuals/ask requests showing provider="gemini" in latency_breakdown

# Test fallback by temporarily unsetting GEMINI_API_KEY
# - Requests should still succeed via Ollama fallback
# - Activity log should show "ai_provider_fallback" entries
```

## Rollback

Set provider back to local via admin UI (`POST /ai/provider` with `provider="local"`) or revert the `_DEFAULT_PROVIDER` constant and redeploy.
