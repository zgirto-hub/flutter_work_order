# Phase 0 Research — 094-dept-auto-assign

All unknowns resolved against the current codebase (specs 092 already merged).

## Decision 1: Admin check uses `users.user_type == 'admin'`

- **Decision**: Use `user_type == 'admin'` as the sole admin gate for the upload-form picker and the server-side substitution.
- **Rationale**: Matches the permissions model documented in the constitution (three roles: reporter, technician, admin). Supervisor / superintendent are booleans layered on top of a non-admin role; they are treated as *global viewers* for file visibility (spec 092) but they are still non-admin for the purpose of *assigning* files to arbitrary departments. Giving them the picker would let a supervisor upload into a department they do not own, violating the spec's intent.
- **Alternatives considered**:
  - Reuse `is_global_viewer()` (admin OR supervisor OR superintendent) — rejected; would let supervisors upload cross-department, contradicting the spec's list of non-admin roles (Technician, Reporter, Supervisor, Superintendent).
  - Add a dedicated `can_assign_department` flag — rejected as YAGNI.

## Decision 2: Department source is `users.department_id`, not `technician_departments`

- **Decision**: For non-admin uploads, substitute `users.department_id` (nullable UUID FK on the `users` table).
- **Rationale**: The spec assumes "each non-admin user has exactly one department_id assigned in their profile." That maps directly to `users.department_id`. `technician_departments` is a many-to-many membership used for *visibility* joins (spec 092) — picking one of several would be arbitrary.
- **Alternatives considered**:
  - First row from `technician_departments` — rejected; non-deterministic.
  - All technician departments (multi-insert) — rejected; spec explicitly says single department per file.

## Decision 3: Extend `/api/departments/mine` instead of adding a new `/me` endpoint

- **Decision**: Add `is_admin: bool` and `primary_department_id: str | null` to the existing `/api/departments/mine` response.
- **Rationale**: The upload form already calls this endpoint (spec 092). Folding the new fields in avoids an extra round trip and keeps the client surface area small.
- **Alternatives considered**:
  - New `/api/users/me` endpoint — rejected as over-engineering for two extra fields.
  - Read role from the Supabase JWT client-side — rejected; role lives in the `users` table, not the JWT claims, and server would still need to enforce regardless.

## Decision 4: Server overrides silently; frontend omits field

- **Decision**: Server substitutes `department_id` for non-admins regardless of what is in the multipart form. Frontend, for non-admins, simply does not attach `department_id` to the request.
- **Rationale**: Simplest possible contract: only one path (server substitution). Frontend omission is a convenience, not a contract guarantee. Any spoofed or stale `department_id` is thrown away without error, matching spec acceptance scenarios US3-1 and US3-2.
- **Alternatives considered**:
  - Server 400 on any non-admin request that includes `department_id` — rejected; too brittle for stale client caches and adds noise to logs.

## Decision 5: No-department block — disable button on client, 400 on server

- **Decision**: When `is_admin == false && primary_department_id == null`:
  - Frontend renders the upload button disabled with helper text: *"Contact your admin to assign a department before uploading files."*
  - Server returns HTTP 400 with `{ "detail": "User has no department assigned; contact your administrator." }` if such a user bypasses the client check.
- **Rationale**: Matches clarification Q1 and FR-008 / FR-009. Both layers needed: client for UX, server for enforcement.
- **Alternatives considered**:
  - Auto-assign a "global" null department for such users — rejected; would leak their uploads into the global scope, contradicting the whole feature.
  - Create a fallback "Unassigned" department — rejected as scope creep.

## Decision 6: No migration, no new tables

- **Decision**: Reuse the `files.department_id` column added in migration `20260423000000_add_department_id_to_files.sql` (spec 092). Nothing new.
- **Rationale**: This spec is a policy change on top of existing schema. Adding a migration would violate YAGNI.

## Open Questions

None. All NEEDS CLARIFICATION resolved.
