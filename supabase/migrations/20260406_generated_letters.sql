CREATE TABLE IF NOT EXISTS generated_letters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ishara TEXT NOT NULL,
    tarikh DATE NOT NULL,
    alsayed TEXT NOT NULL,
    almawdoo TEXT NOT NULL,
    body_text TEXT NOT NULL,
    alasm TEXT NOT NULL,
    signature_base64 TEXT,
    created_by_email TEXT NOT NULL
);
CREATE INDEX idx_generated_letters_created_by ON generated_letters(created_by_email);
ALTER TABLE payment_certificates
    ADD COLUMN IF NOT EXISTS letter_id UUID REFERENCES generated_letters(id) ON DELETE SET NULL;
CREATE INDEX idx_payment_certificates_letter_id ON payment_certificates(letter_id);