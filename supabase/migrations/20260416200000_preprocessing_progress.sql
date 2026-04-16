-- Migration: Add preprocessing progress tracking
-- Feature: 073-smart-doc-preprocess (progress bar)
-- Date: 2026-04-16

ALTER TABLE knowledge_documents ADD COLUMN IF NOT EXISTS preprocessing_progress INT DEFAULT 0;
