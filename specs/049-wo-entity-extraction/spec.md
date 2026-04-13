# Feature Specification: Work Order Entity Extraction

**Feature Branch**: `049-wo-entity-extraction`  
**Created**: 2026-04-13  
**Status**: Draft  
**Input**: User description: "Entity extraction background job for work orders (Level 4 Component 1)"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic Entity Extraction on Work Order Lifecycle Events (Priority: P1)

When a technician creates or closes a work order, the system automatically extracts structured entities (equipment, fault type, actions taken, parts replaced, etc.) from the work order text in the background. The technician experiences no delay — the work order API responds immediately while extraction happens asynchronously.

**Why this priority**: This is the core value proposition. Without automatic extraction on create/close events, no structured entity data is generated, making all downstream analytics and search capabilities impossible.

**Independent Test**: Create a work order with descriptive text mentioning equipment, faults, and parts. Verify that within a short time, the corresponding entity record appears with correctly extracted fields — without any noticeable delay in the work order creation response.

**Acceptance Scenarios**:

1. **Given** a new work order is created with descriptive text, **When** the creation API responds, **Then** the response returns immediately and entity extraction begins in the background.
2. **Given** a work order is closed with notes describing the resolution, **When** the close API responds, **Then** entities are extracted from the combined description and notes text.
3. **Given** entity extraction completes successfully, **Then** a record in the entity store contains all extractable fields (equipment_id, equipment_type, fault_type, fault_code, action_taken, procedure_followed, parts_replaced, outcome).
4. **Given** entities already exist for a work order, **When** the work order is closed (triggering re-extraction), **Then** the existing entity record is updated rather than creating a duplicate.

---

### User Story 2 - Manual Re-extraction for a Specific Work Order (Priority: P2)

An administrator can manually trigger entity re-extraction for any specific work order. This is useful when the original extraction failed, when work order text was edited after creation, or when the extraction model has been improved and the admin wants better results.

**Why this priority**: Provides a recovery mechanism for failed extractions and allows admins to refresh entity data on demand. Essential for data quality management.

**Independent Test**: Call the manual extraction endpoint for a specific work order ID and verify that entities are extracted (or re-extracted) correctly, replacing any previous entity data.

**Acceptance Scenarios**:

1. **Given** a work order exists with no extracted entities, **When** an admin triggers manual extraction for that work order, **Then** entities are extracted and stored.
2. **Given** a work order already has extracted entities, **When** an admin triggers manual re-extraction, **Then** the existing entities are replaced with the newly extracted data.
3. **Given** a work order ID that does not exist, **When** an admin triggers extraction, **Then** the system returns an appropriate error indicating the work order was not found.

---

### User Story 3 - Bulk Backfill of Historical Work Orders (Priority: P3)

An administrator can trigger a bulk backfill process that finds all work orders lacking entity records and extracts entities for them. The process runs in controlled batches to avoid overloading the system, and the admin receives feedback on progress.

**Why this priority**: Enables the organization to populate entity data for the entire historical work order catalog, unlocking analytics across all past work — not just new work orders.

**Independent Test**: With a set of work orders that have no entity records, trigger the backfill endpoint and verify that entities are extracted in batches, with work orders that already have entities being skipped.

**Acceptance Scenarios**:

1. **Given** 25 work orders exist and none have entity records, **When** an admin triggers backfill, **Then** extraction processes them in batches of 10 (10, 10, 5) without overwhelming the system.
2. **Given** 25 work orders exist and 15 already have entity records, **When** an admin triggers backfill, **Then** only the 10 without entities are processed.
3. **Given** a backfill is triggered and some extractions fail, **Then** the system continues processing remaining work orders and reports which ones failed.

---

### User Story 4 - Graceful Failure Handling (Priority: P2)

When the AI model fails to return valid structured data, the system retries once. If the retry also fails, the system logs the failure with details for debugging but does not crash or block any other operations.

**Why this priority**: Reliability is critical for a background process. Unhandled failures could silently lose data or, worse, crash the application.

**Independent Test**: Simulate a scenario where the AI model returns invalid output. Verify that the system retries once, and if the retry also fails, logs the error without crashing.

**Acceptance Scenarios**:

1. **Given** the AI model returns malformed output on the first attempt, **When** the system retries, **And** the retry succeeds, **Then** entities are stored normally.
2. **Given** the AI model returns malformed output on both attempts, **Then** the failure is logged with the work order ID and error details, and no entity record is created.
3. **Given** the AI model is completely unreachable, **Then** the failure is logged and the work order API response is not affected.

---

### Edge Cases

- What happens when work order description and notes are both empty or contain only whitespace? The system skips extraction and logs a notice.
- What happens when the AI model returns valid JSON but with missing or null fields? The system stores the partial extraction with null values for missing fields.
- What happens if two extraction requests for the same work order run concurrently (e.g., a close event and a manual trigger at the same time)? The idempotent upsert ensures no duplicates; the last write wins.
- What happens when the backfill endpoint is called while another backfill is already running? The system should either queue or reject the second request with an appropriate message.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST automatically trigger entity extraction when a work order is created.
- **FR-002**: System MUST automatically trigger entity extraction when a work order is closed.
- **FR-003**: Entity extraction MUST run as a background task that does not block the work order API response.
- **FR-004**: System MUST extract the following entities from work order text: equipment_id, equipment_type, fault_type, fault_code, action_taken, procedure_followed, parts_replaced (list), outcome, technician_id, work_order_id, and date.
- **FR-005**: Extracted entities MUST be stored in a dedicated entity store linked to the work order.
- **FR-006**: Extraction MUST be idempotent — if entities already exist for a work order, they are updated rather than duplicated.
- **FR-007**: If the AI model fails to return valid structured data, the system MUST retry once before logging the failure.
- **FR-008**: Failed extractions MUST be logged with sufficient detail for debugging (work order ID, error details, timestamp).
- **FR-009**: Failed extractions MUST NOT crash the application or affect other operations.
- **FR-010**: System MUST provide a manual trigger endpoint allowing an administrator to re-extract entities for a specific work order.
- **FR-011**: System MUST provide a bulk backfill endpoint that processes all work orders lacking entity records, in batches of 10.
- **FR-012**: The extraction input MUST combine the work order's description and notes fields.
- **FR-013**: Work orders with empty or whitespace-only text MUST be skipped during extraction with a logged notice.

### Key Entities

- **Work Order Entity Record**: Represents structured data extracted from a work order's free-text description and notes. Key attributes: equipment_id, equipment_type, fault_type, fault_code, action_taken, procedure_followed, parts_replaced (list of strings), outcome, technician_id, work_order_id (unique link to source work order), date, extraction timestamp. One-to-one relationship with a Work Order.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Entity extraction completes within 30 seconds of the triggering event (work order create/close) for a single work order.
- **SC-002**: Work order creation and closure response times are not measurably affected (less than 50ms additional latency) by the background extraction process.
- **SC-003**: 90% of work orders with substantive text (more than 10 words) produce a valid entity record on the first or retry attempt.
- **SC-004**: Bulk backfill of 100 historical work orders completes without manual intervention or system instability.
- **SC-005**: Zero application crashes or unhandled errors attributed to the extraction process over a 30-day period.
- **SC-006**: All extraction failures are logged with enough detail for an administrator to identify and resolve the issue.

## Assumptions

- The AI model is running and accessible on the same network as the backend server (localhost:11434).
- Work order description and notes fields contain enough natural-language context for meaningful entity extraction in most cases.
- The existing work order create and close API endpoints can accommodate the addition of a background task without architectural changes.
- Administrator role is already defined in the system and can be used to gate access to manual trigger and backfill endpoints.
- The 15GB server RAM is sufficient to handle batch sizes of 10 concurrent extraction requests alongside normal system operations.
- Extraction quality from the AI model is acceptable for the intended use case (analytics, search) without human review of every record.
- This feature is entirely backend — no frontend (Flutter) changes are required.
