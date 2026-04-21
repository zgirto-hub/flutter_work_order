-- Spec 090: Drop legacy `manuals` table family and dependent DB objects.
--
-- Preconditions (enforced by the DO-block below):
--   - manuals rows = 0
--   - manual_chunks rows = 0
-- If either assertion fails the migration aborts without dropping anything.
--
-- This migration is Story 3 of spec 090. Stories 1 and 2 (frontend UI
-- removal and backend route/service removal) must have been deployed first;
-- otherwise the live application will 500 on calls to routes that query
-- these tables.

BEGIN;

-- 1. Safety gate — abort if the legacy tables are not empty.
DO $$
DECLARE
    manuals_n INT;
    chunks_n INT;
BEGIN
    SELECT COUNT(*) INTO manuals_n FROM manuals;
    SELECT COUNT(*) INTO chunks_n FROM manual_chunks;
    IF manuals_n > 0 OR chunks_n > 0 THEN
        RAISE EXCEPTION
            'Aborting spec-090 drop: manuals=% manual_chunks=% (expected 0/0). '
            'Investigate before rerunning. Do NOT remove this check.',
            manuals_n, chunks_n;
    END IF;
END $$;

-- 2. Drop the dangling FK and column on answer_ratings.
--    (Other surviving code no longer reads answer_ratings.manual_id after
--    Story 2; dropping the column eliminates the reference. The FK to
--    validated_qa.source_manual_id was already removed by the spec-080
--    migration 20260418100000_train_ai_use_knowledge_documents.sql and is
--    intentionally NOT re-touched here.)
ALTER TABLE answer_ratings DROP CONSTRAINT IF EXISTS answer_ratings_manual_id_fkey;
ALTER TABLE answer_ratings DROP COLUMN IF EXISTS manual_id;

-- 3. Drop the RPC functions that operated on the legacy tables.
DROP FUNCTION IF EXISTS search_manual_chunks(vector, uuid, int);
DROP FUNCTION IF EXISTS create_manual_with_chunks(uuid, text, text, text, bigint, uuid, jsonb, bigint);
DROP FUNCTION IF EXISTS delete_manual_with_stats(uuid);

-- 4. Drop the tables in FK-safe order (manual_chunks before manuals).
--    manual_corpus_stats has no FKs and is dropped last.
DROP TABLE IF EXISTS manual_chunks;
DROP TABLE IF EXISTS manuals;
DROP TABLE IF EXISTS manual_corpus_stats;

COMMIT;

-- Post-migration verification (run as a separate ad-hoc query to confirm):
--   SELECT count(*) FROM information_schema.tables
--     WHERE table_schema='public'
--       AND table_name IN ('manuals','manual_chunks','manual_corpus_stats');
--   -- expected: 0
--
--   SELECT count(*) FROM pg_proc
--     WHERE proname IN ('search_manual_chunks','create_manual_with_chunks','delete_manual_with_stats');
--   -- expected: 0
--
--   SELECT count(*) FROM information_schema.columns
--     WHERE table_name='answer_ratings' AND column_name='manual_id';
--   -- expected: 0
--
--   SELECT count(*) FROM manual_assistant_settings WHERE id = 1;
--   -- expected: 1 (retained)
--
--   SELECT count(*) FROM information_schema.columns
--     WHERE table_name='validated_qa' AND column_name='source_manual_id';
--   -- expected: 1 (retained)
