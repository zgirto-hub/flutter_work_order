# API Contracts: 016-signature-approval-chain

## Modified Endpoints

### POST /work-orders/{work_order_id}/signatures

**Change**: `signer_role` now accepts `'technician'` only (not `'admin'`). On tech sign, sets `work_orders.signature_status = 'tech_signed'`. Calls `_advance_chain()` which notifies supervisors.

**New behavior**:
- Checks `signature_status == 'unsigned'` or `'rejected'` before allowing tech sign
- On re-sign after rejection: clears all non-rejected signatures, resets chain
- Returns 409 if `signature_status` doesn't match expected state

**Request body** (unchanged shape):
```json
{
  "signer_email": "tech@example.com",
  "signer_role": "technician",
  "signature_data": "base64...",
  "use_saved": false
}
```

**Response** (unchanged shape):
```json
{ "signature": { "id": "uuid", "status": "pending", ... } }
```

### PATCH /work-orders/{work_order_id}/signatures/{signature_id}

**Change**: Authorization completely reworked. No longer admin-only. Now requires user with matching `approval_level` for the current chain step.

**New authorization logic**:
1. If caller is admin → 403 "Admin cannot approve signatures"
2. Get WO `signature_status` → resolve required `approval_level`
3. If caller's `approval_level` != required level → 403
4. If level 1 (supervisor): verify caller's departments include WO department
5. If `signature_status` already advanced → 409 "Already approved at this level"
6. Self-approval check: if caller == technician who signed → 403

**Request body** (unchanged):
```json
{
  "status": "approved" | "rejected",
  "rejection_reason": "optional text"
}
```

**Response**:
```json
{ "status": "approved", "signature_status": "supervisor_approved" }
```

### GET /work-orders/{work_order_id}/signatures

**Change**: No authorization change. Returns all signatures including the new `signer_role` values ('supervisor', 'superintendent').

### GET /signatures/bulk?work_order_ids=...

**Change**: Response now includes `signature_status` from `work_orders` table.

**Response** (extended):
```json
{
  "statuses": {
    "wo-uuid-1": {
      "signature_status": "tech_signed",
      "technician_signed": true,
      "technician_status": "pending",
      "supervisor_signed": false,
      "supervisor_status": null,
      "superintendent_signed": false,
      "superintendent_status": null
    }
  }
}
```

## New Endpoints

### PATCH /users/{user_id}/approval-role

**Description**: Admin sets approval role for a user.

**Query params**: `admin_email` (required) — caller must be admin.

**Request body**:
```json
{
  "approval_level": 1,
  "department_ids": ["dept-uuid-1", "dept-uuid-2"]
}
```

- `approval_level`: `null` (none), `1` (supervisor), `2` (superintendent)
- `department_ids`: Required when `approval_level = 1`, ignored otherwise

**Authorization**: Admin only. Admin cannot set their own approval role.

**Response**:
```json
{
  "user_id": "uuid",
  "approval_level": 1,
  "is_supervisor": true,
  "is_superintendent": false,
  "department_ids": ["dept-uuid-1", "dept-uuid-2"]
}
```

**Error cases**:
- 403: Non-admin caller
- 403: Admin trying to set own approval role
- 400: `approval_level = 1` without `department_ids`
- 404: User not found

### GET /users?is_supervisor=true&department_id=...

**Description**: Extend existing list users endpoint with optional filters.

**New query params**:
- `is_supervisor` (bool, optional)
- `is_superintendent` (bool, optional)
- `department_id` (string, optional) — filter supervisors by department

### GET /work-orders/pending-approvals

**Description**: Returns WOs awaiting the caller's approval action.

**Query params**: `user_email` (required)

**Authorization**: Only users with `approval_level != null`. Returns 403 for others.

**Logic**:
- If `approval_level = 1` (supervisor): WOs where `signature_status = 'tech_signed'` AND WO department IN caller's `technician_departments`
- If `approval_level = 2` (superintendent): WOs where `signature_status = 'supervisor_approved'`

**Response**:
```json
{
  "work_orders": [
    {
      "id": "uuid",
      "job_no": "WO-001",
      "title": "...",
      "department_name": "...",
      "signature_status": "tech_signed",
      "created_at": "...",
      "assigned_technician": { "id": "uuid", "full_name": "...", "email": "..." }
    }
  ]
}
```
