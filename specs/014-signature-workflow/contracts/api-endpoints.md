# API Contracts: Signature Workflow

**Branch**: `014-signature-workflow` | **Date**: 2026-04-03

## Modified Endpoints

### POST `/api/work-orders/{work_order_id}/signatures` (MODIFY)

**Change**: Accept base64 in body, backend saves to file. Return `signature_path` instead of `signature_data`. Add `use_saved: true` option. Add activity logging.

**Request Body**:
```json
{
  "signer_email": "tech@example.com",
  "signer_role": "technician",
  "signature_data": "<base64 PNG>",    // required if use_saved is false/absent
  "use_saved": false                    // optional, if true uses user's saved signature
}
```

**Response** (200):
```json
{
  "signature": {
    "id": "uuid",
    "work_order_id": "uuid",
    "signer_email": "tech@example.com",
    "signer_role": "technician",
    "signature_path": "/files/sig_abc123.png",
    "signed_at": "2026-04-03T10:00:00Z",
    "status": "pending",
    "rejection_reason": null
  }
}
```

**Errors**: 400 (not Closed, already signed), 403 (not assigned, wrong role), 404 (WO not found)

**Activity log**: `log_activity(email, "work_order", "signature_submitted", target_label=wo_title, target_id=work_order_id)`

---

### PATCH `/api/work-orders/{work_order_id}/signatures/{signature_id}` (MODIFY)

**Change**: Add activity logging. Response unchanged.

**Activity log**:
- Approve: `log_activity(email, "work_order", "signature_approved", target_label=wo_title, target_id=work_order_id)`
- Reject: `log_activity(email, "work_order", "signature_rejected", target_label=wo_title, target_id=work_order_id)`

---

### GET `/api/work-orders/{work_order_id}/signatures` (MODIFY)

**Change**: Return `signature_path` instead of `signature_data`.

**Response** (200):
```json
{
  "signatures": [
    {
      "id": "uuid",
      "work_order_id": "uuid",
      "signer_email": "tech@example.com",
      "signer_role": "technician",
      "signature_path": "/files/sig_abc123.png",
      "signed_at": "2026-04-03T10:00:00Z",
      "status": "approved",
      "rejection_reason": null
    }
  ]
}
```

---

## New Endpoints

### GET `/api/signatures/bulk`

**Purpose**: Fetch signature status for multiple work orders in one call (fixes N+1).

**Query Parameters**:
- `work_order_ids` (required): Comma-separated UUIDs

**Response** (200):
```json
{
  "statuses": {
    "wo-uuid-1": {
      "technician_signed": true,
      "technician_status": "approved",
      "admin_signed": true,
      "admin_status": "approved"
    },
    "wo-uuid-2": {
      "technician_signed": true,
      "technician_status": "pending",
      "admin_signed": false,
      "admin_status": null
    },
    "wo-uuid-3": {
      "technician_signed": false,
      "technician_status": null,
      "admin_signed": false,
      "admin_status": null
    }
  }
}
```

**Errors**: 400 (missing work_order_ids)

---

### POST `/api/users/{user_id}/signature`

**Purpose**: Upload or draw a saved signature for a user (Settings).

**Request**: `multipart/form-data`
- `file` (optional): PNG/JPG image file
- `signature_data` (optional): base64 PNG (from canvas draw)
- `user_email` (required): for authorization

One of `file` or `signature_data` must be provided.

**Response** (200):
```json
{
  "signature_path": "/files/usersig_<user_id>.png"
}
```

**Errors**: 400 (no file/data provided, invalid format), 403 (not the user, not technician/admin)

**Activity log**: `log_activity(email, "work_order", "saved_signature_updated", target_label=full_name, target_id=user_id)`

---

### GET `/api/users/{user_id}/signature`

**Purpose**: Get user's saved signature path.

**Query Parameters**:
- `user_email` (required): for authorization

**Response** (200):
```json
{
  "signature_path": "/files/usersig_<user_id>.png"
}
```

**Response** (200, no saved signature):
```json
{
  "signature_path": null
}
```

---

### DELETE `/api/users/{user_id}/signature`

**Purpose**: Remove user's saved signature.

**Query Parameters**:
- `user_email` (required): for authorization

**Response** (200):
```json
{
  "status": "deleted"
}
```

**Errors**: 403 (not the user, not admin), 404 (no saved signature)

**Side effects**: Deletes file from `uploaded_files/`, sets `users.signature_path` to NULL.
