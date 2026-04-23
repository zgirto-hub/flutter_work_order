# Quickstart / Manual Test Plan

## Prerequisites

1. Supabase: apply migration `supabase/migrations/20260423000000_add_department_id_to_files.sql`.
2. Backend restart: `sudo systemctl restart document_server.service` (routes changed — FR mandated).
3. Frontend: rebuild and deploy via `scripts/deploy_frontend.sh`.

## Test users

| Email | Role | Departments |
|-------|------|-------------|
| `salah@admin.com` | admin | N/A (global) |
| `super@test.com` | technician + `is_supervisor=true` | Electrical (global viewer) |
| `tech_a@test.com` | technician | Electrical |
| `tech_b@test.com` | technician | Mechanical |
| `tech_ab@test.com` | technician | Electrical, Mechanical |
| `reporter@test.com` | reporter | Electrical |

If these users don't exist, create via the existing Admin → Users screen.

## Setup fixtures

As admin, upload three test files:

| Title | Department |
|-------|------------|
| `Global-Policy.pdf` | *(blank — global)* |
| `Electrical-SOP.pdf` | Electrical |
| `Mechanical-SOP.pdf` | Mechanical |

## Acceptance tests

### T1 — Scoped viewer sees own + global (Story 1)

Login as `tech_a@test.com`. Open Files screen. **Expect**: exactly 2 files visible — `Global-Policy.pdf` and `Electrical-SOP.pdf`. `Mechanical-SOP.pdf` MUST be absent.

### T2 — Direct fetch of hidden file is denied (Story 1, SC-006)

As `tech_a@test.com`, hit `GET /api/files/<id of Mechanical-SOP>` directly. **Expect**: 403.

### T3 — Multi-department user sees both

Login as `tech_ab@test.com`. **Expect**: all 3 files visible (Global + Electrical + Mechanical).

### T4 — Global viewer sees everything (Story 3)

Login as `super@test.com`. **Expect**: all 3 files. Repeat as `salah@admin.com` — same result.

### T5 — Admin upload picker (Story 2)

As admin, open upload dialog. **Expect**: "Department (optional)" dropdown, default empty. Upload `Test-E.pdf` with Electrical selected. Log in as `tech_b@test.com`; `Test-E.pdf` MUST NOT appear. Log in as `tech_a@test.com`; it MUST appear.

### T6 — Admin upload without department → global

As admin, upload `Test-Any.pdf` with no department. All users see it.

### T7 — Badge on admin view (Story 2, acceptance 4)

As admin, open Files screen. `Electrical-SOP.pdf` MUST show a small department badge ("Electrical"). `Global-Policy.pdf` MUST have no badge.

### T8 — Scope label for scoped users (Story 4)

As `tech_a@test.com`, Files screen header MUST show a label like "Showing files for Electrical". As `tech_ab@test.com`, label MUST list both departments. As admin, NO label.

### T9 — Department edit post-upload (FR-017)

As admin, open `Electrical-SOP.pdf` details and change its department to Mechanical. Immediately, `tech_a@test.com` MUST NOT see it anymore; `tech_b@test.com` MUST see it. Check `user_activity_log` for a row with category `file`, action `updated`, detail mentioning the dept change.

### T10 — Per-user share override (FR-016)

As admin, share `Mechanical-SOP.pdf` with `tech_a@test.com` via the existing Share action. **Expect**: `tech_a@test.com` now sees `Mechanical-SOP.pdf` in their list despite not being in Mechanical.

### T11 — Department deletion fallback (FR-015)

In Supabase (as admin), delete the Electrical department row (or test via a throwaway department). Files previously scoped to it MUST now appear to every user (visibility reverts to global). No file is hidden or deleted.

### T12 — Backwards compatibility (SC-003)

Confirm any pre-existing file uploaded before this migration has `department_id = NULL` and is visible to every user.

## Rollback

If issues: revert by running the reverse migration (drop column + index). The backend endpoints are additive except for the list migration on the frontend — if rolling back, also redeploy the prior frontend build (direct Supabase listing).
