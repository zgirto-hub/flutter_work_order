# Feature Specification: Link Payment Certificates to Letters (Merged PDF Export)

**Feature Branch**: `029-link-cert-letter`
**Created**: 2026-04-07
**Status**: Draft
**Input**: User description: "Link payment certificates to Letters v2 with merged PDF export. Author attaches existing payment certificates to a letter via a picker, sees/removes linked certs, and exports a single combined PDF."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Attach payment certificates to a letter and export a combined PDF (Priority: P1)

A letter author is preparing an official letter that references one or more already-issued payment certificates. From the letter form they open a picker, search and select the relevant payment certificates, see them listed on the letter as attachments, and when they export or regenerate the letter PDF the output is a single PDF containing the letter followed by each linked payment certificate PDF.

**Why this priority**: This is the core value of the feature — without it the author must manually download each payment certificate and merge PDFs outside the system, which is slow and error-prone. Delivering only this story produces a usable MVP.

**Independent Test**: Create a letter, attach two existing payment certificates, export the letter PDF, and confirm the downloaded file is a single PDF containing the letter followed by both certificates in order.

**Acceptance Scenarios**:

1. **Given** an author is creating a new letter and payment certificates exist in the system, **When** they open the attachment picker, search by certificate number or subject, and select one or more certificates, **Then** those certificates appear as linked attachments on the letter form.
2. **Given** a letter with one or more linked payment certificates, **When** the author exports or regenerates the letter PDF, **Then** the downloaded file is a single PDF consisting of the letter pages followed by each linked certificate's pages in the order they were attached.
3. **Given** a saved letter with linked certificates, **When** the author reopens it, **Then** the previously linked certificates are still shown in the attachments list.
4. **Given** a letter with linked certificates, **When** the author removes a certificate from the list and saves, **Then** the removed certificate is no longer associated with the letter and is not included in subsequent PDF exports.

---

### User Story 2 - Handle certificates already linked to another letter (Priority: P2)

When an author tries to attach a payment certificate that is already linked to a different letter, the system warns the author and asks them to confirm reassignment before moving the link.

**Why this priority**: Prevents accidental data loss (a certificate silently disappearing from another letter) but is not required for the MVP happy path where certificates are unlinked.

**Independent Test**: Attach a certificate to Letter A, then attempt to attach the same certificate to Letter B and confirm the warning appears and reassignment only happens on explicit confirmation.

**Acceptance Scenarios**:

1. **Given** a payment certificate is already linked to Letter A, **When** an author attempts to attach it to Letter B, **Then** the system shows a warning indicating the existing link and requires explicit confirmation to reassign.
2. **Given** the author confirms reassignment, **When** Letter B is saved, **Then** the certificate is linked only to Letter B and no longer appears on Letter A.

---

### User Story 3 - Preserve unlink on letter deletion (Priority: P3)

When a letter that has linked payment certificates is deleted, the certificates themselves remain in the system and become unlinked (available to be attached to another letter).

**Why this priority**: Existing behavior that must be preserved — regression protection rather than new value.

**Independent Test**: Delete a letter with two linked certificates and verify the certificates still exist and show no linked letter.

**Acceptance Scenarios**:

1. **Given** a letter with linked payment certificates, **When** the letter is deleted, **Then** the certificates remain in the system with no letter association.

---

### Edge Cases

- Exporting a letter with zero linked certificates produces just the letter PDF (current behavior, unchanged).
- A linked certificate that has been deleted between save and export is skipped and the user is informed which cert was skipped, while the merge still succeeds.
- If a certificate's PDF content cannot be produced at export time, the remaining pages are still merged and the user is informed which cert was skipped.
- Reordering linked certificates in the form updates the order of appended pages in the merged PDF output.
- Very large merged PDFs (letter plus many multi-page certificates) must still download as a single file within a reasonable time.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow a letter author to attach one or more existing payment certificates to a letter from the letter form.
- **FR-002**: System MUST provide a searchable picker that lets the author find payment certificates by certificate number and subject.
- **FR-003**: System MUST display the list of currently linked payment certificates on the letter form, showing at minimum certificate number and subject.
- **FR-004**: Users MUST be able to remove a linked payment certificate from the letter before or after saving.
- **FR-005**: System MUST persist the linkage between a letter and its payment certificates so reopening the letter shows the same attachments.
- **FR-006**: System MUST include each linked payment certificate's PDF content appended to the letter PDF when the letter is exported or regenerated, producing a single combined PDF download.
- **FR-007**: System MUST order the appended certificate pages in the merged PDF according to the order shown in the letter form's attachment list.
- **FR-008**: System MUST warn the author and require explicit confirmation before reassigning a payment certificate that is already linked to a different letter.
- **FR-009**: System MUST unlink (but not delete) all linked payment certificates when a letter is deleted.
- **FR-010**: System MUST skip any linked certificate whose content cannot be produced at export time, inform the user which certificates were skipped, and still return the merged PDF of the remaining content.
- **FR-011**: Only the letter author and administrators MAY attach or detach payment certificates to/from a letter.
- **FR-012**: System MUST enforce the one-letter-per-certificate constraint (a single payment certificate cannot simultaneously be linked to two letters).

### Key Entities

- **Letter**: An official document authored in the Letters v2 workflow. Has zero or more linked payment certificates. Produces a PDF export.
- **Payment Certificate**: An existing certificate document in the system. May be linked to at most one letter at a time. Has an identifier, certificate number, subject, and a produced PDF representation.
- **Letter–Certificate Link**: The association between a letter and a payment certificate, carrying ordering information for export.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An author can attach payment certificates to a letter and export a combined PDF in under 60 seconds end-to-end for a typical letter with up to 3 attached certificates.
- **SC-002**: 100% of letter PDF exports that have linked certificates return a single downloadable file containing both the letter and all linked certificate pages (no separate downloads required).
- **SC-003**: Zero payment certificates are silently reassigned: every reassignment between letters is preceded by an explicit confirmation.
- **SC-004**: Support requests related to "manually merging letter and payment certificate PDFs" drop to zero within one month of release.
- **SC-005**: Authors report (via qualitative feedback) that attaching certificates is at least as easy as attaching file uploads in the existing letter form.

## Assumptions

- The existing one-to-many relationship (one letter → many certificates, one certificate → one letter) is sufficient; true many-to-many is out of scope.
- Payment certificates already have a reliable way to produce their PDF content (either stored on disk or regenerated on demand) — the spec does not prescribe which.
- Creating new payment certificates from inside the letter form is out of scope; authors must create certificates through the existing payment certificate workflow first.
- Only letter authors and administrators can manage attachments; general readers cannot modify links.
- Ordering of attached certificates in the merged PDF follows the order presented in the letter form, which the author can rearrange before save.
- Letter deletion continues to unlink (not delete) associated certificates, preserving existing behavior.

## Dependencies

- Existing Letters v2 create/update/export/regenerate workflow.
- Existing Payment Certificate records and their ability to produce PDF content.
- Existing letter deletion flow that unlinks certificates.
