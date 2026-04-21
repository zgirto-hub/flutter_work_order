# Data Model Change — Spec 090

**Feature**: Delete Legacy `manuals` Table & Dead Code
**Phase**: 1 (Design)
**Scope**: All changes land in a single SQL migration: `supabase/migrations/20260420_drop_legacy_manuals.sql`.

---

## Tables being DROPPED

### `manuals`

- Current: one row per uploaded manual-style PDF/DOCX; columns `id`, `title`, `file_name`, `file_extension`, `file_size_bytes`, `uploaded_by` (FK to `users(id)`), `chunk_count`, `created_at`, `updated_at`.
- Production row count: **0** (verified in prior session; re-verified at migration time).
- Incoming FKs: `manual_chunks.manual_id` (ON DELETE CASCADE), `answer_ratings.manual_id` (ON DELETE SET NULL).
- Outgoing FK: `uploaded_by` → `users(id)`.
- Indexes: `manuals_uploaded_by_idx`, `manuals_created_at_desc_idx`.
- RLS policy: `manuals_authenticated_all` (dropped with the table).

### `manual_chunks`

- Current: one row per chunk of a manual; columns `id`, `manual_id` (FK to `manuals.id`), `chunk_index`, `source_page`, `content`, `raw_content`, `embedding vector(768)`, `created_at`.
- Production row count: **0** (empty because `manuals` is empty; the FK cascade ensured this).
- Incoming FKs: none.
- Outgoing FK: `manual_id` → `manuals(id)`.
- Indexes: `manual_chunks_manual_id_idx`, `manual_chunks_embedding_ivfflat_idx`, `manual_chunks_manual_id_chunk_index_uq`.
- RLS policy: `manual_chunks_authenticated_all` (dropped with the table).

### `manual_corpus_stats`

- Current: singleton (`id = 1`) row tracking `total_bytes`, `manual_count`, `updated_at`. Used by the ceiling enforcement in `manual_rag_service.py`.
- Production row count: **1** (the singleton), with stale or zero values.
- Incoming FKs: none.
- RLS policy: `manual_corpus_stats_authenticated_read` (dropped with the table).

---

## RPC functions being DROPPED

| Function | Signature (input → output) | Callers (all being removed in Story 2) |
|---|---|---|
| `search_manual_chunks` | `(q_embedding vector(768), manual_id_filter uuid, match_count int) → TABLE(id, manual_id, chunk_index, source_page, content, manual_title, distance)` | No live caller. The ask-path RAG pipeline searches `document_chunks` via spec 072. |
| `create_manual_with_chunks` | `(p_id uuid, p_title text, p_file_name text, p_file_extension text, p_file_size_bytes bigint, p_uploaded_by uuid, p_chunks jsonb, p_projected_bytes bigint) → uuid` | `manual_rag_service.upload_manual` pipeline only (being removed). |
| `delete_manual_with_stats` | `(p_manual_id uuid) → TABLE(file_extension text, title text)` | `manual_rag_service.delete_manual` pipeline only (being removed). |

---

## Columns / constraints being MODIFIED

### `answer_ratings.manual_id`

- Current: `UUID NULLABLE`, FK `answer_ratings_manual_id_fkey` references `manuals(id) ON DELETE SET NULL`.
- Change: `ALTER TABLE answer_ratings DROP CONSTRAINT answer_ratings_manual_id_fkey; ALTER TABLE answer_ratings DROP COLUMN manual_id;`
- Rationale: after Story 2, no code reads this column. See research.md Decision 1 for the "drop column vs drop FK only" deliberation and the override path.

---

## Tables / columns being RETAINED (explicitly called out to avoid accidental removal)

### `manual_assistant_settings`

- **Retained**. Holds the Layer 2 AI assistant system prompt. Despite the name, this is live configuration read by `/manuals/ask` on every call. Unrelated to the manuals file corpus.
- Columns: `id smallint CHECK (id = 1)`, `system_instructions text`, `updated_at timestamptz`.
- The migration MUST NOT touch this table.

### `validated_qa.manual_ids` (UUID[] array)

- **Retained, unchanged**. Semantics shifted: values now reference `knowledge_documents(id)`. Name is historically misleading, but all readers treat the array as "IDs of source documents" regardless. Out of scope to rename.

### `validated_qa.source_manual_id`

- **Retained, unchanged**. FK to `manuals(id)` was already dropped by the spec-080 migration (`20260418100000_train_ai_use_knowledge_documents.sql`). Column is a loose UUID semantically meaning "source knowledge_document id". This spec performs no further alteration.

---

## Migration shape (non-normative outline — real SQL in tasks phase)

```sql
-- Spec 090: drop legacy manuals tables + dependent FK/column + RPCs.
-- Preconditions: manuals and manual_chunks rows = 0 (defensive check inside).

BEGIN;

-- 1. Safety gate — abort if legacy tables are non-empty
DO $$
DECLARE manuals_n int; chunks_n int;
BEGIN
  SELECT COUNT(*) INTO manuals_n FROM manuals;
  SELECT COUNT(*) INTO chunks_n FROM manual_chunks;
  IF manuals_n > 0 OR chunks_n > 0 THEN
    RAISE EXCEPTION 'Aborting drop: manuals=% manual_chunks=%, expected 0/0', manuals_n, chunks_n;
  END IF;
END $$;

-- 2. Drop dependent FK + column on answer_ratings (see research.md Decision 1)
ALTER TABLE answer_ratings DROP CONSTRAINT IF EXISTS answer_ratings_manual_id_fkey;
ALTER TABLE answer_ratings DROP COLUMN IF EXISTS manual_id;

-- 3. Drop RPC functions
DROP FUNCTION IF EXISTS search_manual_chunks(vector, uuid, int);
DROP FUNCTION IF EXISTS create_manual_with_chunks(uuid, text, text, text, bigint, uuid, jsonb, bigint);
DROP FUNCTION IF EXISTS delete_manual_with_stats(uuid);

-- 4. Drop tables (FK order: manual_chunks → manuals)
DROP TABLE IF EXISTS manual_chunks;
DROP TABLE IF EXISTS manuals;
DROP TABLE IF EXISTS manual_corpus_stats;

COMMIT;
```

Note: `validated_qa.source_manual_id` FK was already removed by migration `20260418100000_train_ai_use_knowledge_documents.sql`, so the new migration does **not** attempt to drop it again.

---

## Verification queries (post-migration)

```sql
-- Absent tables
SELECT count(*) FROM information_schema.tables
  WHERE table_schema='public' AND table_name IN ('manuals','manual_chunks','manual_corpus_stats');
-- expected: 0

-- Absent RPCs
SELECT count(*) FROM pg_proc
  WHERE proname IN ('search_manual_chunks','create_manual_with_chunks','delete_manual_with_stats');
-- expected: 0

-- answer_ratings has no manual_id column and no FK to manuals
SELECT count(*) FROM information_schema.columns
  WHERE table_name='answer_ratings' AND column_name='manual_id';
-- expected: 0

SELECT count(*) FROM information_schema.table_constraints
  WHERE table_name='answer_ratings' AND constraint_name='answer_ratings_manual_id_fkey';
-- expected: 0

-- manual_assistant_settings still present (regression guard)
SELECT count(*) FROM manual_assistant_settings WHERE id = 1;
-- expected: 1

-- validated_qa.source_manual_id still present (regression guard)
SELECT count(*) FROM information_schema.columns
  WHERE table_name='validated_qa' AND column_name='source_manual_id';
-- expected: 1
```
