# Data Model: Export PDF Report for Closed Work Orders

**Date**: 2026-04-04 | **Branch**: `015-export-wo-pdf`

## Overview

No new tables or migrations required. This feature reads from existing tables only.

## Existing Entities Used

### work_orders

| Field | Type | Usage in PDF |
|-------|------|-------------|
| id | UUID (PK) | Lookup key |
| job_no | string | Header + filename |
| title | string | Details section |
| description | text | Details section (wraps) |
| location | string | Details section |
| mobile_number | string | Details section |
| type | string | Details section |
| status | string | Details section + controls signature visibility |
| department_id | UUID (FK → departments) | Join to get department name |
| created_by | UUID (FK → users) | Join to get creator full name |
| created_at | timestamp | Details section |
| closed_at | timestamp | Details section |
| tech_notes | text (nullable) | Details section (omitted if null/empty) |

### work_order_assignments

| Field | Type | Usage in PDF |
|-------|------|-------------|
| work_order_id | UUID (FK → work_orders) | Join key |
| technician_id | UUID (FK → users) | Join to get technician full names |

### work_order_signatures

| Field | Type | Usage in PDF |
|-------|------|-------------|
| id | UUID (PK) | — |
| work_order_id | UUID (FK → work_orders) | Join key |
| signer_email | string | Signature section label |
| signer_role | string ('technician' or 'admin') | Determines column placement |
| signature_path | string (nullable) | File path to PNG on server |
| signed_at | timestamp | Signature section label |
| status | string ('pending', 'approved', 'rejected') | Badge + filtering |

### users

| Field | Type | Usage in PDF |
|-------|------|-------------|
| id | UUID (PK) | — |
| email | string | Lookup key for signer names |
| full_name | string | Displayed in signature + technician sections |
| role | string | RBAC enforcement |
| department_id | UUID (FK → departments) | RBAC enforcement for technicians |

### departments

| Field | Type | Usage in PDF |
|-------|------|-------------|
| id | UUID (PK) | — |
| name | string | Header subtitle |

## Query Strategy

### Primary Query: Work Order with Joins

```
work_orders → JOIN departments (name)
            → JOIN users via created_by (full_name)
            → JOIN work_order_assignments → users (full_name for each technician)
```

Uses existing `_fetch_full_work_order()` pattern from `backend/routers/work_orders.py`.

### Secondary Query: Signatures

```
work_order_signatures WHERE work_order_id = :id ORDER BY signed_at ASC
```

Then for each signature, look up signer full_name from users table by email.

### Signature Selection

Per clarification: when multiple signatures exist per role, take the **first (oldest)** non-rejected signature.

## File System Reads

| File | Location | Fallback |
|------|----------|----------|
| logo_emblem.png | backend/assets/ | Skip if missing |
| logo_civilaviation.png | backend/assets/ | Skip if missing |
| logo_newkuwait.png | backend/assets/ | Skip if missing |
| Signature PNGs | backend/uploaded_files/{signature_path} | "Signature file not found" placeholder |
