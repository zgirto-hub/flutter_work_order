# Feature Specification: Department-scoped File Visibility

**Feature Branch**: `092-dept-file-visibility`
**Created**: 2026-04-23
**Status**: Draft
**Input**: User description: "Department-scoped file visibility for Technician and Reporter roles — restrict Files/Documents visibility by department (nullable = global); Admin/Supervisor/Superintendent see all; Technician/Reporter see global + own departments; admin upload gains optional department picker; add a dept badge on file cards and a contextual label on the documents screen."

## Clarifications

### Session 2026-04-23

- Q: Does the existing per-user file-sharing mechanism (explicit share of a specific file with a specific user) override department scope? → A: Yes — per-user shares bypass department scope; an explicitly-shared file is visible to the recipient even if they are not a member of the file's department.
- Q: Who can assign a department to a folder, and when? → A: Folders cannot be scoped in this release — only individual files carry a department association. Folder-level department scope and transitive inheritance are dropped from this spec.
- Q: Can an admin change a file's department after upload? → A: Yes — admin can edit a single file's department (including clearing it back to global) via a per-file action; bulk re-assignment remains out of scope.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Technician sees only their department's files (Priority: P1)

A technician opens the Files/Documents screen. They see only files and folders that have been marked as belonging to one of their departments, plus any files that are globally shared (no department assigned). Files belonging to other departments are invisible to them — they cannot browse, search, or open them.

**Why this priority**: This is the core intent of the feature. Without this, the feature delivers no value. Protecting department-scoped content is the primary business driver.

**Independent Test**: Assign a test technician to exactly one department. Upload three files: one to that department, one to another department, one with no department. Open the documents screen as the technician and verify the list contains exactly the two visible files (own department + global), and the third-department file is neither listed nor retrievable by direct ID.

**Acceptance Scenarios**:

1. **Given** a technician is a member of Department A only, **When** they open the Files screen, **Then** they see only files whose department is A or whose department is empty (global).
2. **Given** a technician attempts to fetch a file that belongs to Department B (not theirs), **When** the request is made directly by the file's identifier, **Then** access is denied.
3. **Given** a file belonging to Department B sits inside a folder that a Department-A technician can otherwise browse, **When** the technician opens that folder, **Then** the Department-B file is omitted from the folder's contents (scope is enforced per-file, not per-folder).

---

### User Story 2 - Admin uploads a file and optionally scopes it to a department (Priority: P1)

An admin uploads a file through the documents screen. During upload, they see an optional "Department" selector. If they pick a department, the file becomes visible only to members of that department (plus admin-tier viewers). If they leave it blank, the file is globally visible.

**Why this priority**: Without the upload-time department picker, admins have no way to create scoped files, so Story 1 cannot be exercised in production. This is the authoring half of the feature.

**Independent Test**: Log in as admin, upload two files — one with a department selected, one without. Verify the scoped file appears only for members of that department, and the un-scoped file appears for everyone.

**Acceptance Scenarios**:

1. **Given** an admin is uploading a file, **When** they open the upload form, **Then** a "Department (optional)" selector is present and defaults to empty.
2. **Given** an admin selects a department during upload, **When** the upload completes, **Then** the file is stored with that department association and visible only to that department's members and admin-tier users.
3. **Given** an admin leaves the department field empty, **When** the upload completes, **Then** the file is stored as global and visible to all users.
4. **Given** the admin views the documents list, **When** a file has a department assigned, **Then** a small department badge appears on the file card; when no department is assigned, no badge is shown.

---

### User Story 3 - Supervisors and Superintendents retain full visibility (Priority: P1)

Users flagged as supervisor or superintendent, and the admin role, see all files and folders regardless of department scope, identical to admin. This ensures oversight roles are not accidentally blocked from content during day-to-day inspection.

**Why this priority**: This role carve-out prevents the feature from silently breaking the workflow of oversight users. It must ship in the first release to avoid regressions for those roles.

**Independent Test**: Log in as a supervisor assigned to Department A. Verify they can see files scoped to Department B and Department C in addition to their own department and globals.

**Acceptance Scenarios**:

1. **Given** a user has the supervisor flag, **When** they open the Files screen, **Then** they see every file, across all departments, plus globals.
2. **Given** a user has the superintendent flag, **When** they open the Files screen, **Then** they see every file, across all departments, plus globals.
3. **Given** an admin opens the Files screen, **When** files span multiple departments, **Then** all files are listed regardless of department.

---

### User Story 4 - Technician/Reporter sees a contextual label showing their scope (Priority: P2)

When a technician or reporter views the documents screen, a small contextual label (e.g., "Showing files for Electrical") appears under the header so they understand why their view differs from admin. Users with multiple departments see a combined label (e.g., "Showing files for Electrical, Mechanical"). Admin-tier viewers do not see this label.

**Why this priority**: Reduces confusion and support load by making the visibility rule self-explanatory; not critical for correctness, so it ships after the enforcement is in place.

**Independent Test**: As a technician in Department A, verify the label reads "Showing files for [Department A name]". As a technician in A and B, verify the label lists both. As an admin, verify no such label is shown.

**Acceptance Scenarios**:

1. **Given** a technician is a member of one department, **When** they open the Files screen, **Then** a label under the header names that department.
2. **Given** a technician is a member of multiple departments, **When** they open the Files screen, **Then** the label lists all their departments.
3. **Given** a user has admin, supervisor, or superintendent privileges, **When** they open the Files screen, **Then** no scope label is shown (they are global viewers).

---

### Edge Cases

- **User has no department assigned**: A technician or reporter not linked to any department sees only global files. No error is shown; the list simply contains globals.
- **Department is deleted**: When a department is removed, files and folders previously scoped to it revert to global visibility rather than becoming inaccessible.
- **Scoped file inside a browsable folder**: Since folders are not department-scoped in this release, a technician may navigate into any folder they can see, but scoped files inside that folder are filtered out individually — visibility is determined per-file, not per-folder.
- **Legacy files created before this feature**: All pre-existing files remain visible to everyone (treated as global) and require no migration.
- **Admin removes department from an already-uploaded file**: Out of scope — bulk re-assignment is not supported in this release.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST allow each document to optionally be associated with a single department. A document with no department association is treated as globally visible. Folders are NOT department-scoped in this release; visibility is evaluated per-document.
- **FR-002**: The system MUST grant users with admin role, supervisor flag, or superintendent flag unrestricted visibility across all documents regardless of department association.
- **FR-003**: The system MUST restrict users with technician or reporter role to viewing only documents that are (a) globally visible, or (b) associated with a department the user belongs to via the existing department-membership relationship.
- **FR-004**: The system MUST enforce the visibility rule on every document-listing, document-retrieval, and document-search path, so that a restricted user cannot retrieve a hidden document by direct identifier, search, or any other read path.
- **FR-005**: The system MUST evaluate department visibility on a per-document basis regardless of the folder a document is nested in; a user who can see a folder may still have specific documents inside that folder hidden from them based on department scope.
- **FR-006**: The system MUST allow an admin, during file upload, to optionally select one department from the existing departments list. The selected department MUST be persisted with the uploaded document.
- **FR-007**: The system MUST leave the department association blank when the admin does not select one, resulting in a globally visible file.
- **FR-008**: The system MUST validate the submitted department selection during upload against the existing set of departments; invalid selections MUST be rejected.
- **FR-009**: The system MUST record the department selection in the existing activity-log entry when it is present on upload.
- **FR-010**: The system MUST preserve existing files by treating any pre-existing document without a department association as globally visible; no data migration or backfill is required.
- **FR-011**: The system MUST expose a way for the client to retrieve the current user's effective department list for display purposes, including a signal that identifies admin-tier viewers who have global visibility.
- **FR-012**: The documents screen MUST display a small contextual label to technician and reporter users indicating which department(s) their view is scoped to. Admin-tier viewers MUST NOT see this label.
- **FR-013**: The documents list, when viewed by an admin, MUST visually indicate which files are scoped to a department by showing a small department badge on each scoped file; globally visible files MUST have no badge.
- **FR-014**: The system MUST restrict the upload action to admins only (unchanged from today); technicians and reporters MUST NOT be able to upload regardless of department.
- **FR-015**: If a department that is assigned to one or more files is deleted, the system MUST gracefully convert those associations to "global" (no department) so the content remains visible to everyone rather than becoming orphaned.
- **FR-016**: The system MUST treat an explicit per-user file share as an override of department scope: if a specific file has been shared with a specific user through the existing per-user sharing mechanism, that user MUST be able to view and retrieve the file even when they are not a member of the file's department.
- **FR-017**: The system MUST allow an admin to change a single existing file's department association after upload, including clearing it to "global". The change MUST validate the new department against the existing set of departments, take immediate effect on visibility for all users, and be recorded in the activity log. Only admins MUST be able to perform this action.

### Key Entities *(include if feature involves data)*

- **Document**: An uploaded file. Gains an optional association to a single Department. Absence of the association means the document is globally visible.
- **Folder**: A grouping of documents. Folders themselves are NOT department-scoped in this release; they remain globally browsable, and department scope is applied only to the documents contained within them.
- **Department**: An existing organizational unit. Used as the scope label for documents and folders.
- **User–Department Membership**: The existing link between a user and one or more departments. This link is the authoritative source for determining which scoped content a technician or reporter can see, regardless of their specific role label.
- **User Role / Flags**: Existing attributes on users — role (admin, technician, reporter), plus supervisor and superintendent flags — that determine whether the user is a "global viewer" (bypasses department filtering) or a "scoped viewer".

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After release, a technician or reporter viewing the documents screen sees zero files belonging to departments they are not a member of, across 100% of list, search, and direct-access paths.
- **SC-002**: Admin-tier users (admin, supervisor, superintendent) continue to see 100% of existing files after release, with no file becoming unexpectedly hidden from them.
- **SC-003**: 100% of pre-existing files remain visible to all users after release (backwards compatibility — no file becomes inaccessible due to the rollout).
- **SC-004**: Admins can successfully scope a new upload to a department in under 15 seconds of additional interaction compared to an unscoped upload.
- **SC-005**: A technician who is a member of a department can open the documents screen and identify which department(s) they are currently scoped to within 5 seconds of the screen loading, without asking a colleague or reading documentation.
- **SC-006**: Attempting to retrieve a restricted file by its identifier returns an access-denied outcome in 100% of cases for non-privileged users.

## Assumptions

- The existing department-membership relationship is authoritative for both technicians and supervisors; no extension to that link is required.
- Admin, supervisor, and superintendent are collectively treated as "global viewers"; no finer-grained variation among them is needed for this feature.
- Upload remains admin-only; no new upload permissions are introduced for other roles.
- The per-user file-sharing mechanism that currently exists (sharing a specific file with a specific user) remains untouched; an explicit per-user share overrides department scope (see FR-016).
- Backwards compatibility is preserved by treating the absence of a department association as "global" — no migration of existing rows is required.
- Filtering is performed server-side; clients display whatever the server returns and do not replicate the rule locally.
- Work-order attachments and knowledge-base / RAG documents are separate content pools and are out of scope for this feature.
- Bulk re-assigning existing files to departments, and allowing technicians to upload to their own department, are explicitly out of scope for this release.
