# Research: Admin Edit WO Metadata Fields

**Branch**: `019-admin-edit-wo-fields` | **Date**: 2026-04-05

## R1: Backend Update Endpoint Extension Pattern

**Decision**: Add three new optional fields to the existing `UpdateWorkOrderBody` Pydantic model and handle them conditionally in the PUT endpoint.

**Rationale**: The existing PUT endpoint at `backend/routers/work_orders.py:725` already has a two-tier authorization model (reporters get restricted fields, non-reporters get full access). Adding an admin-only tier for the three metadata fields follows the same pattern. Using optional fields (defaulting to `None`) ensures backward compatibility — existing clients that don't send these fields are unaffected.

**Alternatives considered**:
- New dedicated PATCH endpoint for metadata-only updates — rejected because it fragments the update flow and requires a separate frontend call. The existing PUT endpoint already handles role-based field restrictions.
- Separate admin-only endpoint — rejected per YAGNI; the authorization check is a simple `if` block.

## R2: Admin Authorization in Work Order Update

**Decision**: Check `user_type == 'admin'` by looking up the user role (same as `_require_admin` in `users.py:70`) within the existing update endpoint, but only when the three metadata fields are present in the payload.

**Rationale**: The existing endpoint uses `_ensure_not_reporter` and `_get_user_role` patterns. For these three fields, we need a stricter check — admin only. The check is already available via `_get_user_role(email)` which returns the user dict including `user_type`. If a non-admin sends these fields, the backend returns 403.

**Alternatives considered**:
- Silently ignoring non-admin metadata fields — rejected because it violates "Explicit Over Automatic" (Constitution II). The user should know their change was rejected.

## R3: Frontend User Picker for "Created By"

**Decision**: Create a `UserSelector` widget based on the existing `TechnicianSelector` pattern (`frontend/lib/widgets/technician_selector.dart`), but for single-select of any active user.

**Rationale**: The `TechnicianSelector` already implements a searchable bottom sheet with filtered list and selection. The "Created By" picker needs the same UX but: (a) loads all active users instead of department technicians, (b) is single-select instead of multi-select, (c) displays user name + email + role. The existing `/users` endpoint returns all users with optional filters.

**Alternatives considered**:
- Reusing `TechnicianSelector` directly with modifications — rejected because the multi-select behavior and technician-only filtering would require too many conditional flags. A clean single-purpose widget is simpler.
- Plain dropdown — rejected because the user list could be large; a searchable bottom sheet is the established pattern.

## R4: Date-Time Picker for Created At / Closed At

**Decision**: Use Flutter's built-in `showDatePicker` + `showTimePicker` combination, pre-filled with the current field value.

**Rationale**: The app already uses Material date pickers elsewhere. No external package needed. The two-step date→time flow is standard Flutter practice and matches user expectations.

**Alternatives considered**:
- Single combined date-time picker package — rejected per YAGNI; the built-in pickers are sufficient and avoid a new dependency.

## R5: Audit Logging for Metadata Changes

**Decision**: Rely on the existing `log_activity` call that already fires at the end of the update endpoint. Add a detail string when metadata fields are changed (e.g., `"Changed created_by from X to Y"`).

**Rationale**: Constitution VI requires audit logging. The existing `log_activity(user_email, "work_order", "updated", ...)` call already covers general updates. Enhancing the `detail` field to mention which metadata changed satisfies the audit requirement without a new table or logging mechanism.

**Alternatives considered**:
- New audit table for metadata changes — rejected per YAGNI and Constitution VII. The existing mechanism is sufficient.

## R6: Validation Rules

**Decision**: Implement validation at both backend (authoritative) and frontend (UX).

**Rationale**:
- `created_at` must not be in the future — compare against server UTC time on backend, device time on frontend.
- `closed_at` must be >= `created_at` — cross-field validation on both layers.
- `created_by` must reference an active user — backend validates UUID exists in `users` table.
- All three fields require `user_type == 'admin'` — backend enforces, frontend hides.

**Alternatives considered**:
- Frontend-only validation — rejected because it's bypassable. Backend must be authoritative.
