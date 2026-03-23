-- Add expiration_date column to documents table
ALTER TABLE documents
  ADD COLUMN IF NOT EXISTS expiration_date TIMESTAMPTZ DEFAULT NULL;

-- Index for efficient queries on expiration status
CREATE INDEX IF NOT EXISTS idx_documents_expiration_date
  ON documents (expiration_date)
  WHERE expiration_date IS NOT NULL;
