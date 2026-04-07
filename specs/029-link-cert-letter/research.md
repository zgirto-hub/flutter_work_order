# Phase 0 Research: Link Payment Certificates to Letters

## Decisions

### 1. Where are payment-certificate PDFs produced?

**Decision**: Payment certificate PDFs are produced **client-side only** by [frontend/lib/services/pdf/payment_certificate_pdf_service.dart](../../frontend/lib/services/pdf/payment_certificate_pdf_service.dart) using the Flutter `pdf` package. There is no server-side payment-certificate PDF builder in [backend/routers/payment_certificates.py](../../backend/routers/payment_certificates.py) and no stored PDF file on disk.

**Rationale**: Reimplementing the cert PDF in reportlab would duplicate ~500 LOC of layout code and drift from the canonical client-rendered version. Storing a cached PDF on disk requires invalidation on every cert edit — adds complexity for little gain.

**Alternatives considered**:
- **Add a reportlab cert builder on backend**: rejected — high duplication, high drift risk.
- **Cache rendered cert PDFs on server disk**: rejected — needs invalidation, violates simplicity, adds write path for binary files.
- **Syncfusion / pdf_merger Flutter package for client-side merge**: rejected — heavier dep, lets duplication of letter PDF generation creep client-side; constitution prefers server reportlab for letters.

### 2. How is the merged PDF assembled?

**Decision**: **Client orchestrates, backend merges.** On export:
1. Frontend fetches the linked cert list from the letter record.
2. Frontend generates each cert PDF locally via the existing `PaymentCertificatePdfService`.
3. Frontend POSTs a multipart request to a new endpoint `POST /letters-v2/{id}/export-with-attachments` containing the letter body JSON + each cert PDF as a file part (with the cert ID as filename).
4. Backend builds the letter PDF via existing `_build_letter_pdf_v2`, then uses **pypdf** (`PdfWriter.append_pages_from_reader`) to append the cert PDFs in the order the client sent them.
5. Backend returns the single combined PDF.

**Rationale**: Reuses the canonical client-side cert generator and the canonical server-side letter generator. Only new work is a thin merge step using pypdf, which is a small, pure-Python, well-maintained dependency. Nginx 50 MB upload ceiling is plenty for a letter with a handful of cert PDFs.

**Alternatives considered**:
- **Backend fetches cert data and rebuilds PDFs in reportlab**: rejected (see above).
- **Frontend does the whole merge**: rejected — requires a new Flutter PDF-merge package; constitution prefers existing `pdf` package only.

### 3. Ordering of attached certificates in the merged output

**Decision**: Add a new column `payment_certificates.letter_link_order INTEGER NULL`. When a cert is linked to a letter, the frontend assigns the order based on the position in the attachment list. When unlinked (`letter_id = NULL`), the value is cleared. The GET endpoint returns certs ordered by `letter_link_order ASC`.

**Rationale**: Explicit, preserves author-chosen order across reloads, no change to existing FK semantics.

**Alternatives considered**:
- **Order by `created_at` of the cert**: rejected — author has no control.
- **JSONB array of cert ids on `generated_letters`**: rejected — denormalizes and duplicates source of truth.

### 4. Reassignment when a cert is already linked to another letter

**Decision**: The create/update endpoint checks if any requested cert id already has `letter_id` set to a different letter. If so, the backend returns HTTP 409 Conflict with the conflicting cert ids and the existing letter id. The frontend shows a confirmation dialog listing the conflicts; on confirmation it re-sends with a `force_reassign: true` flag, and the backend then reassigns (updates `letter_id`, resets `letter_link_order`).

**Rationale**: Satisfies FR-008 (explicit confirmation), keeps the constraint enforcement server-side as the source of truth, avoids race conditions from client-only checks.

**Alternatives considered**:
- **Block reassignment entirely**: rejected — user may legitimately move a cert.
- **Silently reassign**: rejected — violates FR-008 and Principle II (Explicit Over Automatic).

### 5. Permissions

**Decision**: Only the letter's `created_by_email` and users with role `admin` may attach/detach/export. Enforced at the backend by checking the request's authenticated user against the letter record. Matches existing Letters v2 behavior.

**Rationale**: Constitution Principle III; consistent with existing letter endpoints.

## Open Questions

None remaining — all four clarify-phase questions from the spec are resolved above.
