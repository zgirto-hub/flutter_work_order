# Data Model: Civil Aviation Letter Generator

**Feature**: 026-civil-aviation-letter-gen  
**Date**: 2026-04-06

## Entities

### generated_letters (NEW TABLE)

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | Unique letter identifier |
| created_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() | Creation timestamp |
| ishara | TEXT | NOT NULL | Reference number (الإشارة) |
| tarikh | DATE | NOT NULL | Letter date (التاريخ) |
| alsayed | TEXT | NOT NULL | Recipient title (السيد) |
| almawdoo | TEXT | NOT NULL | Subject line (الموضوع) — supports multi-line |
| body_text | TEXT | NOT NULL | Body paragraph (بالإشارة للموضوع أعلاه) — multi-line |
| alasm | TEXT | NOT NULL | Signer name (الاسم) |
| signature_base64 | TEXT | NULLABLE | Signature image as base64 string |
| created_by_email | TEXT | NOT NULL | Creator's email (links to users.email) |

### payment_certificates (MODIFIED — add FK)

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| letter_id | UUID | NULLABLE, FK → generated_letters(id) | Parent cover letter reference |

## Relationships

```
generated_letters 1 ──── * payment_certificates
  (parent/cover letter)     (child, linked via letter_id)
```

- A letter can have zero or more payment certificates linked to it.
- A payment certificate can optionally belong to one letter (nullable FK).
- Deleting a letter should SET NULL on linked payment certificates (not CASCADE delete).

## Indexes

- `generated_letters`: Index on `created_by_email` for history queries filtered by user.
- `payment_certificates`: Index on `letter_id` for fetching linked certificates.

## Migration SQL

File: `supabase/migrations/20260406_generated_letters.sql`

```sql
-- Create generated_letters table
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

-- Add letter_id FK to payment_certificates
ALTER TABLE payment_certificates
    ADD COLUMN IF NOT EXISTS letter_id UUID REFERENCES generated_letters(id) ON DELETE SET NULL;

CREATE INDEX idx_payment_certificates_letter_id ON payment_certificates(letter_id);
```

## State Transitions

Letters have no status lifecycle — they are immutable records once created. The only operations are:
- **Create**: Save form field data after successful PDF generation.
- **Read**: List history, fetch individual record for regeneration.
- **No Update/Delete** in Phase 1 (immutable audit trail).
