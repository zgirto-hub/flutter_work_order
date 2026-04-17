# Quickstart: 080 — Train the AI Tab

**Branch**: `080-train-ai-tab`

## Prerequisites

- Python 3.10+ with FastAPI backend running
- Flutter 3.x frontend
- Supabase (PostgreSQL + pgvector) with existing schema
- Ollama running locally (nomic-embed-text-v2-moe for embeddings, gemma4:e2b for generation)

## Setup

1. **Apply migration**:
   ```sql
   -- Run on Supabase: supabase/migrations/20260418000000_train_ai_staleness.sql
   -- Adds verified_at + source_manual_id to validated_qa
   -- Adds updated_at to manuals
   ```

2. **Backend**: No new Python dependencies. All imports exist:
   - `services.ai_providers.resolver.generate` (provider_generate)
   - `services.ollama_embedder.embed_single` / `embed_many`
   - `services.validated_qa_service`

3. **Frontend**: No new Dart dependencies. Uses existing `http`, `supabase_flutter`, Flutter Material.

## Verification Steps

1. **Migration**: Confirm `validated_qa` has `verified_at` and `source_manual_id` columns; `manuals` has `updated_at`.
2. **Admin guard**: Login as non-admin — "Train the AI" tab should not be visible.
3. **Section A**: Select a manual with chunks → Generate → Approve 1+ → Save All Approved → Verify entries in Verified Answers tab.
4. **Section B**: Rate an AI answer positively twice (different users or sessions) → Check it appears in Real Usage suggestions.
5. **Section C**: Re-embed a manual's chunks → Check entries derived from that manual appear in Needs Review.

## Key Files

| Layer | File | Changes |
|-------|------|---------|
| Migration | `supabase/migrations/20260418000000_train_ai_staleness.sql` | NEW |
| Backend | `backend/routers/manuals.py` | 4 new endpoints + extend paraphrase + verify re-embed |
| Backend | `backend/services/validated_qa_service.py` | Extend `create_verified_answer` for `source_manual_id` |
| Frontend | `frontend/lib/screens/manual_assistant/manual_assistant_screen.dart` | Add 7th tab |
| Frontend | `frontend/lib/screens/manual_assistant/train_ai_tab.dart` | NEW — main tab widget |
| Frontend | `frontend/lib/screens/manual_assistant/widgets/qa_candidate_card.dart` | NEW |
| Frontend | `frontend/lib/screens/manual_assistant/widgets/usage_suggestion_card.dart` | NEW |
| Frontend | `frontend/lib/screens/manual_assistant/widgets/stale_entry_card.dart` | NEW |
| Frontend | `frontend/lib/services/manual_assistant_service.dart` | 5 new methods + extend paraphrase |
