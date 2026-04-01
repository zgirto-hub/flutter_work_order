<!--
  Sync Impact Report
  ==================
  Version change: 0.0.0 → 1.0.0 (initial ratification)

  Added Principles:
    - I. Full-Stack Ownership
    - II. Explicit Over Automatic
    - III. Role-Based Access Control
    - IV. Server-First File Storage
    - V. Client-Side Computation Where Possible
    - VI. Audit Everything
    - VII. Simplicity & YAGNI

  Added Sections:
    - Technology Constraints
    - Development Workflow
    - Governance

  Templates requiring updates:
    - .specify/templates/plan-template.md — Constitution Check section
      references generic gates; ✅ compatible (gates are filled per-feature)
    - .specify/templates/spec-template.md — ✅ no conflicts
    - .specify/templates/tasks-template.md — ✅ no conflicts

  Follow-up TODOs: none
-->

# Work Order System Constitution

## Core Principles

### I. Full-Stack Ownership

Every feature MUST span the full stack — backend endpoint, database
migration, frontend model, service, and screen — or explicitly document
why a layer is excluded. The new-feature checklist in AGENT.md is the
authoritative gate: backend router, Supabase migration, Flutter model,
Flutter service, Flutter screen, navigation wiring, and documentation
updates. Partial implementations MUST NOT be merged; incomplete layers
lead to ghost endpoints or orphaned UI that confuse future developers.

### II. Explicit Over Automatic

Assignment, notification routing, and state transitions MUST be
explicit rather than implicit. The system does not auto-assign
technicians to a department's work orders unless the individual
technician has opted in via `technician_auto_assign_self`. Work order
closure MUST record `closed_by` (UUID) and `closed_at` (UTC timestamp)
at the moment of closing — never inferred after the fact. Notifications
MUST follow the documented preference cascade: `mute_all` check,
then event-type toggle, then per-channel toggle. No silent fallback
behavior is permitted; if a preference is missing, the documented
default (`DEFAULT_PREFS`) applies.

### III. Role-Based Access Control

Three roles govern the system: `reporter`, `technician`, `admin`.
Every API endpoint and every frontend screen MUST enforce role-based
visibility as defined in the permissions matrix (AGENT.md /
ARCHITECTURE.md). Admin is the only role that can create user accounts
— there is no self-registration. File permissions use a separate
owner/editor/viewer model with folder-hierarchy inheritance. RLS on
`work_orders` provides defense-in-depth for direct Supabase SDK
access but MUST NOT be relied upon as the sole access control layer
since the backend uses the service role key.

### IV. Server-First File Storage

All uploaded files — work order attachments and managed files — MUST
be stored on the Linux server filesystem under `backend/uploaded_files/`.
No cloud object store is used. Files are served via FastAPI's
`StaticFiles` mount at `/files/<filename>`. Images MUST be
auto-compressed (max 1920px via Pillow). Nginx enforces a 50 MB upload
ceiling. This means server disk is the single source of truth for
binary files; metadata lives in Supabase. Any feature touching file
storage MUST account for this: there is no replication, no CDN, and
no automatic backup of binary content.

### V. Client-Side Computation Where Possible

Recurring inspection calendar events, file filtering, and work order
filtering MUST be computed client-side from the full dataset rather
than making per-view API calls, unless the dataset exceeds practical
memory limits. The calendar screen loads all active inspections once
and builds a bounded event cache (60 days past to 120 days future)
with O(1) lookups. If client-side recurrence logic diverges from the
backend's `_compute_next_due()`, calendar markers and actual generation
will disagree — both MUST be kept in sync when frequency semantics
change.

### VI. Audit Everything

All user-facing actions MUST produce an entry in `user_activity_log`
with a category (`work_order`, `file`, `folder`, `auth`, `admin`) and
action verb (`created`, `updated`, `deleted`, `uploaded`, `shared`,
`signed_in`, etc.). Work order status changes MUST additionally be
logged to `work_order_status_logs` with `old_status`, `new_status`,
and `changed_by`. Notification delivery MUST be tracked in
`notification_delivery_logs` with status (`queued`, `sent`, `failed`)
and retry metadata. Fire-and-forget logging (via `backend/utils/activity.py`)
is acceptable — audit writes MUST NOT block the primary request path.

### VII. Simplicity & YAGNI

Start with the simplest implementation that satisfies the requirement.
Do not add configurability, abstraction layers, or future-proofing
unless a concrete current need demands it. Three similar lines of code
are better than a premature abstraction. Features that exist but are
unused (e.g., the backend `/api/recurring-inspections/calendar`
endpoint) MUST be documented as unused rather than silently removed,
so future developers can decide their fate intentionally.

## Technology Constraints

- **Frontend**: Flutter (Dart), targeting web primarily. PWA URL
  handling MUST use `openInNewTab()` from `download_helper_web.dart`
  via conditional import — never `url_launcher`.
- **Backend**: FastAPI (Python 3) on Uvicorn, single Linux server
  behind Nginx.
- **Database**: Supabase (PostgreSQL). Migrations in
  `supabase/migrations/` applied in timestamp order.
- **Auth**: Supabase email/password. No self-registration.
- **Push**: OneSignal. External ID is the user's email.
- **PDF (client)**: `pdf` Flutter package with four theme variants.
- **PDF (server)**: `reportlab` with logos from `backend/assets/`.
- **OCR**: pytesseract + pdf2image (Arabic + English).
- **`backend/version.json`**: MUST NOT be committed from dev machines;
  it is managed independently on the server.

## Development Workflow

- New features MUST follow the checklist in AGENT.md: backend router,
  migration, model, service, screen, navigation, docs update.
- Database schema changes require a timestamped migration file in
  `supabase/migrations/`.
- API base URL is toggled via `kIsProduction` in
  `frontend/lib/config.dart`.
- Deployment uses shell scripts in `scripts/` — `deploy_frontend.sh`,
  `bump_version.sh`, `update_nginx_config.sh`, `rollback_frontend.sh`.
- Backend is restarted manually after updates (systemd or process
  manager).
- `backend/uploaded_files/` is runtime-created and MUST NOT be committed.

## Governance

This constitution defines the non-negotiable rules for the Work Order
System. All code changes — whether by human developers or AI agents —
MUST comply with these principles.

**Amendment procedure**: Any principle addition, removal, or material
redefinition requires updating this document, incrementing the version
according to semantic versioning (MAJOR for removals/redefinitions,
MINOR for additions, PATCH for clarifications), and updating the
`LAST_AMENDED_DATE`.

**Versioning policy**: MAJOR.MINOR.PATCH. The version in this document
is the authoritative record.

**Compliance review**: The plan-template Constitution Check section
MUST verify that proposed features comply with all active principles
before implementation begins. Any principle violation MUST be
documented in the Complexity Tracking table with justification.

**Version**: 1.0.0 | **Ratified**: 2026-04-02 | **Last Amended**: 2026-04-02
