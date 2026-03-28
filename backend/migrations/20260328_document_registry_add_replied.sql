-- Add replied column to existing document_registry table
ALTER TABLE document_registry ADD COLUMN IF NOT EXISTS replied BOOLEAN NOT NULL DEFAULT false;
