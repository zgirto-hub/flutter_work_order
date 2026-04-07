# API Contracts

All routes live in [backend/routers/letters_v2.py](../../../backend/routers/letters_v2.py).

## Modified: `POST /letters-v2` and `PUT /letters-v2/{letter_id}`

`LetterBodyV2` gains:

```jsonc
{
  // ...existing fields...
  "payment_certificate_ids": ["uuid", "uuid"],     // ordered list, position = letter_link_order
  "force_reassign": false                           // opt-in reassignment of already-linked certs
}
```

**Behavior**:
1. Upsert the letter record (existing logic).
2. For each id in `payment_certificate_ids`:
   - Fetch the cert; if `letter_id` is set and ≠ current letter and `force_reassign` is false → collect as conflict.
3. If any conflicts → rollback letter upsert (for POST) / skip cert updates (for PUT), return HTTP 409:
   ```json
   {
     "error": "certificates_already_linked",
     "conflicts": [
       { "certificate_id": "uuid", "existing_letter_id": "uuid" }
     ]
   }
   ```
4. Otherwise: set `letter_id` + `letter_link_order = index` on each included cert; clear `letter_id` + `letter_link_order` on any cert previously linked to this letter but not in the new list.
5. Build letter PDF via existing `_build_letter_pdf_v2` and return as today (still a single letter-only PDF; the merged export has its own endpoint).

## Modified: `GET /letters-v2`

Existing response already attaches `payment_certificates[]`. Extend the select to include `letter_link_order` and ORDER BY `letter_link_order ASC`.

## New: `POST /letters-v2/{letter_id}/export-with-attachments`

**Request**: multipart/form-data
- `letter_body` (string, JSON) — current `LetterBodyV2` payload (used to rebuild the letter PDF with in-progress edits).
- `cert_<uuid>` (file, application/pdf) — zero or more cert PDFs, one per linked cert. Filename = cert id.
- `order` (string, JSON) — ordered list of cert ids defining append order.

**Response**: `application/pdf` — the merged PDF (letter pages followed by cert pages in `order`).

**Errors**:
- 403 if requester is not the letter author and not admin.
- 404 if letter not found.
- 422 if `order` contains ids that have no corresponding file part.
- 400 if any uploaded part fails to parse as a PDF (the offending cert id is listed; merge still succeeds for the remainder if `best_effort=true` query param is set, per FR-010).

**Implementation notes**:
- Use `pypdf.PdfWriter` with `append(PdfReader(io.BytesIO(cert_bytes)))`.
- Letter PDF is built fresh from `letter_body` so the export reflects unsaved edits.
- Log `exported` activity via `log_activity`.

## Unchanged

- `DELETE /letters-v2/{letter_id}` — existing unlink-on-delete logic preserved (also resets `letter_link_order`).
- `POST /letters-v2/{letter_id}/regenerate` — unchanged (returns letter-only PDF). The merged-export endpoint is the way to get a combined PDF.
