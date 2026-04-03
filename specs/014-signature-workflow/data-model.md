# Data Model: Signature Workflow

**Branch**: `014-signature-workflow` | **Date**: 2026-04-03

## Entity Changes

### 1. `users` Table (ALTER — add column)

| Column         | Type | Nullable | Default | Description                              |
|----------------|------|----------|---------|------------------------------------------|
| signature_path | TEXT | YES      | NULL    | Path to saved signature file under uploaded_files/ (e.g., `usersig_<user_id>.png`) |

**Notes**: One saved signature per user. Deterministic filename `usersig_<user_id>.png` — overwrites on update. Only technician and admin roles use this field.

---

### 2. `work_order_signatures` Table (ALTER — add column, modify constraint)

**Existing columns** (unchanged):
| Column           | Type         | Nullable | Default              | Description                       |
|------------------|--------------|----------|----------------------|-----------------------------------|
| id               | UUID         | NO       | gen_random_uuid()    | Primary key                       |
| work_order_id    | UUID         | NO       | —                    | FK → work_orders(id) CASCADE      |
| signer_email     | TEXT         | NO       | —                    | Email of the signer               |
| signer_role      | TEXT         | NO       | —                    | CHECK ('technician', 'admin')     |
| signed_at        | TIMESTAMPTZ  | NO       | now()                | When signature was submitted      |
| status           | TEXT         | NO       | 'pending'            | CHECK ('pending', 'approved', 'rejected') |
| rejection_reason | TEXT         | YES      | NULL                 | Reason if rejected                |

**Modified column**:
| Column         | Type | Change                    | Description                       |
|----------------|------|---------------------------|-----------------------------------|
| signature_data | TEXT | NOT NULL → NULL (nullable) | Legacy base64 data, no longer written to |

**New column**:
| Column         | Type | Nullable | Default | Description                              |
|----------------|------|----------|---------|------------------------------------------|
| signature_path | TEXT | YES      | NULL    | Path to signature file under uploaded_files/ (e.g., `sig_<uuid>.png`) |

**Notes**: New signatures write to `signature_path` only. `signature_data` kept nullable for backward compat with existing records. Migration out of scope per clarification.

---

## State Transitions

### Work Order Signature Lifecycle (Technician)

```
[No Signature] → (technician signs) → [Pending]
[Pending] → (admin approves + countersigns) → [Approved]
[Pending] → (admin rejects with reason) → [Rejected]
[Rejected] → (technician re-signs) → [Pending]  (new record; rejected record preserved)
```

### Work Order Signature Lifecycle (Admin Countersignature)

```
[No Signature] → (admin countersigns during approval) → [Approved]  (auto-approved on creation)
```

### Saved User Signature Lifecycle

```
[No Signature] → (user draws or uploads in Settings) → [Saved]
[Saved] → (user draws or uploads new one) → [Saved]  (file overwritten)
[Saved] → (user removes) → [No Signature]
```

---

## Relationships

- `work_order_signatures.work_order_id` → `work_orders.id` (CASCADE DELETE, many-to-one)
- `users.signature_path` → file in `uploaded_files/` (no FK, filesystem reference)
- `work_order_signatures.signature_path` → file in `uploaded_files/` (no FK, filesystem reference)
- Authorization: `work_order_assignments(work_order_id, technician_id)` used to verify technician can sign a specific WO

---

## Indexes

**Existing** (no changes needed):
- `idx_work_order_signatures_wo_id` on `work_order_signatures(work_order_id)` — used by per-WO and bulk lookups
- `idx_work_order_signatures_status` on `work_order_signatures(status)` — used by status filtering

---

## File Storage Conventions

| Context                | Filename Pattern              | Deterministic? | Overwrites? |
|------------------------|-------------------------------|----------------|-------------|
| Saved user signature   | `usersig_<user_id>.png`       | Yes            | Yes         |
| WO signature (drawn)   | `sig_<uuid>.png`              | No (UUID)      | No          |
| WO signature (from saved) | copies saved file to `sig_<uuid>.png` | No (UUID) | No |
