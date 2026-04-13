-- Feedback Loop AI Assistant: Migration
-- Feature: 048-feedback-loop-ai-assistant
-- Created: 2026-04-13

-- 1. Create `answer_ratings` table
CREATE TABLE IF NOT EXISTS answer_ratings (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    question_text TEXT NOT NULL,
    answer_text TEXT NOT NULL,
    source_chunks JSONB NOT NULL DEFAULT '[]',
    rating TEXT NOT NULL CHECK (rating IN ('positive', 'negative')),
    review_status TEXT CHECK (review_status IN ('pending', 'approved', 'corrected')),
    rater_email TEXT NOT NULL,
    manual_id UUID REFERENCES manuals(id) ON DELETE SET NULL,
    model_used TEXT,
    session_summary TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (id)
);

-- Indexes for answer_ratings
CREATE INDEX IF NOT EXISTS idx_answer_ratings_review ON answer_ratings (review_status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_answer_ratings_rater ON answer_ratings (rater_email);

-- 2. Create `validated_qa` table
CREATE TABLE IF NOT EXISTS validated_qa (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    question_text TEXT NOT NULL,
    validated_answer TEXT NOT NULL,
    question_embedding VECTOR(768) NOT NULL,
    equipment_type TEXT,
    fault_code TEXT,
    procedure_ref TEXT,
    manual_ids UUID[] DEFAULT '{}',
    source_chunks JSONB NOT NULL DEFAULT '[]',
    validated_by TEXT NOT NULL,
    validated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    thumbs_up_count INTEGER NOT NULL DEFAULT 0,
    thumbs_down_count INTEGER NOT NULL DEFAULT 0,
    is_reflagged BOOLEAN NOT NULL DEFAULT FALSE,
    rating_id UUID NOT NULL REFERENCES answer_ratings(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (id)
);

-- Indexes for validated_qa
CREATE INDEX IF NOT EXISTS idx_validated_qa_embedding_ivfflat
    ON validated_qa USING ivfflat (question_embedding vector_cosine_ops) WITH (lists = 10);
CREATE INDEX IF NOT EXISTS idx_validated_qa_reflagged ON validated_qa (is_reflagged) WHERE is_reflagged = TRUE;

-- Row Level Security policies
ALTER TABLE answer_ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE validated_qa ENABLE ROW LEVEL SECURITY;

-- answer_ratings: any authenticated user can insert, service role can read all
CREATE POLICY answer_ratings_authenticated_insert ON answer_ratings
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY answer_ratings_service_read ON answer_ratings
    FOR SELECT TO service_role USING (true);

CREATE POLICY answer_ratings_service_update ON answer_ratings
    FOR UPDATE TO service_role USING (true);

-- validated_qa: service role full access, authenticated can read for display
CREATE POLICY validated_qa_service_all ON validated_qa
    FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY validated_qa_authenticated_read ON validated_qa
    FOR SELECT TO authenticated USING (true);

-- 3. Vector search RPC for validated_qa
CREATE OR REPLACE FUNCTION search_validated_qa(
    q_embedding VECTOR(768),
    match_count INT DEFAULT 5
)
RETURNS TABLE (
    id UUID,
    question_text TEXT,
    validated_answer TEXT,
    equipment_type TEXT,
    source_chunks JSONB,
    validated_by TEXT,
    validated_at TIMESTAMPTZ,
    thumbs_up_count INTEGER,
    thumbs_down_count INTEGER,
    distance FLOAT
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        vq.id,
        vq.question_text,
        vq.validated_answer,
        vq.equipment_type,
        vq.source_chunks,
        vq.validated_by,
        vq.validated_at,
        vq.thumbs_up_count,
        vq.thumbs_down_count,
        (vq.question_embedding <=> q_embedding) AS distance
    FROM validated_qa vq
    WHERE vq.is_reflagged = FALSE
    ORDER BY vq.question_embedding <=> q_embedding
    LIMIT match_count;
END;
$$;

-- 4. Atomic increment RPC for validated_qa rating counts
CREATE OR REPLACE FUNCTION increment_validated_rating(
    row_id UUID,
    col_name TEXT
)
RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    IF col_name = 'thumbs_up_count' THEN
        UPDATE validated_qa SET thumbs_up_count = thumbs_up_count + 1 WHERE id = row_id;
    ELSIF col_name = 'thumbs_down_count' THEN
        UPDATE validated_qa SET thumbs_down_count = thumbs_down_count + 1 WHERE id = row_id;
    ELSE
        RAISE EXCEPTION 'Invalid column name: %', col_name;
    END IF;
END;
$$;
