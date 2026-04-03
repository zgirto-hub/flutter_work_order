# API Contract: Export Work Order PDF

**Date**: 2026-04-04 | **Branch**: `015-export-wo-pdf`

## POST /api/reports/work-order-pdf/{work_order_id}

Generates a PDF report for the specified work order and returns it as a binary stream.

### Request

**Method**: POST
**Path**: `/api/reports/work-order-pdf/{work_order_id}`

**Path Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| work_order_id | string (UUID) | Yes | ID of the work order to export |

**Query Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| email | string | Yes | Email of the requesting user (for RBAC) |
| user_role | string | Yes | Role of the requesting user: `reporter`, `technician`, or `admin` |

### Response

**Success (200)**:

| Header | Value |
|--------|-------|
| Content-Type | application/pdf |
| Content-Disposition | attachment; filename="WO-{job_no}-report.pdf" |

Body: Raw PDF bytes

**Error Responses**:

| Status | Condition | Response Body |
|--------|-----------|---------------|
| 404 | Work order not found | `{"detail": "Work order not found"}` |
| 403 | User does not have access to this work order | `{"detail": "Access denied"}` |
| 500 | PDF generation failed | `{"detail": "Failed to generate PDF: {error}"}` |

### Authorization Rules

| User Role | Access Scope |
|-----------|-------------|
| reporter | Only work orders where `created_by` matches the user's ID |
| technician | Only work orders in the user's department |
| admin | All work orders |

### Behavior Notes

- Works for any work order status (not just Closed)
- For non-closed WOs: signature section shows "Awaiting Signature" placeholders
- Missing signature image files: renders "Signature file not found" in the signature box
- Missing logo files: skips the logo gracefully
- Empty tech notes: omits the tech notes row
- Logs `pdf_exported` activity after successful generation
