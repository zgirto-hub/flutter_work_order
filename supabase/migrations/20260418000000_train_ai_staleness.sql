-- Add staleness tracking to validated_qa
ALTER TABLE validated_qa
  ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ DEFAULT now(),
  ADD COLUMN IF NOT EXISTS source_manual_id UUID REFERENCES manuals(id) ON DELETE SET NULL;

UPDATE validated_qa SET verified_at = created_at WHERE verified_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_validated_qa_source_manual
  ON validated_qa(source_manual_id) WHERE source_manual_id IS NOT NULL;

-- Add updated_at to manuals for staleness trigger
ALTER TABLE manuals
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

UPDATE manuals SET updated_at = created_at WHERE updated_at IS NULL;