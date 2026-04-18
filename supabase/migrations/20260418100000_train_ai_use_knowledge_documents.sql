-- Spec 080 follow-up: training reads from knowledge_documents (live table),
-- not the legacy `manuals` table. Repoint staleness tracking.

-- 1. Drop the FK on source_manual_id (it referenced legacy manuals table).
--    Keep the column as a loose UUID so training entries can track their
--    source document without a hard reference.
ALTER TABLE validated_qa
  DROP CONSTRAINT IF EXISTS validated_qa_source_manual_id_fkey;

-- 2. Add updated_at to knowledge_documents for staleness detection.
ALTER TABLE knowledge_documents
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

UPDATE knowledge_documents
  SET updated_at = created_at
  WHERE updated_at IS NULL;
