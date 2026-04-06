# API Contracts: Civil Aviation Letter Generator

**Feature**: 026-civil-aviation-letter-gen  
**Date**: 2026-04-06

## Endpoints

### POST /api/letters/generate

Generate a PDF letter and save the letter record to Supabase.

**Request Body** (JSON):
```json
{
  "ishara": "27/1/2026",
  "tarikh": "2026-01-29",
  "alsayed": "مدير إدارة الشئون المالية",
  "almawdoo": "موضوع الخطاب",
  "body_text": "بالإشارة للموضوع أعلاه، نود أن نفيدكم...",
  "alasm": "المهندس. راشد سعود العنزي",
  "signature_base64": "data:image/png;base64,iVBOR...",
  "created_by_email": "user@example.com"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| ishara | string | Yes | Reference number |
| tarikh | string (ISO date) | Yes | Letter date YYYY-MM-DD |
| alsayed | string | Yes | Recipient title |
| almawdoo | string | Yes | Subject (supports newlines) |
| body_text | string | Yes | Body paragraph (supports newlines) |
| alasm | string | Yes | Signer name |
| signature_base64 | string | No | Base64-encoded PNG/JPG signature |
| created_by_email | string | Yes | Creator's email |

**Response** (200 OK):
- Content-Type: `application/pdf`
- Content-Disposition: `attachment; filename="letter_20260129_143022.pdf"`
- Body: PDF binary stream

**Side Effect**: Saves letter record to `generated_letters` table. Returns the letter ID in response header `X-Letter-Id`.

**Errors**:
- 400: Missing required fields
- 500: PDF generation failure

---

### GET /api/letters

Fetch letter history for a user.

**Query Parameters**:
| Param | Type | Required | Notes |
|-------|------|----------|-------|
| email | string | Yes | Filter by creator email |

**Response** (200 OK):
```json
{
  "letters": [
    {
      "id": "uuid-here",
      "created_at": "2026-01-29T14:30:22Z",
      "ishara": "27/1/2026",
      "tarikh": "2026-01-29",
      "alsayed": "مدير إدارة الشئون المالية",
      "almawdoo": "موضوع الخطاب",
      "body_text": "بالإشارة للموضوع أعلاه...",
      "alasm": "المهندس. راشد سعود العنزي",
      "signature_base64": null,
      "created_by_email": "user@example.com",
      "payment_certificates": [
        { "id": "cert-uuid", "certificate_number": "PC-001", "subject": "..." }
      ]
    }
  ]
}
```

---

### POST /api/letters/{letter_id}/regenerate

Regenerate a PDF from a saved letter record.

**Path Parameters**:
| Param | Type | Notes |
|-------|------|-------|
| letter_id | UUID | Letter record ID |

**Response** (200 OK):
- Content-Type: `application/pdf`
- Content-Disposition: `attachment; filename="letter_20260129_143022.pdf"`
- Body: PDF binary stream

**Errors**:
- 404: Letter not found

---

### PATCH /api/payment-certificates/{cert_id}/link-letter

Link a payment certificate to a letter.

**Request Body** (JSON):
```json
{
  "letter_id": "uuid-here"
}
```

**Response** (200 OK):
```json
{
  "message": "Payment certificate linked to letter",
  "certificate_id": "cert-uuid",
  "letter_id": "uuid-here"
}
```

**Errors**:
- 404: Certificate or letter not found
