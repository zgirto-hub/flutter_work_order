# Tasks: Pattern Rules Engine

**Input**: Design documents from `/specs/051-pattern-rules-engine/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api.md
**Branch**: `051-pattern-rules-engine`

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks grouped by user story. Each story is independently implementable and testable after the foundational phase completes.

**Target implementer**: Another LLM (opencode) executing tasks sequentially. Each task includes exact file paths and references to design docs for complete context.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Database migration — creates the two new tables that all other work depends on.

- [ ] T001 Create Supabase migration file `supabase/migrations/20260413200000_create_pattern_engine.sql` with two tables: `pattern_rules` and `pattern_alerts`. Schema defined in `specs/051-pattern-rules-engine/data-model.md`. Key details: (1) `pattern_rules` has columns: id (uuid PK default gen_random_uuid()), name (text NOT NULL), description (text), severity (text NOT NULL CHECK IN ('low','medium','high')), detection_type (text NOT NULL CHECK IN ('recurring_fault','technician_recurring','procedure_deviation','seasonal_pattern','long_resolution','parts_replaced_recurrence')), threshold_count (integer DEFAULT 3), threshold_days (integer DEFAULT 180), target_field (text DEFAULT 'equipment_id'), group_by_field (text), enabled (boolean NOT NULL DEFAULT true), is_built_in (boolean NOT NULL DEFAULT false), created_at (timestamptz NOT NULL DEFAULT now()), updated_at (timestamptz NOT NULL DEFAULT now()). (2) `pattern_alerts` has columns: id (uuid PK default gen_random_uuid()), rule_id (uuid NOT NULL FK references pattern_rules(id) ON DELETE CASCADE), work_order_ids (uuid[] NOT NULL), equipment_id (text), fault_type (text), technician_id (text), severity (text NOT NULL CHECK IN ('low','medium','high')), status (text NOT NULL DEFAULT 'new' CHECK IN ('new','acknowledged','resolved')), message (text NOT NULL), dedup_key (text), detected_at (timestamptz NOT NULL DEFAULT now()), updated_at (timestamptz NOT NULL DEFAULT now()). (3) Create indexes: idx_pattern_alerts_rule_id ON pattern_alerts(rule_id), idx_pattern_alerts_status ON pattern_alerts(status), idx_pattern_alerts_detected_at ON pattern_alerts(detected_at DESC), and a PARTIAL UNIQUE index: CREATE UNIQUE INDEX idx_pattern_alerts_dedup_key ON pattern_alerts(dedup_key) WHERE dedup_key IS NOT NULL. The partial unique index means triggered-mode alerts (NULL dedup_key) bypass uniqueness, while full-scan alerts are deduplicated.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Backend pattern engine service with all six detection functions + seeding logic, plus Flutter models and API service. MUST complete before any user story phase.

**CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T002 Create `backend/services/pattern_engine.py` — the core pattern evaluation engine. This file contains ALL detection logic. Import supabase client from existing `backend/supabase_client.py` (or however the project initializes it — check `backend/services/entity_extractor.py` for the import pattern). Import logging. Define these async functions: (1) `async def seed_built_in_rules()` — check if pattern_rules table is empty via SELECT COUNT(*), if 0 then INSERT the 6 built-in rules with is_built_in=true. The 6 rules are defined in `specs/051-pattern-rules-engine/research.md` Decision 2: recurring_fault (count=3, days=180, severity=high, target=equipment_id), technician_recurring (count=3, days=null, severity=medium, target=technician_id), procedure_deviation (no thresholds, severity=high), seasonal_pattern (count=2 for years, days=null, severity=low, target=equipment_type, group_by=fault_type), long_resolution (count=null, days=14, severity=medium), parts_replaced_recurrence (count=null, days=30, severity=high, target=equipment_id). (2) `async def evaluate_patterns(work_order_id: str)` — fetch the entity from work_order_entities WHERE work_order_id=param, fetch all active rules WHERE enabled=true, for each rule call the appropriate _check function based on detection_type, if check returns a match then INSERT into pattern_alerts with status='new', dedup_key=NULL (triggered mode). (3) `async def full_scan()` — fetch all active rules, fetch all entities, for each rule+entity combination call the check function, if match then construct dedup_key as f"{rule_id}:{equipment_id}:{fault_type}:{YYYY-MM}" (using the entity's date parsed to get year-month), check if alert with that dedup_key already exists, if not then INSERT. Return dict with rules_evaluated, alerts_created, alerts_skipped_duplicate, duration_seconds.

- [ ] T003 In the same file `backend/services/pattern_engine.py`, implement the six detection check functions. CRITICAL: the `date` column in work_order_entities is TEXT type, not timestamp. All date comparisons must use `datetime.strptime(date_str, '%Y-%m-%d')` wrapped in try/except — skip records with unparseable dates. (1) `async def _check_recurring_fault(entity, rule)` — query work_order_entities for COUNT where equipment_id matches AND fault_type matches AND date is within rule.threshold_days of the current entity's date. Use TO_DATE(date, 'YYYY-MM-DD') in SQL for date arithmetic, or parse in Python. Return True if count >= rule.threshold_count. Also return the list of matching work_order_ids for the alert. (2) `async def _check_technician_recurring(entity, rule)` — COUNT where technician_id matches AND fault_type matches (no time window). Return True if count >= rule.threshold_count. (3) `async def _check_procedure_deviation(entity, rule)` — check if BOTH action_taken and procedure_followed are non-empty strings, then compare them after stripping whitespace and lowercasing. If they differ, return True. This is a per-entity check (no cross-entity query needed). (4) `async def _check_seasonal_pattern(entity, rule)` — extract calendar month from entity date, query for DISTINCT years where same equipment_type + fault_type appear in the same calendar month. Return True if distinct year count >= rule.threshold_count (default 2). (5) `async def _check_long_resolution(entity, rule)` — join with work_orders table to get created_at and resolved_date (or closed_at — check what columns work_orders has). Calculate day difference. Return True if difference > rule.threshold_days. Skip if work order is not resolved. (6) `async def _check_parts_replaced_recurrence(entity, rule)` — check if entity.parts_replaced is non-empty array, then query for same equipment_id + fault_type within rule.threshold_days AFTER this entity's date. Return True if any subsequent fault exists. For each function, handle None/empty field values gracefully — return False and skip (FR-012).

- [ ] T004 [P] Create `frontend/lib/models/pattern_rule.dart` — Dart model class PatternRule with fields matching the API response from `specs/051-pattern-rules-engine/contracts/api.md` GET /api/patterns/rules: id (String), name (String), description (String?), severity (String), detectionType (String), thresholdCount (int), thresholdDays (int), targetField (String), groupByField (String?), enabled (bool), isBuiltIn (bool), createdAt (DateTime), updatedAt (DateTime). Include factory PatternRule.fromJson(Map<String, dynamic> json) and Map<String, dynamic> toJson() methods. Use the same JSON key naming as the API (snake_case in JSON, camelCase in Dart).

- [ ] T005 [P] Create `frontend/lib/models/pattern_alert.dart` — Dart model class PatternAlert with fields matching the API response from contracts/api.md GET /api/patterns/alerts: id (String), ruleId (String), ruleName (String), workOrderIds (List<String>), equipmentId (String?), faultType (String?), technicianId (String?), severity (String), status (String), message (String), detectedAt (DateTime), updatedAt (DateTime). Include factory PatternAlert.fromJson(Map<String, dynamic> json) and Map<String, dynamic> toJson(). Parse work_order_ids as List<String> from JSON array.

- [ ] T006 Create `frontend/lib/services/pattern_service.dart` — API client class PatternService. Follow the exact same pattern as `frontend/lib/services/manual_assistant_service.dart`: get auth token from Supabase.instance.client.auth.currentSession?.accessToken, set Authorization header, use AppConfig.baseUrl. Implement methods for all 8 endpoints defined in contracts/api.md: (1) `Future<List<PatternRule>> getRules()` — GET /api/patterns/rules, parse response.rules list. (2) `Future<PatternRule> createRule(Map<String, dynamic> body)` — POST /api/patterns/rules. (3) `Future<PatternRule> updateRule(String ruleId, Map<String, dynamic> body)` — PUT /api/patterns/rules/{ruleId}. (4) `Future<void> deleteRule(String ruleId)` — DELETE /api/patterns/rules/{ruleId}. (5) `Future<PatternRule> toggleRule(String ruleId)` — PATCH /api/patterns/rules/{ruleId}/toggle. (6) `Future<Map<String, dynamic>> getAlerts({String? status, String? severity, int page = 1, int pageSize = 20})` — GET /api/patterns/alerts with query params, return map with 'alerts' (List<PatternAlert>), 'total' (int), 'page', 'page_size'. (7) `Future<PatternAlert> updateAlertStatus(String alertId, String status)` — PATCH /api/patterns/alerts/{alertId}/status. (8) `Future<Map<String, dynamic>> triggerScan()` — POST /api/patterns/scan, return summary map. Handle 403 by throwing 'Admin access required'. Handle 400 by throwing the error message from response body.

**Checkpoint**: Foundation ready — pattern_engine.py has all detection logic, Flutter has models + service. User story implementation can now begin.

---

## Phase 3: User Story 1 — Automatic Pattern Detection (Priority: P1) MVP

**Goal**: After entity extraction completes, the system automatically evaluates all active pattern rules against the extracted entity and fires alerts for matches. This is fire-and-forget — failures never block extraction.

**Independent Test**: Extract entities for a work order where the equipment+fault combination already has 2 prior occurrences within 6 months. Verify a "recurring fault threshold" alert is created with status "new" in the pattern_alerts table. Then verify that if pattern evaluation is deliberately broken (e.g., pattern_rules table doesn't exist), entity extraction still succeeds.

- [ ] T007 [US1] Modify `backend/services/entity_extractor.py` — add fire-and-forget pattern evaluation hook. At the top, add import: `from services.pattern_engine import evaluate_patterns`. In the `extract_entities()` function, AFTER the successful upsert to work_order_entities (around line 174, after `supabase.table("work_order_entities").upsert(payload).execute()`), add a try/except block: `try: await evaluate_patterns(work_order_id) except Exception as e: logger.warning(f"Pattern evaluation failed for {work_order_id}: {e}")`. This ensures extraction always returns parsed_data regardless of pattern evaluation outcome. Do NOT move or modify any existing code — only add the try/except block after the upsert.

- [ ] T008 [US1] Call `seed_built_in_rules()` on backend startup so rules exist for evaluation. In `backend/main.py`, add import `from services.pattern_engine import seed_built_in_rules` and add a startup event handler (FastAPI lifespan or @app.on_event("startup")) that calls `await seed_built_in_rules()`. Check how other startup logic is done in main.py and follow that pattern. This ensures the 6 built-in rules are created if the table is empty when the server starts.

**Checkpoint**: US1 complete. Entity extraction now triggers pattern evaluation. Alerts are created for matching patterns. Failures are silently logged. The 6 built-in rules are auto-seeded on startup.

---

## Phase 4: User Story 5 — Built-in Rules Seeded Automatically (Priority: P2)

**Goal**: Verify and ensure the 6 built-in rules are correctly defined and seeded. This was partially done in T008 (startup hook) and T002 (seed function), but this phase ensures the exact rule definitions are correct.

**Independent Test**: Delete all rows from pattern_rules, restart the backend, then GET /api/patterns/rules and verify exactly 6 rules appear with correct names, severities, detection types, and thresholds.

- [ ] T009 [US5] Review and verify the 6 built-in rule definitions in `backend/services/pattern_engine.py` seed_built_in_rules() match these exact specifications: Rule 1 "Recurring fault threshold" — detection_type='recurring_fault', severity='high', threshold_count=3, threshold_days=180, target_field='equipment_id', description='Same fault_type on same equipment_id 3+ times within 6 months. Replacement may be mandatory per manual rule.' Rule 2 "Same technician recurring fault" — detection_type='technician_recurring', severity='medium', threshold_count=3, threshold_days=NULL, target_field='technician_id', group_by_field='fault_type', description='Same technician handles same fault_type 3+ times. Training or procedure review needed.' Rule 3 "Procedure deviation" — detection_type='procedure_deviation', severity='high', threshold_count=NULL, threshold_days=NULL, description='action_taken does not match procedure_followed. Flag for senior engineer review.' Rule 4 "Seasonal pattern" — detection_type='seasonal_pattern', severity='low', threshold_count=2, threshold_days=NULL, target_field='equipment_type', group_by_field='fault_type', description='Same equipment_type and fault_type recurs in the same calendar month across 2+ years. Recommend preventive check.' Rule 5 "Long resolution time" — detection_type='long_resolution', severity='medium', threshold_count=NULL, threshold_days=14, description='Work order resolution exceeds 14 days for this fault_type. Escalation needed.' Rule 6 "Parts replaced but fault recurs" — detection_type='parts_replaced_recurrence', severity='high', threshold_count=NULL, threshold_days=30, target_field='equipment_id', description='Parts replaced but same fault_type recurs on same equipment within 30 days. Part quality or installation issue.' All 6 must have is_built_in=true, enabled=true.

**Checkpoint**: US5 complete. All 6 built-in rules are correctly defined and auto-seed on empty table.

---

## Phase 5: User Story 2 — Admin Manages Pattern Rules (Priority: P2)

**Goal**: Admin users can view, create, edit, toggle, and delete pattern rules through a Rules tab in ManualAssistantScreen and a rule edit screen. Custom rules use the same 6 structured detection types as built-in rules.

**Independent Test**: Log in as admin, navigate to ManualAssistantScreen, see Rules tab. Create a new rule with detection_type='recurring_fault', threshold_count=5. Edit it to change threshold to 10. Toggle it off. Delete it. Verify non-admin user does NOT see the Rules tab.

### Backend — Rules API

- [ ] T010 [P] [US2] Create `backend/routers/patterns.py` — FastAPI router for pattern rules and alerts. Create `router = APIRouter(tags=["patterns"])`. Implement these rules endpoints per contracts/api.md: (1) `GET /patterns/rules` — query pattern_rules table ordered by created_at, return {"rules": [...]}. (2) `POST /patterns/rules` — validate body (name non-empty, severity in [low/medium/high], detection_type in the 6 valid types, threshold_count >= 1 if provided, threshold_days >= 1 if provided), insert into pattern_rules with is_built_in=false, return 201 with created rule. (3) `PUT /patterns/rules/{rule_id}` — fetch rule by id (404 if not found), update only provided fields, set updated_at=now(), return updated rule. (4) `DELETE /patterns/rules/{rule_id}` — fetch rule by id (404 if not found), delete (CASCADE will remove alerts), return {"deleted": true}. is_built_in does NOT block deletion. (5) `PATCH /patterns/rules/{rule_id}/toggle` — fetch rule, flip enabled boolean, set updated_at=now(), return updated rule. For admin enforcement: check the requesting user's role from the JWT/auth context using the same pattern as existing admin-protected endpoints in the project (check `backend/routers/manuals.py` for how admin role is verified). Return 403 if not admin.

- [ ] T011 [US2] Register the patterns router in `backend/main.py` — add `from routers import patterns` and `app.include_router(patterns.router, prefix="/api")`. Place it near the other router registrations (look at how manuals router is registered).

### Frontend — Rules Tab & Edit Screen

- [ ] T012 [P] [US2] Create `frontend/lib/screens/manual_assistant/widgets/rule_card.dart` — a widget that displays a single pattern rule in a Card/ListTile. Show: rule name (bold), description (subtitle, truncated), severity badge using colored Container (high=Colors.red, medium=Colors.amber, low=Colors.green with white text), detection_type as a Chip, enabled toggle Switch that calls onToggle callback, and a PopupMenuButton with Edit and Delete options. If rule.isBuiltIn is true, show a small "Built-in" Chip. Follow the visual style of existing card widgets in the project (check `frontend/lib/screens/manual_assistant/widgets/` for reference).

- [ ] T013 [US2] Create `frontend/lib/screens/manual_assistant/rules_tab.dart` — a StatefulWidget similar to `frontend/lib/screens/manual_assistant/review_queue_tab.dart`. Constructor takes userEmail (String). Has a public reload() method. State: _loading (bool), _error (String?), _rules (List<PatternRule>). On init, call PatternService().getRules() and populate _rules. Build: if loading show CircularProgressIndicator, if error show error + retry button, if empty show EmptyState icon + "No pattern rules configured" message, else show a ListView.builder of RuleCard widgets. Each RuleCard's onToggle calls PatternService().toggleRule(rule.id) and updates the list. onEdit navigates to RuleEditScreen. onDelete shows confirmation dialog then calls PatternService().deleteRule(rule.id) and removes from list. Add a FloatingActionButton with Icons.add that navigates to RuleEditScreen(rule: null) for creating a new rule. After returning from RuleEditScreen, call reload().

- [ ] T014 [US2] Create `frontend/lib/screens/manual_assistant/rule_edit_screen.dart` — a full-screen form for creating or editing a rule. Constructor takes optional PatternRule? rule (null = create mode, non-null = edit mode). AppBar title: "Create Rule" or "Edit Rule". Form fields: (1) TextFormField for name (required, validator: non-empty). (2) TextFormField for description (optional, multiline). (3) DropdownButtonFormField for severity with items: low, medium, high. (4) DropdownButtonFormField for detection_type with items: recurring_fault, technician_recurring, procedure_deviation, seasonal_pattern, long_resolution, parts_replaced_recurrence — display human-readable labels (e.g., "Recurring Fault", "Technician Recurring"). (5) TextFormField for threshold_count (number input, validator: >= 1 when applicable). (6) TextFormField for threshold_days (number input, validator: >= 1 when applicable). (7) DropdownButtonFormField for target_field with items: equipment_id, equipment_type, fault_type, technician_id. (8) Switch for enabled (default true). Save button calls PatternService().createRule() or updateRule() and pops back. Show SnackBar on success or error.

**Checkpoint**: US2 complete. Admin can fully manage pattern rules through the UI. API validates all inputs. Non-admin blocked.

---

## Phase 6: User Story 3 — Admin Views and Manages Alerts (Priority: P2)

**Goal**: Admin users can view all pattern alerts in an Alerts tab, filter by status/severity, and transition alert status through the lifecycle: new → acknowledged → resolved.

**Independent Test**: With existing alerts in the database, log in as admin, navigate to Alerts tab. See alerts sorted newest-first. Filter by status "new". Tap acknowledge on an alert — verify status changes. Tap resolve — verify status changes. Verify backwards transitions are blocked.

### Backend — Alerts API

- [ ] T015 [US3] Add alerts endpoints to `backend/routers/patterns.py`. (1) `GET /patterns/alerts` — accept query params: status (optional), severity (optional), page (default 1), page_size (default 20). Query pattern_alerts table with optional WHERE clauses for status and severity, ORDER BY detected_at DESC, with LIMIT/OFFSET pagination. JOIN with pattern_rules to get rule name (rule_name = pattern_rules.name where pattern_alerts.rule_id = pattern_rules.id). Return {"alerts": [...], "total": count, "page": page, "page_size": page_size}. Admin only. (2) `PATCH /patterns/alerts/{alert_id}/status` — accept body {"status": "acknowledged"|"resolved"}. Fetch alert by id (404 if not found). Enforce valid transitions: if current status is "new" only allow "acknowledged", if current status is "acknowledged" only allow "resolved", if current status is "resolved" reject all changes. Return 400 with message "Invalid status transition: {current} → {requested}" on violation. Update status and updated_at=now(). Return updated alert with rule_name. Admin only.

### Frontend — Alerts Tab

- [ ] T016 [P] [US3] Create `frontend/lib/screens/manual_assistant/widgets/alert_card.dart` — a widget for displaying a single pattern alert. Show: severity badge (high=Colors.red, medium=Colors.amber, low=Colors.green), rule name (bold), message text, equipment_id and fault_type (if present), status badge, detected_at formatted as relative time or date. Style by status: "new" = bold text / slightly highlighted background, "acknowledged" = normal weight, "resolved" = muted grey text. Include action buttons: if status is "new" show "Acknowledge" button, if status is "acknowledged" show "Resolve" button, if "resolved" show no action buttons. Callbacks: onStatusChange(String newStatus).

- [ ] T017 [US3] Create `frontend/lib/screens/manual_assistant/alerts_tab.dart` — a StatefulWidget similar to review_queue_tab.dart. Constructor takes userEmail (String). Has public reload() method. State: _loading, _error, _alerts (List<PatternAlert>), _statusFilter (String? — null means all), _severityFilter (String? — null means all), _page (int), _total (int). On init, fetch alerts via PatternService().getAlerts(). Build: header row with two DropdownButton filters (status: All/New/Acknowledged/Resolved; severity: All/High/Medium/Low) and a refresh IconButton. Below header: if loading show indicator, if error show retry, if empty show "No pattern alerts" message, else show ListView.builder of AlertCard widgets. When filter changes, refetch with new params. AlertCard onStatusChange calls PatternService().updateAlertStatus(alertId, newStatus), then updates the alert in the local list. Add simple pagination at bottom (Previous/Next) if total > page_size. Pass an onCountChanged callback (for future badge on tab).

**Checkpoint**: US3 complete. Admin can view, filter, and manage alert lifecycle. Status transitions enforced.

---

## Phase 7: User Story 4 — Manual Full Scan (Priority: P3)

**Goal**: Admin can trigger a full scan that runs all active rules against all entities, creating only non-duplicate alerts (dedup by rule_id + equipment_id + fault_type + calendar month).

**Independent Test**: Create a new rule, trigger full scan via POST /api/patterns/scan, verify alerts are created for historical matching data. Run scan again — verify zero new alerts (all deduplicated). Check next month the same scan would create new alerts.

- [ ] T018 [US4] Add full scan endpoint to `backend/routers/patterns.py` — `POST /patterns/scan` (admin only). Call `await full_scan()` from pattern_engine.py. Return the summary dict: {"rules_evaluated": int, "alerts_created": int, "alerts_skipped_duplicate": int, "duration_seconds": float}. The full_scan() function in pattern_engine.py (implemented in T002/T003) handles all the dedup logic using the dedup_key partial unique index.

- [ ] T019 [US4] Add a "Scan" button to the Rules tab or Alerts tab in the frontend. In `frontend/lib/screens/manual_assistant/alerts_tab.dart` (or rules_tab.dart — choose alerts tab since that's where results appear), add an IconButton with Icons.radar or Icons.search in the header row. On tap, show a confirmation dialog "Run full pattern scan against all work order entities?", on confirm call PatternService().triggerScan(), show a SnackBar with the summary: "Scan complete: {alerts_created} alerts created, {alerts_skipped_duplicate} duplicates skipped in {duration_seconds}s", then reload the alerts list.

**Checkpoint**: US4 complete. Full scan works end-to-end with proper deduplication.

---

## Phase 8: Tab Integration — Wire Rules & Alerts into ManualAssistantScreen

**Purpose**: This phase wires the Rules and Alerts tabs into the existing ManualAssistantScreen, making them visible only to admin users.

- [ ] T020 Modify `frontend/lib/screens/manual_assistant/manual_assistant_screen.dart` — add Rules and Alerts tabs for admin users. Key changes: (1) Import rules_tab.dart and alerts_tab.dart at the top. (2) Change TabController length from `_isAdmin ? 3 : 2` to `_isAdmin ? 5 : 2`. (3) In the TabBar.tabs list, after the existing `if (_isAdmin)` block for Review Queue, add two more conditional tabs: `if (_isAdmin) Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.rule, size: 18), SizedBox(width: 4), Text('Rules')]))` and `if (_isAdmin) Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.notifications_active, size: 18), SizedBox(width: 4), Text('Alerts')]))`. (4) In the TabBarView.children list, after the existing ReviewQueueTab conditional, add: `if (_isAdmin) RulesTab(userEmail: widget.userEmail)` and `if (_isAdmin) AlertsTab(userEmail: widget.userEmail)`. (5) Create GlobalKey references for both tabs if you need parent-triggered reload (same pattern as _reviewQueueKey). The _isAdmin flag already exists and uses `widget.userRole == 'admin'` — do NOT change how it's determined.

**Checkpoint**: All tabs wired. Admin sees 5 tabs (Chat, Knowledge, Review Queue, Rules, Alerts). Non-admin sees 2 (Chat, Knowledge).

---

## Phase 9: Audit Logging & Polish

**Purpose**: Add activity logging for rule CRUD and alert status changes per Constitution Principle VI.

- [ ] T021 Add audit logging to `backend/routers/patterns.py` — after each successful mutation (create rule, update rule, delete rule, toggle rule, update alert status, trigger scan), log to `user_activity_log` table using the same fire-and-forget pattern as other routers (check `backend/utils/activity.py` or however existing routers log activities). Use category='pattern' and action verbs: 'created_rule', 'updated_rule', 'deleted_rule', 'toggled_rule', 'updated_alert_status', 'triggered_scan'. Include relevant details (rule name, alert id, etc.) in the log metadata.

- [ ] T022 Update `CLAUDE.md` to document the new pattern rules engine feature under Active Technologies and Recent Changes sections. Add entry: "051-pattern-rules-engine: Added Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client (backend); http, supabase_flutter, Flutter Material (frontend)" and storage: "Supabase (PostgreSQL) — new pattern_rules and pattern_alerts tables".

- [ ] T023 End-to-end validation: (1) Apply migration to Supabase. (2) Restart backend — verify 6 rules seeded (check logs or GET /api/patterns/rules). (3) Extract entities for a work order that should trigger "recurring fault" rule — verify alert created. (4) Open PWA as admin — verify 5 tabs visible. (5) Rules tab: view 6 rules, toggle one off, create custom rule, edit it, delete it. (6) Alerts tab: view alerts, filter by severity, acknowledge one, resolve one. (7) Trigger full scan — verify summary and no duplicates. (8) Log in as non-admin — verify only 2 tabs visible. (9) Verify pattern evaluation failure does not break entity extraction (temporarily break pattern_engine import, extract entities, confirm success).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 (migration must exist before engine references tables)
- **Phase 3 (US1)**: Depends on Phase 2 (needs pattern_engine.py)
- **Phase 4 (US5)**: Depends on Phase 2 (needs seed function). Can run in parallel with Phase 3.
- **Phase 5 (US2)**: Depends on Phase 2 (needs models/service). Can run in parallel with Phase 3.
- **Phase 6 (US3)**: Depends on Phase 2. Can run in parallel with Phase 5.
- **Phase 7 (US4)**: Depends on Phase 2 (needs full_scan in pattern_engine)
- **Phase 8 (Tab Integration)**: Depends on Phase 5 + Phase 6 (needs both tab widgets to exist)
- **Phase 9 (Polish)**: Depends on all previous phases

### User Story Dependencies

- **US1 (P1)**: Independent after foundational. MVP candidate.
- **US5 (P2)**: Independent after foundational. Required for US1 to have rules to evaluate.
- **US2 (P2)**: Independent after foundational. Needs rules_tab.dart + rule_edit_screen.dart.
- **US3 (P2)**: Independent after foundational. Needs alerts_tab.dart.
- **US4 (P3)**: Independent after foundational. Needs full_scan endpoint.

### Within Each User Story

- Backend before frontend (API must exist before UI calls it)
- Models before services
- Services before screens
- Widgets before parent screens that use them

### Parallel Opportunities

- T004 + T005 (models) can run in parallel
- T010 + T012 (backend router + frontend widget) can run in parallel
- T016 can run in parallel with T015 (frontend widget + backend endpoint)
- Phase 3 (US1) + Phase 4 (US5) can run in parallel after Phase 2
- Phase 5 (US2) + Phase 6 (US3) can run in parallel after Phase 2

---

## Parallel Example: Foundational Phase

```text
# These can run in parallel (different files):
Task T004: Create PatternRule model in frontend/lib/models/pattern_rule.dart
Task T005: Create PatternAlert model in frontend/lib/models/pattern_alert.dart

# Then sequentially (T006 depends on T004 + T005):
Task T006: Create PatternService in frontend/lib/services/pattern_service.dart
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (migration)
2. Complete Phase 2: Foundational (engine + models + service)
3. Complete Phase 3: US1 (entity extractor hook + startup seeding)
4. **STOP and VALIDATE**: Extract entities, verify alert created in DB
5. This is a functional backend-only MVP — patterns detected automatically

### Incremental Delivery

1. Phase 1 + 2 → Foundation ready
2. + Phase 3 + 4 → Automatic detection working + rules seeded (Backend MVP)
3. + Phase 5 → Admin can manage rules (Rules tab)
4. + Phase 6 → Admin can manage alerts (Alerts tab)
5. + Phase 8 → Both tabs wired into ManualAssistantScreen
6. + Phase 7 → Full scan available
7. + Phase 9 → Audit logging + validation

### Sequential Execution (for single LLM implementer)

Execute tasks in order: T001 → T002 → T003 → T004 → T005 → T006 → T007 → T008 → T009 → T010 → T011 → T012 → T013 → T014 → T015 → T016 → T017 → T018 → T019 → T020 → T021 → T022 → T023

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story for traceability
- All file paths are relative to repository root (`c:\Development\flutter_work_order\`)
- Date column in work_order_entities is TEXT — always parse defensively
- Severity colors: high=red, medium=amber, low=green (everywhere)
- Admin check uses existing `_isAdmin` / `widget.userRole == 'admin'` pattern
- is_built_in is informational only — does NOT prevent deletion
- dedup_key is NULL for triggered alerts, populated for full-scan alerts
- Pattern evaluation failures are NEVER allowed to block entity extraction
- Commit after each task or logical group of tasks
