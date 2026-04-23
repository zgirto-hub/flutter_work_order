-- Feature 092: Department-scoped File Visibility
-- Add nullable department_id to files table + partial index
-- Do NOT backfill existing rows — NULL = global visibility (FR-010)

ALTER TABLE files
  ADD COLUMN IF NOT EXISTS department_id UUID NULL REFERENCES departments(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_files_department_id
  ON files(department_id)
  WHERE department_id IS NOT NULL;