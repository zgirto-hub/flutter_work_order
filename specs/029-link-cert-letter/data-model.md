# Phase 1 Data Model

## Changes to existing tables

### `payment_certificates`

| Column | Type | Change | Notes |
|--------|------|--------|-------|
| `letter_id` | UUID, FK → `generated_letters(id)` | EXISTING (feature 026) | No change; `ON DELETE SET NULL` preserved. |
| `letter_link_order` | INTEGER NULL | **NEW** | Position (0-based) of this cert inside its letter's attachment list. NULL when `letter_id` is NULL. |

**Migration**: `supabase/migrations/20260407_letter_cert_link_order.sql`

```sql
ALTER TABLE payment_certificates
    ADD COLUMN IF NOT EXISTS letter_link_order INTEGER NULL;

CREATE INDEX IF NOT EXISTS idx_payment_certificates_letter_order
    ON payment_certificates(letter_id, letter_link_order);
```

### `generated_letters`

No schema change. Continues to be read via existing routes.

## Validation rules

- A payment certificate MAY have `letter_id = NULL` (unlinked).
- When `letter_id` is set, `letter_link_order` SHOULD be set to a non-negative integer.
- A given `(letter_id, letter_link_order)` pair is expected to be unique per letter but is not enforced by a DB constraint (the client assigns monotonically increasing values at save time).
- A single payment certificate MUST NOT be simultaneously attached to two letters; enforced by the backend reassignment check (research decision 4).

## State transitions

```text
 (unlinked)
    │
    ├── author attaches → letter_id=L, letter_link_order=N
    │
    ├── author detaches OR letter deleted → letter_id=NULL, letter_link_order=NULL
    │
    └── author reassigns to letter M (force) → letter_id=M, letter_link_order=K
```

## Entities surfaced to the frontend

- `LinkedPaymentCertificate { id, certificate_number, subject, letter_link_order }` — returned inside `generated_letters.payment_certificates[]` (existing field enriched with new `letter_link_order`).
