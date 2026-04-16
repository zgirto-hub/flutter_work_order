-- Add chunk ordering
ALTER TABLE document_chunks ADD COLUMN chunk_index int;

-- Add stale embedding tracking
ALTER TABLE document_chunks ADD COLUMN embedding_stale boolean NOT NULL DEFAULT false;

-- Add file extension tracking
ALTER TABLE knowledge_documents ADD COLUMN file_extension text;

-- Backfill chunk_index for existing chunks (order by created_at within parent)
WITH ranked AS (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY parent_id ORDER BY created_at) - 1 AS idx
    FROM document_chunks
    WHERE chunk_type = 'child'
)
UPDATE document_chunks SET chunk_index = ranked.idx
FROM ranked WHERE document_chunks.id = ranked.id;

-- Also index parent chunks (by created_at)
WITH ranked_parents AS (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY document_id ORDER BY created_at) - 1 AS idx
    FROM document_chunks
    WHERE chunk_type = 'parent'
)
UPDATE document_chunks SET chunk_index = ranked_parents.idx
FROM ranked_parents WHERE document_chunks.id = ranked_parents.id;

-- Update RPC to exclude stale chunks
CREATE OR REPLACE FUNCTION search_document_chunks(
    query_embedding vector(768),
    match_count int DEFAULT 10,
    match_threshold float DEFAULT 0.55
)
RETURNS TABLE (
    id uuid,
    document_id uuid,
    parent_id uuid,
    section_title text,
    content text,
    page_number int,
    distance float
)
LANGUAGE sql STABLE
AS $$
    SELECT
      dc.id,
      dc.document_id,
      dc.parent_id,
      dc.section_title,
      dc.content,
      dc.page_number,
      dc.embedding <=> query_embedding AS distance
    FROM document_chunks dc
    JOIN knowledge_documents kd ON kd.id = dc.document_id
    WHERE dc.chunk_type = 'child'
      AND kd.status = 'ready'
      AND dc.embedding_stale = false
      AND dc.embedding <=> query_embedding < match_threshold
    ORDER BY dc.embedding <=> query_embedding
    LIMIT match_count;
$$;