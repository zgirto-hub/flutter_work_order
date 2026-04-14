# Feature Specification: Shared Systems Table

**Feature Branch**: `056-shared-systems-table`  
**Created**: 2026-04-14  
**Status**: Draft  
**Input**: User description: "Create a shared systems table to unify system names across the codebase. Replace hardcoded ALLOWED_SYSTEMS lists in backend (system_status.py, ai_insights.py), frontend systemSuggestions in asset.dart, and free-text system columns in asset_system_links and system_status_reports with a single systems database table. Provide a /api/systems endpoint. Migrate existing system names into the table. Add FK references from asset_system_links.system_id and system_status_reports.system_id. Support adding/renaming/retiring systems via admin UI without code deploys."

## Clarifications

### Session 2026-04-14

- Q: Should `work_order_entities.system` (entity extraction output) also migrate to FK the systems table? → A: No — keep as free text. AI-extracted values may not perfectly match canonical names; the extraction prompt already uses canonical names as guidance.
- Q: Should the systems table support an explicit display/sort order? → A: Yes — add a sort order field; migration seeds it to match the current ALLOWED_SYSTEMS list ordering.
- Q: Where should the Systems management screen live in the UI? → A: Standalone admin screen with its own entry in the admin navigation, consistent with other admin features.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Manage the canonical list of systems (Priority: P1)

An administrator opens the Systems management screen and sees all registered systems (CADAS-ATS, CADAS-IMS, AIDA-NG, etc.) in a single list. They can add a new system, rename an existing one, or retire a system that is no longer in service — all without requiring a code deployment. Retired systems are hidden from selection dropdowns but remain visible in historical records.

**Why this priority**: This is the core of the feature — establishing a single, authoritative source of system names that replaces all hardcoded lists. Without this, every other story has no foundation.

**Independent Test**: Can be fully tested by navigating to the admin Systems screen, verifying all 24 existing systems appear, adding a new system, renaming one, and retiring one. The changes should be immediately reflected without restarting the application.

**Acceptance Scenarios**:

1. **Given** an administrator is on the Systems management screen, **When** they view the list, **Then** all currently known systems are displayed with their name, category, and active status.
2. **Given** an administrator adds a new system name, **When** they save, **Then** the new system immediately appears in all system selection dropdowns across the application.
3. **Given** an administrator retires a system, **When** they confirm the action, **Then** the system no longer appears in selection dropdowns but existing records referencing it remain intact.
4. **Given** an administrator renames a system, **When** they save, **Then** the updated name is reflected everywhere the system is referenced.

---

### User Story 2 - Select systems from a unified dropdown when linking assets (Priority: P2)

A technician or administrator is creating or editing an asset in the Asset Registry. When they need to link the asset to a system, they see a dropdown populated from the central systems table instead of a limited autocomplete with only 4 suggestions. The dropdown shows all active systems and allows search/filtering.

**Why this priority**: The Asset Registry is the primary consumer of system names and currently has the weakest validation (free-text entry). Connecting it to the shared table eliminates data quality issues like typos and inconsistent naming.

**Independent Test**: Can be tested by editing an asset, opening the system selection field, and verifying it shows all active systems from the central table. Entering a system name not in the table should not be possible.

**Acceptance Scenarios**:

1. **Given** a user is linking an asset to a system, **When** they open the system selector, **Then** they see all active systems from the central systems table.
2. **Given** a user searches for a system in the selector, **When** they type a partial name, **Then** results are filtered to matching active systems.
3. **Given** a system has been retired, **When** a user opens the system selector, **Then** the retired system does not appear as an option.
4. **Given** an asset is already linked to a system that was later retired, **When** the user views the asset, **Then** the retired system name is still displayed (read-only) on the existing link.

---

### User Story 3 - System Status screen uses the shared systems table (Priority: P2)

An operator opens the System Status screen and sees all active systems from the central table, rather than a hardcoded list. When a new system is added via the admin screen, it automatically appears on the System Status screen without any backend code changes.

**Why this priority**: Same priority as Story 2 — the System Status screen is the other major consumer of system names and currently relies on a hardcoded Python constant.

**Independent Test**: Can be tested by adding a new system via the admin screen, then navigating to System Status and verifying the new system appears in the daily status grid.

**Acceptance Scenarios**:

1. **Given** the System Status screen is loaded, **When** the system list is fetched, **Then** it reflects all active systems from the central table.
2. **Given** an administrator has added a new system, **When** an operator refreshes the System Status screen, **Then** the new system appears in the status grid.
3. **Given** existing system status reports reference a system by name, **When** the migration runs, **Then** all historical reports are linked to the correct system record.

---

### User Story 4 - Data migration preserves all existing references (Priority: P1)

When the shared systems table is deployed, all existing data — system status reports, asset-system links, and any other references — are automatically migrated. No data is lost, and all historical records correctly reference the new systems table.

**Why this priority**: P1 because a migration failure would break existing functionality. This is a prerequisite for all other stories.

**Independent Test**: Can be tested by running the migration against a copy of production data and verifying row counts and referential integrity before and after.

**Acceptance Scenarios**:

1. **Given** the database contains existing system_status_reports with system_name values, **When** the migration runs, **Then** each report is linked to the corresponding record in the systems table.
2. **Given** the database contains existing asset_system_links with free-text system values, **When** the migration runs, **Then** each link is associated with the matching system record (creating new system records for any previously unknown names).
3. **Given** the migration has completed, **When** a user views historical data, **Then** all system names display correctly and match their pre-migration values.

---

### Edge Cases

- What happens when two existing records use slightly different spellings of the same system (e.g., "CADAS-ATS" vs "cadas-ats")? The migration should normalize to the canonical spelling from the ALLOWED_SYSTEMS list, and any unrecognized free-text values should be created as new system entries for manual review.
- What happens when an administrator tries to retire a system that has active (unresolved) status reports? The system should warn the administrator but still allow retirement — the unresolved reports remain linked.
- What happens when all systems are retired? The System Status screen should display an empty state indicating no active systems are configured.
- What happens if a system name already exists when an administrator tries to add it? The system should reject the duplicate with a clear validation message.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a centralized registry of all system names as the single source of truth.
- **FR-002**: System MUST allow administrators to add new systems with a name and optional category.
- **FR-003**: System MUST allow administrators to rename existing systems, with the change reflected across all references.
- **FR-004**: System MUST allow administrators to retire (soft-delete) systems so they no longer appear in selection interfaces but remain in historical data.
- **FR-005**: System MUST provide an endpoint that returns the list of active systems for use by all frontend screens.
- **FR-006**: System MUST enforce unique system names (case-insensitive).
- **FR-007**: System MUST migrate all existing system names from hardcoded lists, system_status_reports, and asset_system_links into the central table.
- **FR-008**: System MUST replace free-text system entry in the Asset Registry with a constrained selector backed by the central table.
- **FR-009**: System MUST replace the hardcoded ALLOWED_SYSTEMS validation in System Status with a lookup against the central table.
- **FR-010**: System MUST support optional grouping/categorization of systems (e.g., all "INDRA CCTV" cameras grouped together).
- **FR-011**: System MUST prevent deletion of system records that are referenced by existing data; only retirement (soft-delete) is allowed.
- **FR-012**: System MUST support an explicit display/sort order for each system, used to control rendering order on the System Status screen and other lists.
- **FR-013**: System MUST provide a dedicated admin management screen accessible from the admin navigation for CRUD operations on systems.

### Key Entities

- **System**: A named system tracked by the organization (e.g., "CADAS-ATS", "AIDA-NG"). Attributes: name (unique), category (optional grouping label), display/sort order, active status, timestamps. Relationships: referenced by asset-system links and system status reports.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All system name references across the application resolve to a single authoritative source — zero hardcoded system name lists remain in the codebase.
- **SC-002**: Administrators can add, rename, or retire a system in under 30 seconds without requiring a code deployment or application restart.
- **SC-003**: 100% of existing system status reports and asset-system links are correctly migrated to reference the new central table with no data loss.
- **SC-004**: The system selector in the Asset Registry shows all active systems (currently 24) instead of the previous 4 suggestions, reducing data entry errors from inconsistent free-text input to zero.
- **SC-005**: Adding a new system via the admin screen makes it immediately available on both the System Status screen and Asset Registry — no code changes required.

## Design Notes

- **Rename is free by design**: Because all references (asset-system links, system status reports) point to the system record by FK — not by name string — renaming a system is a single update to the systems table. The new name is automatically reflected everywhere at query time with zero propagation logic. There is no need for cascade updates, background jobs, or find-and-replace across tables. Future contributors should not add rename-propagation code; the FK design makes it unnecessary.

## Assumptions

- The existing 24 systems in the ALLOWED_SYSTEMS list represent the canonical set of system names. Any free-text system names in asset_system_links that don't match this list will be created as new system entries for admin review.
- Only administrators can manage (add/rename/retire) systems. All authenticated users can view the active systems list.
- The category field is used for UI grouping (e.g., grouping all "INDRA CCTV" cameras) and does not affect functionality.
- System retirement is a soft operation — retired systems are hidden from dropdowns but remain queryable for historical reporting.
- The migration will run as a one-time database migration script, not as a runtime operation.
- The `work_order_entities.system` column (entity extraction output, spec 049) is explicitly out of scope — it remains free text since AI-extracted values may not perfectly match canonical system names.
- The Systems management screen is a standalone admin screen, consistent with the existing admin navigation pattern (asset registry, pattern rules, extraction toggle).
- The migration seeds the sort order field to match the current ALLOWED_SYSTEMS list ordering so the System Status screen layout is preserved.
