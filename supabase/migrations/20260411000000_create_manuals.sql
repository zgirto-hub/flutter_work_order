-- System Manual RAG Assistant: Migration
-- Feature: 040-manual-rag-assistant
-- Created: 2026-04-11

-- 1. Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. Create `manuals` table
CREATE TABLE IF NOT EXISTS manuals (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_extension TEXT NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL,
    chunk_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (id)
);

-- 3. Create `manual_chunks` table
CREATE TABLE IF NOT EXISTS manual_chunks (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    manual_id UUID NOT NULL REFERENCES manuals(id) ON DELETE CASCADE,
    chunk_index INTEGER NOT NULL,
    source_page INTEGER,
    content TEXT NOT NULL,
    embedding VECTOR(768) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (id)
);

-- 4. Create `manual_corpus_stats` table
CREATE TABLE IF NOT EXISTS manual_corpus_stats (
    id SMALLINT NOT NULL CHECK (id = 1),
    total_bytes BIGINT NOT NULL DEFAULT 0,
    manual_count INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (id)
);

-- Indexes for `manuals`
CREATE INDEX IF NOT EXISTS manuals_uploaded_by_idx ON manuals (uploaded_by);
CREATE INDEX IF NOT EXISTS manuals_created_at_desc_idx ON manuals (created_at DESC);

-- Indexes for `manual_chunks`
CREATE INDEX IF NOT EXISTS manual_chunks_manual_id_idx ON manual_chunks (manual_id);
CREATE INDEX IF NOT EXISTS manual_chunks_embedding_ivfflat_idx 
    ON manual_chunks USING ivfflat (embedding vector_cosine_ops) WITH (lists = 50);
CREATE UNIQUE INDEX IF NOT EXISTS manual_chunks_manual_id_chunk_index_uq 
    ON manual_chunks (manual_id, chunk_index);

-- Row Level Security policies
ALTER TABLE manuals ENABLE ROW LEVEL SECURITY;
ALTER TABLE manual_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE manual_corpus_stats ENABLE ROW LEVEL SECURITY;

-- manuals: any authenticated user can read/write
CREATE POLICY manuals_authenticated_all ON manuals
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- manual_chunks: any authenticated user can read/write
CREATE POLICY manual_chunks_authenticated_all ON manual_chunks
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- manual_corpus_stats: read-only for authenticated, writes only via service role
CREATE POLICY manual_corpus_stats_authenticated_read ON manual_corpus_stats
    FOR SELECT TO authenticated USING (true);

-- Seed the singleton stats row
INSERT INTO manual_corpus_stats (id, total_bytes, manual_count) VALUES (1, 0, 0)
ON CONFLICT (id) DO NOTHING;

-- Vector search RPC for manual_chunks.
-- Returns top-k nearest chunks by cosine distance, optionally scoped to a single manual.
CREATE OR REPLACE FUNCTION search_manual_chunks(
    q_embedding vector(768),
    manual_id_filter uuid DEFAULT NULL,
    match_count int DEFAULT 5
)
RETURNS TABLE (
    id uuid,
    manual_id uuid,
    chunk_index int,
    source_page int,
    content text,
    manual_title text,
    distance float
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        mc.id,
        mc.manual_id,
        mc.chunk_index,
        mc.source_page,
        mc.content,
        m.title AS manual_title,
        (mc.embedding <=> q_embedding) AS distance
    FROM manual_chunks mc
    JOIN manuals m ON m.id = mc.manual_id
    WHERE manual_id_filter IS NULL OR mc.manual_id = manual_id_filter
    ORDER BY mc.embedding <=> q_embedding
    LIMIT match_count;
$$;

-- Atomic upload of a manual and its chunks, plus stats update.
-- Does everything in one SQL transaction so partial failures roll back cleanly.
CREATE OR REPLACE FUNCTION create_manual_with_chunks(
    p_id uuid,
    p_title text,
    p_file_name text,
    p_file_extension text,
    p_file_size_bytes bigint,
    p_uploaded_by uuid,
    p_chunks jsonb,
    p_projected_bytes bigint
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_chunk jsonb;
BEGIN
    INSERT INTO manuals (id, title, file_name, file_extension, file_size_bytes, uploaded_by, chunk_count)
    VALUES (p_id, p_title, p_file_name, p_file_extension, p_file_size_bytes, p_uploaded_by, jsonb_array_length(p_chunks));

    FOR v_chunk IN SELECT * FROM jsonb_array_elements(p_chunks) LOOP
        INSERT INTO manual_chunks (manual_id, chunk_index, source_page, content, embedding)
        VALUES (
            p_id,
            (v_chunk->>'chunk_index')::int,
            NULLIF(v_chunk->>'source_page', '')::int,
            v_chunk->>'content',
            (v_chunk->>'embedding')::vector(768)
        );
    END LOOP;

    UPDATE manual_corpus_stats
    SET total_bytes = total_bytes + p_projected_bytes,
        manual_count = manual_count + 1,
        updated_at = now()
    WHERE id = 1;

    RETURN p_id;
END;
$$;

-- Accurate, atomic delete of a manual (plus chunks via CASCADE) and stats decrement.
CREATE OR REPLACE FUNCTION delete_manual_with_stats(p_manual_id uuid)
RETURNS TABLE (file_extension text, title text)
LANGUAGE plpgsql
AS $$
DECLARE
    v_bytes bigint := 0;
    v_chunk_count int := 0;
    v_ext text;
    v_title text;
BEGIN
    SELECT m.file_extension, m.title INTO v_ext, v_title
    FROM manuals m
    WHERE m.id = p_manual_id;

    IF v_ext IS NULL THEN
        RETURN;
    END IF;

    SELECT
        COALESCE(SUM(octet_length(content)), 0) + COUNT(*) * 3072 + COUNT(*) * 200 + 500,
        COUNT(*)
    INTO v_bytes, v_chunk_count
    FROM manual_chunks
    WHERE manual_id = p_manual_id;

    DELETE FROM manuals WHERE id = p_manual_id;

    UPDATE manual_corpus_stats
    SET total_bytes = GREATEST(0, total_bytes - v_bytes),
        manual_count = GREATEST(0, manual_count - 1),
        updated_at = now()
    WHERE id = 1;

    RETURN QUERY SELECT v_ext, v_title;
END;
$$;

-- 9. System instructions table (Layer 2)
CREATE TABLE IF NOT EXISTS manual_assistant_settings (
    id SMALLINT PRIMARY KEY CHECK (id = 1),
    system_instructions TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO manual_assistant_settings (id, system_instructions) VALUES (1, '') ON CONFLICT DO NOTHING;
ALTER TABLE manual_assistant_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY manual_assistant_settings_read ON manual_assistant_settings FOR SELECT TO authenticated USING (true);