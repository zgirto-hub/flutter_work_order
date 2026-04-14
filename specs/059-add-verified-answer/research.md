# Research: Add Verified Answer — Manual Entry

**Date**: 2026-04-14
**Feature**: 059-add-verified-answer

## R1: rating_id NOT NULL Constraint

**Question**: The `validated_qa` table has `rating_id UUID NOT NULL REFERENCES answer_ratings(id)`. Can we insert a row without a rating_id?

- **Decision**: Add a migration to make `rating_id` nullable.
- **Rationale**: Direct admin inserts do not originate from `answer_ratings` — there is no parent rating record. A sentinel/dummy row in `answer_ratings` would be a data integrity hack that pollutes the ratings table and complicates queries. Making the column nullable cleanly separates the two creation paths (review queue vs. direct admin entry).
- **Alternatives considered**:
  - **Option A — Sentinel row in `answer_ratings`**: Insert a synthetic rating with `review_status = 'approved'` and use its ID. Rejected because it creates fake data in the ratings table, breaks aggregate queries (count, averages), and requires special-case filtering everywhere ratings are queried.
  - **Option B — Nullable `rating_id` (chosen)**: Simple `ALTER TABLE` dropping the NOT NULL constraint. Existing rows with `rating_id` set are unaffected. The `search_validated_qa` RPC does not reference `rating_id` at all, so no downstream impact.

**Migration file**: `supabase/migrations/20260415000000_make_rating_id_nullable.sql`

## R2: Embedding Service Import

**Question**: Which embedding function does the codebase use?

- **Decision**: Use `embed_single` from `services.ollama_embedder` (not `embed_text` from `services.embeddings`).
- **Rationale**: `services.embeddings` does not exist in the codebase. The actual embedding service is `services/ollama_embedder.py` which exports `embed_single()`, `embed_many()`, and `EmbedderTimeoutError`. This is already imported in `routers/manuals.py` at line 22.
- **Alternatives considered**: None — `embed_single` is the only embedding function in the project.

## R3: Existing Insert Pattern

**Question**: What fields must be set when inserting into `validated_qa`?

- **Decision**: Match the existing pattern in `validated_qa_service.py:194-206` but omit `rating_id` (after migration) and add it via the new create endpoint in `validated_qa_service.py`.
- **Required fields**: `question_text`, `validated_answer`, `question_embedding` (formatted as `"[0.1,0.2,...]"`), `validated_by`, `equipment_type` (extracted via `_extract_equipment_type`), `fault_code` (extracted via `_extract_fault_code`).
- **Optional fields**: `manual_ids` (default `[]`), `source_chunks` (default `[]`).
- **Auto-set fields**: `id` (gen_random_uuid), `validated_at` (now), `thumbs_up_count` (0), `thumbs_down_count` (0), `is_reflagged` (false), `created_at` (now), `updated_at` (now).

## R4: Where to Place the Create Logic

**Question**: Should the create logic go in the router or in `validated_qa_service.py`?

- **Decision**: Add a `create_verified_answer()` function in `validated_qa_service.py`, called from a new endpoint in `routers/manuals.py`. This matches the existing pattern where `update_verified_answer` lives in the service and is called from the router.
- **Rationale**: Keeps embedding logic in the service layer (consistent with `review_answer()` and `update_verified_answer()`), keeps the router thin (just HTTP concerns + error mapping).

## R5: Flutter Service Pattern

**Question**: What exact pattern should the new Flutter method follow?

- **Decision**: Follow `updateVerifiedAnswer()` in `manual_assistant_service.dart:591-627`.
- **Key pattern details**:
  - URL: `${AppConfig.baseUrl}/manuals/verified-answers` (POST, no ID in path)
  - Headers: `Content-Type: application/json` + Bearer token from Supabase auth
  - Error codes: 403 → admin required, 422 → validation error, 504 → embedding timeout, else generic
  - No explicit timeout set (uses default http timeout)

## R6: Flutter UI Pattern

**Question**: What exact dialog structure should the add dialog follow?

- **Decision**: Clone `_showEditDialog()` from `verified_answers_tab.dart:113-165` with these differences:
  - Title: "Add Verified Answer" (not "Edit Verified Answer")
  - Controllers start empty (not pre-filled)
  - No delete button in actions
  - `autofocus: true` on question field
  - On submit: calls `_saveNewEntry()` instead of `_saveEdit()`
- **Build method change**: The current `build()` returns a `Column`. Wrap in `Stack` with a `Positioned` FAB at bottom-right.
