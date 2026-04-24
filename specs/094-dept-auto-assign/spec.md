# Feature Specification: Department Auto-Assignment on File Upload

**Feature Branch**: `094-dept-auto-assign`  
**Created**: 2026-04-24  
**Status**: Draft  
**Input**: User description: "Auto-assign the uploader's department for Technician/Reporter/Supervisor/Superintendent roles and restrict the Department field to Admin users only."

## Clarifications

### Session 2026-04-24

- Q: How should the system handle a non-admin user who has no department assigned — currently the spec says "reject the upload or treat it as an error"? → A: Prevent upload entirely — disable the upload button and show a message directing the user to contact their admin to assign a department before uploading files.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Non-Admin Uploads File with Auto-Assigned Department (Priority: P1)

A Technician, Reporter, Supervisor, or Superintendent opens the file upload screen, fills in the file details, and submits. The system automatically assigns the file to their own department without showing them any department picker. The file appears in their department's document scope immediately.

**Why this priority**: This is the core behavior change — ensuring non-admin users no longer see a department picker they should not control, and their files are correctly scoped. Without this, documents continue to default to "None (global)" and remain mis-scoped.

**Independent Test**: Can be fully tested by logging in as any non-admin role, uploading a file, and verifying in the database that the file's department_id matches the user's department_id and the department picker is absent from the upload form.

**Acceptance Scenarios**:

1. **Given** a Technician is logged in with department_id = "Maintenance", **When** they upload a file through the upload screen, **Then** the uploaded file record has department_id = "Maintenance" and no department picker was displayed.
2. **Given** a Reporter is logged in with department_id = "Operations", **When** they upload a file, **Then** the uploaded file record has department_id = "Operations" and the upload form shows no department field at all.
3. **Given** a Supervisor is logged in with department_id = "Safety", **When** they upload a file, **Then** the file is stored with department_id = "Safety" without any department selection step.

---

### User Story 2 - Admin Controls Department Assignment (Priority: P2)

An Admin opens the file upload screen and sees the "Department (optional)" dropdown as before, defaulting to "None (global)". They can select any department or leave it global, and the file is saved with their chosen department.

**Why this priority**: Admins must retain the ability to assign files across departments. This preserves existing behavior for the only role that needs it, ensuring no regression.

**Independent Test**: Can be fully tested by logging in as an Admin, uploading a file, and verifying the department dropdown is visible, defaults to "None (global)", and the selected department is persisted correctly.

**Acceptance Scenarios**:

1. **Given** an Admin is logged in, **When** they open the upload screen, **Then** the "Department (optional)" dropdown is visible and defaults to "None (global)".
2. **Given** an Admin has selected "Engineering" from the department dropdown, **When** they submit the upload, **Then** the file record has department_id = "Engineering".
3. **Given** an Admin leaves the department dropdown at "None (global)", **When** they submit the upload, **Then** the file record has department_id = null (global scope).

---

### User Story 3 - Server Rejects Spoofed Department from Non-Admin (Priority: P3)

A non-admin user sends a crafted API request with a different department_id in the payload. The server identifies the user's role, ignores the submitted department_id, and substitutes the user's own department_id from their session token.

**Why this priority**: This is a security enforcement layer that prevents privilege escalation. While the frontend hides the field, the server must be the authoritative enforcer.

**Independent Test**: Can be tested by sending a direct API request with a spoofed department_id under a non-admin authentication token and verifying the stored file uses the user's actual department_id.

**Acceptance Scenarios**:

1. **Given** a Technician with department_id = "Maintenance" sends a POST request with department_id = "Engineering", **When** the server processes the request, **Then** the file is saved with department_id = "Maintenance" (the user's own department).
2. **Given** a Reporter with department_id = "Operations" sends a POST request with department_id = null, **When** the server processes the request, **Then** the file is saved with department_id = "Operations" (the user's own department).

---

### User Story 4 - Non-Admin Without Department Cannot Upload (Priority: P3)

A Technician, Reporter, Supervisor, or Superintendent who has no department assigned in their profile attempts to upload a file. The upload button is disabled and a message directs them to contact their administrator to get a department assignment before uploading.

**Why this priority**: Prevents data integrity issues where a file would be uploaded without a valid department scope. This is a guard rail that ensures every non-admin upload has a valid department association.

**Independent Test**: Can be tested by logging in as a non-admin user with no department_id and verifying the upload button is disabled with the advisory message visible.

**Acceptance Scenarios**:

1. **Given** a Technician is logged in with no department_id assigned, **When** they open the upload screen, **Then** the upload button is disabled and a message reads "Contact your admin to assign a department before uploading files."
2. **Given** a Reporter with no department_id sends a direct POST request to the upload endpoint, **When** the server processes the request, **Then** the server rejects the upload with an error indicating the user has no department assigned.

---

### Edge Cases

- What happens when a non-admin user has no department_id assigned in their profile? The upload button is disabled on the frontend and a message directs the user to contact their admin. On the server side, the upload endpoint rejects the request with an error.
- What happens when an Admin user's session token is expired during upload? The upload fails with an authentication error — standard session expiry behavior applies.
- How does the system handle concurrent uploads from the same non-admin user? Each upload independently receives the user's department_id; no race condition risk since the value is read from the session.
- What happens if the department dropdown is pre-populated via browser cache for a non-admin user's previous session? The server enforcement guarantees the correct department regardless of any stale client-side state.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST hide the department selection field from all non-admin users (Technician, Reporter, Supervisor, Superintendent) on the file upload form.
- **FR-002**: System MUST automatically assign the uploader's department_id to the uploaded file record when the uploader is a non-admin role.
- **FR-003**: System MUST display the department dropdown to Admin users on the upload form, defaulting to "None (global)".
- **FR-004**: Admin users MUST be able to select any department or "None (global)" from the dropdown, and the selected value MUST be persisted on the file record.
- **FR-005**: The server-side upload endpoint MUST override any department_id value in the request body with the authenticated user's own department_id when the user's role is not Admin.
- **FR-006**: System MUST reject or bypass any client-supplied department_id for non-admin roles, preventing privilege escalation through crafted requests.
- **FR-007**: Existing uploaded files MUST NOT be affected by this change; their department_id values remain as-is.
- **FR-008**: When a non-admin user has no department_id assigned, the system MUST disable the upload button on the frontend and display a message directing the user to contact their admin to assign a department before uploading.
- **FR-009**: When a non-admin user with no department_id sends an upload request, the server MUST reject the request with an error indicating the user has no department assigned.

### Key Entities

- **Uploaded File/Document**: Represents a file stored in the system. Key attribute: `department_id` — links the file to a specific department scope or null for global visibility.
- **User (with Role)**: Represents the authenticated uploader. Key attributes: `role` (Admin, Technician, Reporter, Supervisor, Superintendent) and `department_id` (the department the user belongs to).
- **Department**: Represents an organizational unit. Files scoped to a department are visible only within that department; files with null department_id are globally visible.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of files uploaded by non-admin users are stored with the correct department_id matching their profile, with zero manual selection required.
- **SC-002**: Non-admin users see no department-related UI element on the upload form, reducing form complexity and eliminating mis-scoping errors.
- **SC-003**: Admin users retain full department assignment capability, with no change to their existing workflow or available options.
- **SC-004**: No crafted API request from a non-admin user can assign a file to a department other than their own — the server substitution rate is 100%.
- **SC-005**: Non-admin users without an assigned department cannot submit uploads — the upload button is visibly disabled with a clear advisory message.

## Assumptions

- Each non-admin user has exactly one department_id assigned in their profile; users without a department are blocked from uploading until an admin assigns one.
- The existing authentication/session mechanism reliably provides the user's role and department_id at the time of upload.
- The Admin role is a single, distinct role — not a composite of other permissions; the check for "is admin" is a straightforward role comparison.
- Existing file records with null department_id values (global scope) remain unchanged; this feature only affects new uploads.
- The upload form's "Department (optional)" dropdown is the only place where department is selected during upload; there are no secondary department selectors in the flow.