# Feature Specification: Pattern Rules Engine

**Feature Branch**: `051-pattern-rules-engine`  
**Created**: 2026-04-13  
**Status**: Draft  
**Input**: User description: "Pattern rules engine (Level 4 Component 2) for the work order AI pipeline"

## Clarifications

### Session 2026-04-13

- Q: Do pattern alerts have a lifecycle or are they immutable records? → A: Simple lifecycle — alerts transition through new → acknowledged → resolved, managed by admins.
- Q: If pattern rule evaluation fails after entity extraction, should extraction be rolled back? → A: Fire-and-forget — extraction always succeeds; pattern evaluation failures are logged silently.
- Q: Can admins create custom rules with arbitrary detection logic or only structured types? → A: Same structured detection types as built-in rules — admins pick a type from a dropdown and fill threshold fields (no raw SQL).
- Q: What is the deduplication key for alerts during full scan? → A: Rule ID + equipment_id + fault_type + calendar month — dedup resets monthly so recurring patterns re-alert each period.
- Q: Where should the admin alert management view appear? → A: New "Alerts" tab in ManualAssistantScreen, admin-only, alongside the Rules tab.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic Pattern Detection After Entity Extraction (Priority: P1)

When a work order's entities are extracted, the system automatically checks all active pattern rules against the newly extracted data and fires alerts for any matches. This happens transparently — no user action required. Pattern evaluation is fire-and-forget: if evaluation fails, the entity extraction result is preserved and the failure is logged silently. Alerts accumulate in the background and become available when the AI assistant queries work order patterns or when admins view the Alerts tab.

**Why this priority**: This is the core value proposition — continuous, automated monitoring of work order patterns without human intervention. Without this, the engine has no purpose.

**Independent Test**: Can be tested by extracting entities for a work order that matches a known rule (e.g., a third fault of the same type on the same equipment within 6 months) and verifying an alert record is created with status "new".

**Acceptance Scenarios**:

1. **Given** an active rule "Recurring fault threshold" (3 occurrences within 6 months) and 2 existing entities for equipment X with fault type Y within the last 6 months, **When** a third entity extraction completes for equipment X with fault type Y, **Then** a pattern alert is created with severity "high", status "new", referencing the matching rule and affected work orders.
2. **Given** a rule that is disabled (enabled = false), **When** entity extraction completes for a work order that would match the rule, **Then** no alert is fired for that rule.
3. **Given** an alert already exists for a prior match of the same rule and equipment, **When** a new entity extraction triggers the same pattern again, **Then** a new alert is created (each occurrence is recorded independently with its own timestamp and status "new").
4. **Given** pattern rule evaluation encounters an error (e.g., database timeout), **When** entity extraction has already completed, **Then** the extraction result is preserved and the evaluation failure is logged silently without affecting the extraction outcome.

---

### User Story 2 - Admin Manages Pattern Rules (Priority: P2)

An administrator navigates to the ManualAssistantScreen and sees a "Rules" tab (visible only to admins). From there, they can view all pattern rules, toggle rules on/off, edit existing rules, delete rules, and create new custom rules. Custom rules use the same structured detection types as built-in rules — admins select a detection type from a dropdown and configure threshold parameters via form fields. No raw SQL input is required.

**Why this priority**: Admins need the ability to customize detection to their operational context — adjusting thresholds, adding domain-specific rules, and disabling irrelevant ones. This makes the engine adaptable rather than static.

**Independent Test**: Can be tested by logging in as an admin, navigating to the Rules tab, creating a new rule by selecting a detection type and filling threshold fields, editing an existing rule's threshold, toggling a rule off, and deleting a custom rule — verifying each change persists on refresh.

**Acceptance Scenarios**:

1. **Given** a user with admin role, **When** they open the ManualAssistantScreen, **Then** they see "Rules" and "Alerts" tabs alongside Chat, Knowledge, and Review Queue tabs.
2. **Given** a user without admin role, **When** they open the ManualAssistantScreen, **Then** they do not see the Rules or Alerts tabs.
3. **Given** an admin on the Rules tab, **When** they tap the add button, **Then** they see a form with a detection type dropdown (matching the six built-in types), fields for name, description, severity dropdown, threshold values, and enabled toggle.
4. **Given** an admin viewing the rules list, **When** they toggle a rule's enabled switch off, **Then** the rule is immediately updated to disabled and will not trigger during future entity extractions.
5. **Given** an admin editing a rule, **When** they change the threshold from 3 to 5 and save, **Then** subsequent pattern checks use the new threshold value of 5.
6. **Given** an admin viewing any rule, **When** they choose to delete it, **Then** the rule is removed and any future scans no longer evaluate it.

---

### User Story 3 - Admin Views and Manages Alerts (Priority: P2)

An administrator navigates to the "Alerts" tab in ManualAssistantScreen to view all pattern alerts. Alerts are listed with their severity, rule name, affected equipment/fault details, status, and detection timestamp. Admins can transition alert status from new → acknowledged → resolved.

**Why this priority**: With alerts having a lifecycle, admins need a dedicated view to triage and track pattern alerts. This closes the feedback loop — patterns are detected, reviewed, and acted upon.

**Independent Test**: Can be tested by triggering a pattern alert, then navigating to the Alerts tab as an admin, verifying the alert appears with status "new", acknowledging it, and resolving it — verifying each status change persists.

**Acceptance Scenarios**:

1. **Given** pattern alerts exist with various statuses, **When** an admin opens the Alerts tab, **Then** they see a list of alerts showing severity, rule name, affected equipment/fault, status, and detection date.
2. **Given** an alert with status "new", **When** an admin marks it as acknowledged, **Then** the alert status updates to "acknowledged" and persists on refresh.
3. **Given** an alert with status "acknowledged", **When** an admin marks it as resolved, **Then** the alert status updates to "resolved" and persists on refresh.
4. **Given** many alerts exist, **When** an admin views the Alerts tab, **Then** alerts are sorted by detection date (newest first) and can be filtered by status and severity.

---

### User Story 4 - Manual Full Scan (Priority: P3)

An administrator triggers a full scan that runs all active rules against every record in the work_order_entities table and creates alerts for any new matches not already recorded. Deduplication uses rule ID + equipment_id + fault_type + calendar month — so the same pattern re-alerts each month but does not duplicate within a month. This is useful after enabling a new rule or after bulk data imports.

**Why this priority**: Complements the real-time trigger by allowing retroactive pattern detection. Needed when rules are added or modified after data already exists.

**Independent Test**: Can be tested by creating a new rule, then triggering a full scan and verifying alerts are created for historical data that matches the rule.

**Acceptance Scenarios**:

1. **Given** a newly created active rule and existing historical entity data that matches it, **When** a full scan is triggered, **Then** alerts are created for all matching patterns in the historical data.
2. **Given** an alert that already exists for a specific rule + equipment_id + fault_type in the current calendar month, **When** a full scan runs, **Then** no duplicate alert is created for that combination in this month.
3. **Given** an alert that was created last month for a rule + equipment_id + fault_type, **When** a full scan runs this month and the pattern still matches, **Then** a new alert is created for this month.
4. **Given** 500 entity records and 6 active rules, **When** a full scan is triggered, **Then** the scan completes and returns a summary of how many rules were evaluated and how many alerts were created.

---

### User Story 5 - Built-in Rules Seeded Automatically (Priority: P2)

On first system startup (or when no rules exist), six predefined pattern rules are automatically seeded into the rules table. These cover recurring faults, technician patterns, procedure deviations, seasonal patterns, long resolution times, and parts-replaced-but-fault-recurs scenarios.

**Why this priority**: The system must be useful out of the box without requiring admin configuration. These six rules represent common aviation maintenance patterns.

**Independent Test**: Can be tested by starting the system with an empty rules table and verifying all six rules appear with correct names, descriptions, severities, and default thresholds.

**Acceptance Scenarios**:

1. **Given** an empty pattern_rules table, **When** the pattern engine initializes, **Then** six built-in rules are created with their default configurations.
2. **Given** the six built-in rules already exist, **When** the system restarts, **Then** no duplicate rules are created.

---

### Edge Cases

- What happens when the work_order_entities record has null or empty fields that a rule depends on (e.g., empty equipment_id)? The rule should skip that record without error.
- What happens when a full scan is triggered while an entity extraction is in progress? The operations should not conflict — each creates its own alerts independently.
- What happens when an admin saves a rule with invalid detection parameters? The system should validate parameters before saving and display a clear error message.
- What happens when no entities exist in the table and a full scan runs? The scan should complete successfully with zero alerts.
- What happens when a rule's threshold is set to 0 or a negative number? The system should enforce minimum threshold values (count >= 1, days >= 1).
- What happens when pattern evaluation fails during triggered mode? The failure is logged silently and does not affect the entity extraction result.
- What happens when an admin tries to transition an alert to an invalid status (e.g., resolved → new)? The system should enforce valid transitions: new → acknowledged → resolved (no backwards transitions).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST automatically evaluate all active pattern rules against a work order's entities immediately after entity extraction completes, using fire-and-forget execution (failures logged, never blocking extraction).
- **FR-002**: System MUST store pattern rules persistently with fields: name, description, severity (low/medium/high), detection type, detection logic parameters, threshold values, and enabled flag.
- **FR-003**: System MUST seed six built-in rules on first initialization when no rules exist: recurring fault threshold, same technician recurring fault, procedure deviation, seasonal pattern, long resolution time, and parts-replaced-but-fault-recurs.
- **FR-004**: System MUST store fired alerts persistently with references to the triggering rule, affected work orders/entities, severity, status (new/acknowledged/resolved), detection timestamp, and a human-readable message.
- **FR-005**: System MUST provide a full-scan capability that evaluates all active rules against all existing entity records and creates only new (non-duplicate) alerts, using rule ID + equipment_id + fault_type + calendar month as the deduplication key.
- **FR-006**: Admin users MUST be able to view, create, edit, toggle (enable/disable), and delete pattern rules through the Rules tab.
- **FR-007**: The Rules and Alerts tabs MUST be visible only to admin users.
- **FR-008**: System MUST validate rule parameters before saving (non-empty name, valid severity, positive threshold values).
- **FR-009**: Full scan MUST return a summary indicating how many rules were evaluated and how many alerts were created.
- **FR-010**: Custom rules MUST use the same structured detection types as the six built-in rules, with parameterized form fields (no raw SQL input).
- **FR-011**: Each built-in rule MUST have configurable thresholds that admins can adjust (e.g., occurrence count, time window in days).
- **FR-012**: System MUST skip entity records with missing required fields for a given rule rather than producing errors.
- **FR-013**: Admin users MUST be able to view all pattern alerts in the Alerts tab, sorted by detection date (newest first), with filtering by status and severity.
- **FR-014**: Admin users MUST be able to transition alert status through the lifecycle: new → acknowledged → resolved. Backwards transitions are not allowed.
- **FR-015**: Alert deduplication during full scan MUST reset monthly — the same pattern re-alerts in a new calendar month.

### Key Entities

- **Pattern Rule**: A detection rule with a name, description, severity level (low/medium/high), detection type identifier (one of six structured types matching the built-in rules), configurable thresholds (count, days), enabled status, and creation/update timestamps. Rules define what pattern to look for in work order entity data.
- **Pattern Alert**: A fired alert instance linking a pattern rule to the work orders/entities that triggered it. Contains the rule reference, affected entity identifiers (equipment_id, fault_type, technician_id as relevant), severity, status (new → acknowledged → resolved), a human-readable alert message, and the detection timestamp.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Pattern alerts are generated within 5 seconds of entity extraction completing for a work order that matches an active rule.
- **SC-002**: All six built-in rules are available and functional on first system use without manual configuration.
- **SC-003**: Admins can create a new custom rule and see it take effect on the next entity extraction within one interaction (no system restart needed).
- **SC-004**: Full scan of 1,000 entity records against 6 rules completes within 30 seconds.
- **SC-005**: The rules and alerts management interfaces are discoverable by admins within the existing application navigation (no separate application or URL needed).
- **SC-006**: Duplicate alerts are never created during full scans within the same calendar month — running the same scan twice in one month produces zero new alerts if no new data was added.
- **SC-007**: Pattern evaluation failures never block or delay entity extraction completion.

## Assumptions

- The existing work_order_entities table and entity extraction pipeline (spec 049) are fully functional and deployed.
- Admin role detection reuses the existing role-checking mechanism already present in ManualAssistantScreen (used for the Review Queue tab visibility).
- Pattern alerts are consumed downstream by a Layer 5 agent patterns tool (Component 3, separate spec) — this spec does not cover how alerts surface in chat responses.
- The six built-in rules use threshold-based detection logic (counts and time windows) with structured parameters, keeping rule management safe and accessible to non-technical admins.
- Rule creation by admins uses structured form fields (dropdown for detection type, dropdown for severity, numeric inputs for thresholds, text fields for entity field matching) rather than raw SQL input.
- The work_orders table has date fields sufficient to calculate resolution time for the "long resolution time" rule.
- The ManualAssistantScreen tab count will increase to 5 for admins (Chat, Knowledge, Review Queue, Rules, Alerts) and remain 2 for non-admins (Chat, Knowledge).
