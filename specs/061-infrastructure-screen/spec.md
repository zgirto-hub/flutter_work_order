# Feature Specification: Infrastructure Screen (Unify Systems + Asset Registry)

**Feature Branch**: `061-infrastructure-screen`
**Created**: 2026-04-14
**Status**: Draft
**Input**: User description: Unify the Systems admin and Asset Registry screens into a single system-centric Infrastructure screen with Production/Contingency site awareness. Reference design: `specs/060-infrastructure-refactor/spec.md`.

## Clarifications

### Session 2026-04-14

- Q: How should the migration treat `system_status_reports` tied to removed International Circuit systems? → A: Repoint all reports (open + resolved) to AIDA-NG, preserving original date/text so the outage history remains intact.
- Q: Can a single asset hold multiple different roles on the same system within the same site? → A: No — one role per (asset, system, site). An asset is either primary, standby, or client on a given system at a given site, not more than one.
- Q: How should the migration resolve a conflict when repointing an International Circuit asset link to AIDA-NG would violate the uniqueness rules (duplicate primary/standby or duplicate asset-system-site)? → A: Demote the repointed link to role=`client`, which preserves the fact of the link without breaking uniqueness constraints.
- Q: What is the flow when an admin toggles `has_contingency` off on a system that still has contingency-site links? → A: Show a confirmation dialog offering to move the N contingency assets to production; on confirm, auto-move and demote to `client` if the move would create primary/standby conflicts; on cancel, abort the toggle.
- Q: When an admin changes an asset link's site and the destination site already has that asset linked to the same system, what should happen? → A: Block the change with an inline error; the admin must first unlink the conflicting link in the target site.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Browse the full infrastructure from one place (Priority: P1)

An admin opens Settings and taps a single "Infrastructure" entry. They see a list of all real systems (e.g., AIDA-NG, CADAS-ATS, INDRA CCTV) as summary cards. Each card shows the system name, status, category, total asset count, and whether the system has a contingency site. Tapping a card opens a detail view for that system, where the admin can see the assets that run it, grouped by site (Production / Contingency) and by role (primary / standby / client).

**Why this priority**: This is the entire point of the feature. Without the unified overview and detail pages, administrators still have to switch between two disconnected screens to understand what hardware runs which system where. P1 is the smallest slice that delivers real value on day one.

**Independent Test**: An admin navigates from Settings → Infrastructure, sees 7 system cards (AIDA-NG, CADAS-ATS, CADAS-IMS, IRTOS, Permissions, Billing System, INDRA CCTV), taps AIDA-NG, and sees its Production and Contingency sections populated with the correct assets and roles. They can confirm this matches what used to live in the separate Systems and Asset Registry screens.

**Acceptance Scenarios**:

1. **Given** the admin is on the Settings page, **When** they tap the Infrastructure entry, **Then** a screen appears showing one summary card per real system with name, status, asset count, and a site indicator ("Prod + Cont" or "Prod only").
2. **Given** the admin is on the Infrastructure overview, **When** they tap the AIDA-NG card, **Then** a detail page opens with a Production section and a Contingency section, each listing the linked assets grouped under primary, standby, and client roles.
3. **Given** the admin is viewing a system that does not have a contingency site (e.g., Billing System), **When** the detail page loads, **Then** only the Production section is shown; no empty Contingency section is displayed.
4. **Given** the admin is on the Infrastructure overview, **When** they use the existing filters (Show Retired, Needs Review, Category), **Then** the list updates to reflect the same filter behavior that existed on the old Systems screen.

---

### User Story 2 - Manage assets for a specific system and site (Priority: P1)

From a system's detail page, the admin can add an asset to either the Production or the Contingency section. They can choose to link an existing asset (e.g., a workstation already connected to AIDA-NG) or create a new asset on the spot. They pick the role (primary, standby, client) and save. They can also tap an existing asset to change its role, change its site, or unlink it from this system.

**Why this priority**: The whole reason to have a system-centric view is to make site- and role-aware asset management fast. This turns the passive browse view (Story 1) into an active management surface.

**Independent Test**: An admin opens AIDA-NG, taps "+ Add" under Contingency, creates a new server named "as1-cont" with role "primary", saves, and sees it appear immediately in the Contingency → Primary slot. They then tap it and change its role to "standby"; the UI moves it into the Standby group.

**Acceptance Scenarios**:

1. **Given** the admin is on a system detail page, **When** they tap "+ Add" under Contingency, **Then** a bottom sheet opens allowing them to either pick an existing asset or create a new one, choose a role, and the site is pre-set to "contingency".
2. **Given** the admin is adding a new link, **When** they try to assign "primary" to a site that already has a primary for this system, **Then** the UI prevents the conflict and explains why (one primary per site).
3. **Given** the admin taps an existing asset card in the detail view, **When** they open the row actions, **Then** they can change role, change site, or remove the link.
4. **Given** an asset is linked to multiple systems (e.g., a workstation that runs both AIDA-NG and CADAS-ATS), **When** the admin unlinks it from AIDA-NG, **Then** the asset itself is preserved and remains linked to CADAS-ATS.

---

### User Story 3 - Administer systems themselves (Priority: P2)

The admin can perform system-level actions from inside the new Infrastructure screen: create a new system (FAB on overview), edit name/category/sort order, toggle whether the system has a contingency site, and retire or reactivate a system. These replace the equivalent actions on the old Systems admin screen.

**Why this priority**: System CRUD already works in the current app; this story re-exposes those same actions in the new navigation so nothing is lost. P2 because Stories 1 and 2 are usable even if the admin never adds or retires a system during the rollout.

**Independent Test**: An admin creates a new system from the Infrastructure FAB, edits its name and toggles `has_contingency` on, then retires it and confirms it disappears from the default list but reappears when "Show Retired" is enabled.

**Acceptance Scenarios**:

1. **Given** the admin is on the Infrastructure overview, **When** they tap the floating action button, **Then** they can create a new system with name, optional category, and initial `has_contingency` value.
2. **Given** the admin is on a system detail page, **When** they open the overflow menu and select "Toggle Has Contingency" on a system that previously had no contingency, **Then** a Contingency section appears (empty) and they can begin adding assets to it.
3. **Given** the admin retires a system with unresolved system-status reports, **When** they confirm the action, **Then** the retirement succeeds and the existing warning behavior about unresolved reports is preserved.

---

### User Story 4 - Cleaned-up seed data on first launch (Priority: P2)

When this feature ships, the Infrastructure screen immediately reflects real-world topology:

- INDRA CCTV Cameras 1 through 10, previously modeled as 10 separate systems, appear as camera **assets** linked to a single "INDRA CCTV" system with role=client in Production.
- International Circuits (Beirut, Damascus, Karachi, Tehran, Baghdad, Bahrain), previously modeled as 6 separate systems, are removed as systems; any asset links that referenced them are repointed to AIDA-NG.
- The remaining 7 real systems carry the correct `has_contingency` values (true for AIDA-NG, CADAS-ATS, CADAS-IMS, IRTOS; false for Permissions, Billing System, INDRA CCTV).

**Why this priority**: Without the data cleanup, the new UI would display misleading infrastructure on day one. P2 because the cleanup is not what users *do*, but it is a prerequisite for Stories 1-3 to look right in production.

**Independent Test**: Immediately after deploying the migration, open the Infrastructure overview and verify the card count is 7 (not 23), each card shows the correct site indicator, and tapping INDRA CCTV shows up to 10 camera assets in its Production → Client group.

**Acceptance Scenarios**:

1. **Given** the migration has run on an environment that had the old seed, **When** an admin opens Infrastructure, **Then** they see exactly 7 real systems and no standalone Camera-N or International-Circuit-X entries.
2. **Given** an asset link previously pointed to an International Circuit system, **When** the migration completes, **Then** that link now points to AIDA-NG with the same role and a site of "production".
3. **Given** the environment previously had no "International Circuit" links, **When** the migration runs, **Then** it completes successfully without error (idempotent / safe on clean DBs).

---

### Edge Cases

- A system that previously had no contingency site gains one: the Contingency section appears empty and accepts new asset links.
- A system that had a contingency site is later flipped to `has_contingency = false` while contingency links still exist: the system opens a confirmation dialog offering to move the N contingency assets to production; on confirm, links are moved (with role demoted to `client` if the move would violate uniqueness), and on cancel the toggle is aborted.
- An admin tries to set two assets as "primary" in the same site: the UI prevents this and explains the rule (one primary per role per site).
- The same physical asset (e.g., one workstation) serves multiple systems: it must appear under each system it is linked to, with the correct site and role for that system.
- A system status report exists for a now-removed International Circuit: the migration repoints it to AIDA-NG (both open and resolved reports), keeping date and text intact, so the historical record is preserved without breaking referential integrity.
- The admin searches the overview while "Show Retired" is active: both filters must compose correctly.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Settings page MUST present a single "Infrastructure" entry that replaces the previous "Systems" and "Asset Registry" entries.
- **FR-002**: The Infrastructure overview MUST display one summary card per system, showing name, status (active/retired), category (if any), review flag (if any), total linked asset count, and a site indicator that reflects whether the system has a contingency site.
- **FR-003**: The Infrastructure overview MUST support the existing filters: Show Retired and Needs Review.
- **FR-004**: Tapping a system card MUST open a detail page for that system.
- **FR-005**: The detail page MUST display a Production section whenever the system is configured to have a production site (i.e., always, in this version).
- **FR-006**: The detail page MUST display a Contingency section **only when** the system's `has_contingency` flag is true.
- **FR-007**: Each site section MUST group assets by role (primary, standby, client) and MUST display each asset's name, type, and location.
- **FR-008**: The detail page MUST allow the admin to add an asset to a specific site, either by selecting an existing asset or by creating a new one inline.
- **FR-009**: The system MUST enforce these linking rules: (a) no single system can have more than one asset with role "primary" per site, (b) no single system can have more than one asset with role "standby" per site, and (c) a given asset can hold at most one role on a given system at a given site (it cannot be both primary and client at the same site, for example). Violations MUST be rejected with a clear explanation.
- **FR-010**: The admin MUST be able to change an asset link's role, change its site, or remove it, from within the detail page. When a site change would conflict with an existing link (same asset already linked to this system at the destination site), the change MUST be blocked with an inline error explaining the conflict; the admin is expected to resolve it by unlinking the conflicting link first.
- **FR-011**: The admin MUST be able to create, edit, retire, and reactivate systems from inside the Infrastructure screen; the floating action button on the overview creates new systems.
- **FR-012**: The admin MUST be able to toggle the `has_contingency` flag on an existing system from the detail page. When an admin flips `has_contingency` from true to false while contingency-site links exist, the system MUST open a confirmation dialog that states the count of contingency assets and offers to move them to the production site. On confirm, the system MUST move those links to site=production, demoting any role to `client` when the move would otherwise violate the uniqueness rules in FR-009. On cancel, the toggle MUST be aborted and no data changed.
- **FR-013**: When this feature ships, a one-time migration MUST transform the existing seed data as follows: the 10 INDRA CCTV Camera-N system rows become camera assets linked to a single INDRA CCTV system (role=client, site=production); the 6 International Circuit system rows are removed and any links pointing to them are repointed to AIDA-NG with site=production. If a repointed link would violate the uniqueness rules in FR-009 (duplicate primary/standby, or duplicate (asset, system, site)), the migration MUST demote the repointed link's role to `client` rather than fail.
- **FR-014**: The migration MUST set `has_contingency = true` for AIDA-NG, CADAS-ATS, CADAS-IMS, and IRTOS, and `has_contingency = false` for Permissions, Billing System, and INDRA CCTV.
- **FR-015**: After migration, no orphaned asset links MUST remain pointing to removed system rows; referential integrity MUST hold.
- **FR-016**: Existing downstream features that read from the systems table (notably the System Status feature) MUST continue to function without modification.
- **FR-017**: The migration MUST be idempotent: re-running it on a migrated database MUST produce no further changes and MUST NOT fail.
- **FR-018**: Deleting an asset from the Infrastructure screen MUST cascade-remove its system links across all systems and sites, consistent with today's behavior.
- **FR-019**: The old Systems admin and Asset Registry screens and their navigation entries MUST be removed once the new Infrastructure screen is live.

### Key Entities

- **System**: A logical platform that is run on physical infrastructure (e.g., AIDA-NG, INDRA CCTV). Attributes include name, optional category, active/retired status, needs-review flag, sort order, and a `has_contingency` flag indicating whether the system is deployed at a contingency site.
- **Asset**: A physical piece of equipment (server, workstation, camera, router, switch, media converter, power adapter) with a name, type, and location. Assets exist independently of any single system and may serve multiple systems.
- **Asset-System Link**: An association between one asset and one system that carries a **role** (primary, standby, or client) and a **site** (production or contingency). A given asset has at most one link per (system, site) combination — it cannot hold two different roles on the same system at the same site.
- **Site**: A fixed two-value category (production or contingency). The contingency site only applies to systems whose `has_contingency` flag is true.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After migration, the Infrastructure overview lists exactly 7 real systems (not 23), and none of them are named "INDRA CCTV - Camera N" or "International Circuits - …".
- **SC-002**: An admin can find the primary server for AIDA-NG's contingency site in under 15 seconds starting from the Settings page, compared to the previous flow that required searching the flat Asset Registry.
- **SC-003**: 100% of asset links that previously referenced an International Circuit system point to AIDA-NG after migration, with no broken foreign keys.
- **SC-004**: The System Status feature continues to function with zero code changes beyond what this feature introduces, verified by loading the existing status dashboard after migration.
- **SC-005**: An admin can create a new asset and link it to a specific system site and role in a single flow without leaving the Infrastructure detail page.
- **SC-006**: No user-visible regressions in Systems CRUD: every action possible on the old Systems screen (create, edit, retire, reactivate, mark review) is still possible on the new Infrastructure screen.

## Assumptions

- Sites are fixed to Production and Contingency for this release. Custom sites (Dev/Test, Training, etc.) are out of scope and will be handled in a later spec if needed.
- International Circuits will not be reintroduced as a first-class concept in this release. If they need first-class modeling later, it will be a separate spec.
- The INDRA CCTV seed (10 cameras) is the authoritative starting set; cameras can be renamed or extended later through normal asset management.
- The admin-only access model for Systems and Asset Registry is preserved; only admins can see and use the Infrastructure screen.
- The existing admin user experience for retiring systems with unresolved status reports (a warning banner) is preserved unchanged.
- Asset types remain the existing enumerated list (workstation, server, camera, router, switch, media_converter, power_adapter); no new types are introduced by this feature.
