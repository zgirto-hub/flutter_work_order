CREATE TABLE IF NOT EXISTS document_registry (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_name   TEXT NOT NULL,
    document_number TEXT NOT NULL,
    date            DATE NOT NULL,
    created_by      TEXT NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_document_registry_created_by ON document_registry(created_by);
CREATE INDEX IF NOT EXISTS idx_document_registry_date ON document_registry(date);
