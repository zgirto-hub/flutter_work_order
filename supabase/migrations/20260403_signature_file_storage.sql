-- File-based signature storage
ALTER TABLE work_order_signatures
  ADD COLUMN IF NOT EXISTS signature_path TEXT;

ALTER TABLE work_order_signatures
  ALTER COLUMN signature_data DROP NOT NULL;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS signature_path TEXT;
