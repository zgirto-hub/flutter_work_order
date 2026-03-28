-- Payment certificates table
CREATE TABLE payment_certificates (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    certificate_number      TEXT NOT NULL,
    subject                 TEXT,
    contract_number         TEXT,
    invoice_number          TEXT,
    invoice_amount          NUMERIC DEFAULT 0,
    currency                TEXT DEFAULT 'USD',
    period_from             DATE,
    period_to               DATE,
    executing_entity        TEXT,
    supervising_entity      TEXT,
    original_value_usd      NUMERIC DEFAULT 0,
    original_value_kwd      NUMERIC DEFAULT 0,
    additional_works        TEXT,
    contract_signing_date   DATE,
    contract_duration       TEXT,
    contract_start_date     DATE,
    contract_end_date       DATE,
    work_commencement_date  DATE,
    renewal_info            TEXT,
    renewal_expiry_date     DATE,
    payment_rows            JSONB DEFAULT '[]'::jsonb,
    attachment_checklist    JSONB DEFAULT '{}'::jsonb,
    dept_head               TEXT,
    controller              TEXT,
    director                TEXT,
    auditor                 TEXT,
    created_by              TEXT,
    created_by_email        TEXT,
    created_at              TIMESTAMPTZ DEFAULT now(),
    updated_at              TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_payment_certificates_created_by ON payment_certificates(created_by_email);
CREATE INDEX idx_payment_certificates_cert_no ON payment_certificates(certificate_number);
