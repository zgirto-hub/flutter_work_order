-- Migration: Smart Document Preprocessing
-- Feature: 073-smart-doc-preprocess
-- Date: 2026-04-16

-- 1. Update knowledge_documents.status CHECK constraint to include 'preprocessing'
ALTER TABLE knowledge_documents DROP CONSTRAINT IF EXISTS knowledge_documents_status_check;
ALTER TABLE knowledge_documents ADD CONSTRAINT knowledge_documents_status_check
    CHECK (status IN ('pending', 'preprocessing', 'indexing', 'ready', 'failed'));

-- 2. Add raw_content column to document_chunks table
ALTER TABLE document_chunks ADD COLUMN IF NOT EXISTS raw_content TEXT;

-- 3. Add raw_content column to manual_chunks table
ALTER TABLE manual_chunks ADD COLUMN IF NOT EXISTS raw_content TEXT;

-- 4. Seed smart_preprocessing_enabled setting
INSERT INTO app_settings (key, value) VALUES
    ('smart_preprocessing_enabled', 'true')
ON CONFLICT (key) DO NOTHING;