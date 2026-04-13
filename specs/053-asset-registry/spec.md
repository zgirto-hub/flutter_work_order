# Feature Specification: Asset Registry

**Feature Branch**: `053-asset-registry`  
**Created**: 2026-04-14  
**Status**: Draft  
**Input**: User description: "Add an Asset Registry module to flutter_work_order that models the physical infrastructure at Kuwait DGCA. Each asset is a physical device (workstation, server, camera, router, switch, media converter, power adapter) with a known location, type, and system associations. Servers are modeled as main/standby pairs per system. Workstations are shared physical machines that can host multiple system clients (CADAS-ATS, CADAS-IMS, AIDA-NG). The registry is Admin-managed via a dedicated screen. The AI extraction pipeline reads from the registry at runtime to build a dynamic domain knowledge block, so Gemma can resolve 'WS-01 crashed' to the correct systems without hardcoded prompt strings. Pattern alerts are enriched with asset context (location, role, hosted systems)."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admin Manages Asset Inventory (Priority: P1)

An Admin opens the Asset Registry screen to maintain a living inventory of all DGCA physical infrastructure. They can view the full list of assets, add new devices (e.g., a new workstation installed in the ACC Tower), edit existing asset details (e.g., relocating a camera), and remove decommissioned equipment. Each asset has a name, type, location, and optional notes.

**Why this priority**: The asset data is the foundation for all downstream features — system associations, AI extraction, and pattern alert enrichment all depend on assets existing in the registry first.

**Independent Test**: Can be fully tested by navigating to the Asset Registry screen, adding an asset with all fields, editing it, and deleting it — confirms CRUD operations deliver value independently.

**Acceptance Scenarios**:

1. **Given** an Admin is on the Asset Registry screen, **When** they tap "Add Asset" and fill in name ("WS-01"), type ("workstation"), location ("ACC Tower - Room 3"), and notes ("Near window bay"), **Then** the asset appears in the list immediately after saving.
2. **Given** an existing asset "CAM-05" in the registry, **When** the Admin edits its location from "Runway 15L" to "Runway 15R", **Then** the updated location is displayed in the list.
3. **Given** a decommissioned asset "SW-OLD-02", **When** the Admin deletes it and confirms, **Then** it is removed from the registry and no longer appears in any list.
4. **Given** an Admin is viewing the asset list, **When** the list has 50+ assets, **Then** they can scroll through all assets and optionally filter by type or search by name.

---

### User Story 2 - Admin Associates Assets with Systems (Priority: P1)

After adding an asset, an Admin links it to one or more systems (e.g., CADAS-ATS, CADAS-IMS, AIDA-NG, INDRA CCTV) and assigns a role for each link: primary (main server), standby (backup server), or client (workstation hosting a system client). A workstation like "WS-01" may be linked to multiple systems as a client. A server like "SRV-CADAS-01" is linked to one system as primary, while "SRV-CADAS-02" is its standby.

**Why this priority**: System associations are the key value-add — they enable AI and pattern features to understand which systems are affected when a device has a fault.

**Independent Test**: Can be tested by adding an asset, then associating it with two systems with different roles, and verifying the associations display correctly on the asset detail.

**Acceptance Scenarios**:

1. **Given** an asset "WS-01" exists, **When** the Admin adds system links for CADAS-ATS (client) and CADAS-IMS (client), **Then** both associations appear under the asset's system list.
2. **Given** an asset "SRV-CADAS-01" exists, **When** the Admin adds a link to CADAS-ATS with role "primary", **Then** the association shows "CADAS-ATS — Primary".
3. **Given** an asset has three system associations, **When** the Admin removes one, **Then** only the remaining two are shown.
4. **Given** an Admin is editing system associations, **When** they try to add a duplicate link (same asset + same system + same role), **Then** the system prevents the duplicate and shows a message.

---

### User Story 3 - AI Extraction Uses Dynamic Asset Context (Priority: P2)

When the entity extraction pipeline processes a work order, it reads the current asset registry to build a dynamic domain knowledge block for the AI model. Instead of relying on a hardcoded list of systems and equipment, the prompt includes up-to-date asset information (names, types, locations, associated systems). When a technician writes "WS-01 crashed", the AI can look up WS-01 in the prompt context, see it is a workstation in "ACC Tower - Room 3" hosting CADAS-ATS and CADAS-IMS clients, and extract the correct system and equipment references.

**Why this priority**: This is the primary integration value — replacing hardcoded domain strings with live registry data makes the extraction pipeline accurate and maintainable without code changes.

**Independent Test**: Can be tested by populating the registry with assets, submitting a work order mentioning an asset by name, and verifying the extracted entities correctly reference the associated systems.

**Acceptance Scenarios**:

1. **Given** the registry contains "WS-01" (workstation, ACC Tower, client of CADAS-ATS and CADAS-IMS), **When** a work order with text "WS-01 not responding" is processed, **Then** the extraction correctly identifies the equipment as "WS-01" and the associated systems as CADAS-ATS and CADAS-IMS.
2. **Given** the registry is updated to add a new system link to "WS-01", **When** the next work order mentioning "WS-01" is processed, **Then** the extraction reflects the updated system associations without any code deployment.
3. **Given** the registry is empty, **When** extraction runs, **Then** the pipeline still functions using a minimal fallback prompt (graceful degradation).

---

### User Story 4 - Pattern Alerts Include Asset Context (Priority: P3)

When the pattern engine detects an alert (e.g., recurring fault on equipment "WS-01"), the alert is enriched with asset metadata from the registry: the asset's location, type, and all hosted systems. This gives the Admin or Supervisor reviewing alerts immediate context — they see not just "WS-01 has 3 faults in 180 days" but also "WS-01 is a workstation in ACC Tower - Room 3 serving CADAS-ATS and CADAS-IMS".

**Why this priority**: Enrichment improves alert actionability but depends on Stories 1-3 being in place. Alerts still function without enrichment; the extra context is additive.

**Independent Test**: Can be tested by creating assets with system links, triggering a pattern alert for an asset's equipment ID, and verifying the alert card shows location and system details.

**Acceptance Scenarios**:

1. **Given** a pattern alert references equipment_id "WS-01" and the registry has that asset with location "ACC Tower - Room 3" and systems [CADAS-ATS, CADAS-IMS], **When** the alert is displayed, **Then** it shows the asset location and associated systems alongside the alert message.
2. **Given** a pattern alert references an equipment_id not found in the registry, **When** the alert is displayed, **Then** it shows the standard alert without asset context (no error).

---

### Edge Cases

- What happens when an asset is deleted but existing pattern alerts reference its equipment_id? Alerts retain their original message text; enrichment simply returns no additional context for that ID.
- What happens when the registry has no assets? The extraction pipeline falls back to a minimal prompt; pattern alerts display without enrichment. No errors are thrown.
- What happens when a system name in the registry doesn't match any known extraction category? The AI model receives the registry data as-is; unrecognized system names are included in the prompt context for the model to interpret.
- What happens when two assets share the same name? The system requires unique asset names to prevent ambiguity in extraction lookups.
- What happens when an Admin tries to assign a second primary server to a system that already has one? The system blocks the action and shows which asset currently holds the primary role, so the Admin can reassign if needed.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow Admins to create assets with a name, type (from a defined set: workstation, server, camera, router, switch, media converter, power adapter), location (free text), and optional notes.
- **FR-002**: System MUST allow Admins to view all assets in a scrollable list, with the ability to filter by asset type and search by name.
- **FR-003**: System MUST allow Admins to edit any field of an existing asset.
- **FR-004**: System MUST allow Admins to delete an asset after confirmation, which also removes all its system associations.
- **FR-005**: System MUST enforce unique asset names across the registry.
- **FR-006**: System MUST allow Admins to associate an asset with one or more systems, specifying a role (primary, standby, or client) for each association.
- **FR-007**: System MUST prevent duplicate associations (same asset + same system + same role).
- **FR-007a**: System MUST enforce that each system has at most one asset with the "primary" role and at most one with the "standby" role. If an Admin attempts to assign a primary or standby role to a system that already has one, the system MUST block the action and identify the existing holder.
- **FR-008**: System MUST allow Admins to remove individual system associations from an asset.
- **FR-009**: The entity extraction pipeline MUST read the current asset registry at extraction time and build the domain knowledge prompt block dynamically from registry data.
- **FR-010**: The dynamically built prompt block MUST include each asset's name, type, location, and associated systems with roles.
- **FR-011**: If the asset registry is empty, the extraction pipeline MUST still function with a minimal fallback prompt.
- **FR-012**: Pattern alerts MUST be enriched with asset metadata (location, type, associated systems) when the alert's equipment_id matches an asset name in the registry.
- **FR-013**: If no matching asset is found for an alert's equipment_id, the alert MUST display normally without enrichment and without errors.
- **FR-014**: Only users with the Admin role MUST have access to the Asset Registry screen. The screen MUST NOT appear in navigation for non-Admin users. Non-Admin users consume asset context exclusively through enriched pattern alerts.

### Key Entities

- **Asset**: A physical device at DGCA — identified by a unique name, categorized by type, placed at a location, with optional notes. Represents workstations, servers, cameras, routers, switches, media converters, and power adapters.
- **Asset-System Link**: A relationship between an asset and a system (e.g., CADAS-ATS, AIDA-NG), qualified by a role (primary, standby, or client). One asset can have multiple links; one system can be linked to multiple assets.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Admins can add, edit, and delete assets and their system associations in under 30 seconds per operation.
- **SC-002**: The AI extraction pipeline correctly identifies the associated systems for a mentioned asset in at least 90% of work orders that reference registered equipment by name.
- **SC-003**: Extraction prompt updates reflect registry changes without any code deployment — adding a new asset to the registry is immediately available to the next extraction run.
- **SC-004**: Pattern alerts for registered equipment display asset context (location + systems) — users can identify the physical location and affected systems at a glance.
- **SC-005**: The registry supports at least 200 assets without noticeable performance degradation in the admin list or extraction prompt generation.

## Clarifications

### Session 2026-04-14

- Q: Should the system enforce that each system has at most one primary and one standby server? → A: Yes, enforce max one primary + one standby per system (block duplicates).
- Q: Can Admins add custom asset types, or is the list fixed? → A: Fixed list of 7 predefined types (workstation, server, camera, router, switch, media converter, power adapter); new types require a code update.
- Q: Should non-Admin users have read-only access to the registry? → A: No. Admin-only screen; non-Admins see asset context only through enriched pattern alerts.
- Q: Should the Asset Registry integrate with the existing System Status screen? → A: No integration now; both reference the same system names independently. Log shared system source as a future refactor once the Asset Registry is stable.

## Assumptions

- The known systems (CADAS-ATS, CADAS-IMS, AIDA-NG, INDRA CCTV) will be seeded as selectable options, but Admins may add new system names as needed to keep the registry extensible.
- AIDA-NG international circuits (Bahrain, Karachi, Tehran, Doha, Damascus, Beirut) are pre-seeded as individual assets (type: router) with system link to AIDA-NG (role: client), so the extractor can resolve circuit references to the correct system.
- Asset names follow the existing DGCA naming convention (e.g., "WS-01", "SRV-CADAS-01", "CAM-05") and are unique identifiers used to match equipment references in work order text.
- The extraction pipeline currently uses a hardcoded prompt string; this feature replaces that string with a dynamically generated one from registry data.
- The Admin screen follows the existing app patterns: plain StatefulWidget with direct service injection, SnackBar for feedback, and AlertDialog for delete confirmations.
- Only the Admin role needs write access to the registry; the extraction pipeline and pattern engine read from the registry as internal services.
- The asset type list is fixed to 7 values (workstation, server, camera, router, switch, media converter, power adapter). Adding new types requires a code update; Admins cannot create custom types.
- The Asset Registry and the existing System Status screen remain independent — no data coupling between them. Both reference the same system names (CADAS-ATS, CADAS-IMS, AIDA-NG, INDRA CCTV) but maintain separate lists. **Future refactor**: once the Asset Registry is stable, unify system names into a shared source (a `systems` table) to eliminate duplicate maintenance.
