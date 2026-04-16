-- knowledge_documents table
CREATE TABLE knowledge_documents (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    filename      text NOT NULL,
    display_name  text NOT NULL,
    file_path     text NOT NULL,
    status        text NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'indexing', 'ready', 'failed')),
    error_message text,
    total_pages   int,
    total_chunks  int,
    indexed_at    timestamptz,
    uploaded_by   text NOT NULL,
    created_at    timestamptz DEFAULT now()
);

-- document_chunks table
CREATE TABLE document_chunks (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id     uuid REFERENCES knowledge_documents(id) ON DELETE CASCADE,
    chunk_type      text NOT NULL CHECK (chunk_type IN ('parent', 'child')),
    parent_id       uuid REFERENCES document_chunks(id) ON DELETE CASCADE,
    section_title   text,
    content         text NOT NULL,
    page_number     int,
    embedding       vector(768),
    created_at      timestamptz DEFAULT now()
);

-- Partial index: only child chunks with embeddings are searched
CREATE INDEX idx_document_chunks_embedding
    ON document_chunks USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100)
    WHERE chunk_type = 'child';

-- RPC function for vector search
CREATE OR REPLACE FUNCTION search_document_chunks(
    query_embedding vector(768),
    match_count int DEFAULT 3,
    match_threshold float DEFAULT 0.30
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
      AND dc.embedding <=> query_embedding < match_threshold
    ORDER BY dc.embedding <=> query_embedding
    LIMIT match_count;
$$;