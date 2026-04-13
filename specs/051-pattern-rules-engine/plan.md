# Implementation Plan: Pattern Rules Engine

**Branch**: `051-pattern-rules-engine` | **Date**: 2026-04-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/051-pattern-rules-engine/spec.md`

## Summary

Build a configurable pattern detection engine that evaluates SQL-based rules against the `work_order_entities` table and fires alerts when maintenance patterns are detected. Six built-in rules are seeded automatically. Admins manage rules and alerts through two new tabs in ManualAssistantScreen. The engine runs in two modes: triggered after each entity extraction (fire-and-forget) and manual full scan. Alerts follow a new → acknowledged → resolved lifecycle.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client (backend); http, supabase_flutter, Flutter Material (frontend)
**Storage**: Supabase (PostgreSQL) — new `pattern_rules` and `pattern_alerts` tables; existing `work_order_entities`, `work_orders` tables
**Testing**: Manual testing via PWA + backend logs
**Target Platform**: Web (PWA primary), Linux server (backend)
**Project Type**: Web application (Flutter frontend + FastAPI backend)
**Performance Goals**: Pattern evaluation <5s post-extraction; full scan of 1,000 entities against 6 rules <30s
**Constraints**: 15GB server RAM; pattern evaluation must be fire-and-forget (never block extraction); no raw SQL from users
**Scale/Scope**: ~500-1,000 work order entities; 6 built-in + custom rules; 5 admin tabs in ManualAssistantScreen

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Feature spans all layers: migration, backend router+service, Flutter model+service+screens, navigation wiring |
| II. Explicit Over Automatic | PASS | Alert status transitions are explicit (admin-driven new→acknowledged→resolved); rule seeding only when table is empty |
| III. Role-Based Access Control | PASS | Rules and Alerts tabs admin-only; API endpoints enforce admin role check; follows existing Review Queue pattern |
| IV. Server-First File Storage | N/A | No file uploads in this feature |
| V. Client-Side Computation | PASS | Rule evaluation is server-side (requires DB queries across entities); alert list filtering can be client-side |
| VI. Audit Everything | PASS | Rule CRUD and alert status changes will log to `user_activity_log` via fire-and-forget pattern |
| VII. Simplicity & YAGNI | PASS | Structured detection types only (no rule DSL/SQL editor); 6 predefined types matching built-in rules |

## Project Structure

### Documentation (this feature)

```text
specs/051-pattern-rules-engine/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── patterns.py                  # NEW: pattern rules + alerts API endpoints
├── services/
│   ├── entity_extractor.py          # MODIFIED: hook pattern evaluation after extraction
│   └── pattern_engine.py            # NEW: rule evaluation engine + seeding logic
└── ...

supabase/
└── migrations/
    └── 20260413200000_create_pattern_engine.sql  # NEW: pattern_rules + pattern_alerts tables

frontend/
├── lib/
│   ├── models/
│   │   ├── pattern_rule.dart        # NEW: PatternRule model
│   │   └── pattern_alert.dart       # NEW: PatternAlert model
│   ├── services/
│   │   └── pattern_service.dart     # NEW: API client for rules + alerts
│   └── screens/
│       └── manual_assistant/
│           ├── manual_assistant_screen.dart  # MODIFIED: add Rules + Alerts tabs (admin)
│           ├── rules_tab.dart               # NEW: rules list + CRUD
│           ├── rule_edit_screen.dart         # NEW: create/edit rule form
│           ├── alerts_tab.dart              # NEW: alerts list + status management
│           └── widgets/
│               ├── rule_card.dart           # NEW: rule list item
│               └── alert_card.dart          # NEW: alert list item
```

**Structure Decision**: Follows existing project layout — new router in `backend/routers/`, new service in `backend/services/`, Flutter screens in `manual_assistant/` directory matching the existing tab pattern (Chat, Knowledge, Review Queue).

## Phase 0: Research

See [research.md](research.md) for full findings.

**Key decisions**:
- Six structured detection types: `recurring_fault`, `technician_recurring`, `procedure_deviation`, `seasonal_pattern`, `long_resolution`, `parts_replaced_recurrence`
- Each type has a dedicated Python evaluation function — no dynamic SQL execution
- Dedup key for full scan: composite of `rule_id + equipment_id + fault_type + YYYY-MM`
- Pattern evaluation called as `await evaluate_patterns(work_order_id)` after entity upsert in entity_extractor.py, wrapped in try/except for fire-and-forget
- Tab count: admin sees 5 tabs (Chat, Knowledge, Review Queue, Rules, Alerts), non-admin sees 2

## Phase 1: Design

See [data-model.md](data-model.md) for entity definitions.
See [contracts/](contracts/) for API contracts.
See [quickstart.md](quickstart.md) for developer setup.

## Phase 2: Backend — Database Migration

**Goal**: Create `pattern_rules` and `pattern_alerts` tables in Supabase.

**Files**:
- `supabase/migrations/20260413200000_create_pattern_engine.sql` — CREATE TABLE for both tables with indexes

**Key details**:
- `pattern_alerts.dedup_key` gets a partial UNIQUE index: `CREATE UNIQUE INDEX idx_pattern_alerts_dedup_key ON pattern_alerts (dedup_key) WHERE dedup_key IS NOT NULL` — triggered-mode alerts have NULL dedup_key and bypass this constraint
- `pattern_rules.is_built_in` boolean DEFAULT false — informational flag, does NOT block deletion

**Acceptance**: Tables exist with correct columns, constraints, and indexes. Partial unique index on dedup_key verified. No RLS policies needed (backend uses service role key).

## Phase 3: Backend — Pattern Engine Service

**Goal**: Implement the core rule evaluation engine with six built-in detection functions.

**Files**:
- `backend/services/pattern_engine.py` — rule evaluation functions, seeding logic, full scan

**Key functions**:
- `seed_built_in_rules()` — insert 6 rules if table empty
- `evaluate_patterns(work_order_id: str)` — run all active rules against one work order's entities
- `full_scan()` — run all active rules against all entities, with dedup
- `_check_recurring_fault(entity, rule)` — count same fault_type + equipment_id within days window
- `_check_technician_recurring(entity, rule)` — count same technician_id + fault_type
- `_check_procedure_deviation(entity, rule)` — normalized case-insensitive comparison of action_taken vs procedure_followed (both stripped + lowered); flags mismatch for human review; accepts false positives on free text
- `_check_seasonal_pattern(entity, rule)` — same equipment_type + fault_type in same month across years
- `_check_long_resolution(entity, rule)` — work order open-to-close exceeds threshold days; **CRITICAL: `date` column is TEXT type — must parse via `datetime.strptime(date_str, '%Y-%m-%d')` in Python or `TO_DATE(date, 'YYYY-MM-DD')` in SQL; skip records with unparseable dates**
- `_check_parts_replaced_recurrence(entity, rule)` — parts_replaced not empty + same fault recurs within days; same date parsing caveat applies

**Date parsing note**: All time-window rules (`recurring_fault`, `seasonal_pattern`, `long_resolution`, `parts_replaced_recurrence`) must defensively parse the text `date` column. Use try/except around `datetime.strptime()` and skip entities with invalid dates per FR-012.

**Acceptance**: Each function correctly detects its pattern type. Date parsing handles text-type date column safely. Seeding creates exactly 6 rules. Full scan deduplicates by rule_id + equipment_id + fault_type + YYYY-MM.

## Phase 4: Backend — Entity Extractor Integration

**Goal**: Hook pattern evaluation into entity_extractor.py as fire-and-forget.

**Files**:
- `backend/services/entity_extractor.py` — add pattern evaluation call after entity upsert

**Change**: After the successful upsert at ~line 174, add:
```python
try:
    await evaluate_patterns(work_order_id)
except Exception as e:
    logger.warning(f"Pattern evaluation failed for {work_order_id}: {e}")
```

**Acceptance**: Entity extraction succeeds even if pattern evaluation fails. Pattern alerts are created when rules match.

## Phase 5: Backend — Patterns Router (API Endpoints)

**Goal**: Expose CRUD endpoints for rules and alerts management.

**Files**:
- `backend/routers/patterns.py` — all pattern-related API endpoints
- `backend/main.py` — register patterns router

**Endpoints**:
- `GET /api/patterns/rules` — list all rules
- `POST /api/patterns/rules` — create rule (admin)
- `PUT /api/patterns/rules/{rule_id}` — update rule (admin)
- `DELETE /api/patterns/rules/{rule_id}` — delete rule (admin, including built-in; is_built_in is informational only)
- `PATCH /api/patterns/rules/{rule_id}/toggle` — toggle enabled (admin)
- `GET /api/patterns/alerts` — list alerts (with status/severity filters)
- `PATCH /api/patterns/alerts/{alert_id}/status` — update alert status (admin)
- `POST /api/patterns/scan` — trigger full scan (admin)

**Acceptance**: All endpoints enforce admin role. CRUD operations persist correctly. Full scan returns summary. Alert status transitions enforce new→acknowledged→resolved.

## Phase 6: Backend — Audit Logging

**Goal**: Log rule CRUD and alert status changes to `user_activity_log`.

**Files**:
- `backend/routers/patterns.py` — add activity logging calls

**Acceptance**: Creating/editing/deleting rules and changing alert status all produce activity log entries with category `pattern` and appropriate action verbs.

## Phase 7: Frontend — Models & Service

**Goal**: Create Dart models and API service for pattern rules and alerts.

**Files**:
- `frontend/lib/models/pattern_rule.dart` — PatternRule model with fromJson/toJson
- `frontend/lib/models/pattern_alert.dart` — PatternAlert model with fromJson/toJson
- `frontend/lib/services/pattern_service.dart` — PatternService with methods for all API endpoints

**Acceptance**: Models correctly parse API responses. Service methods handle auth headers, error codes, and return typed data.

## Phase 8: Frontend — Rules Tab & Edit Screen

**Goal**: Build the admin Rules tab and rule create/edit form.

**Files**:
- `frontend/lib/screens/manual_assistant/rules_tab.dart` — rules list with toggle, edit, delete
- `frontend/lib/screens/manual_assistant/rule_edit_screen.dart` — create/edit form with detection type dropdown, severity dropdown, threshold fields
- `frontend/lib/screens/manual_assistant/widgets/rule_card.dart` — rule list item widget with severity badge (high=red, medium=amber, low=green), enabled toggle, and "Built-in" chip for is_built_in rules

**Acceptance**: Admin can view rules list, toggle enable/disable, create new rule (selecting detection type, thresholds), edit existing rule, delete rule. Severity badges use correct colors. Non-admin cannot access.

## Phase 9: Frontend — Alerts Tab

**Goal**: Build the admin Alerts tab with status management.

**Files**:
- `frontend/lib/screens/manual_assistant/alerts_tab.dart` — alerts list with filters
- `frontend/lib/screens/manual_assistant/widgets/alert_card.dart` — alert list item with status actions

**Severity color mapping**:
- `high` → `Colors.red` (red badge)
- `medium` → `Colors.amber` (amber badge)
- `low` → `Colors.green` (green badge)

**Status indicators**: "new" = bold/unread style, "acknowledged" = normal weight, "resolved" = muted/grey text.

**Acceptance**: Admin sees alerts sorted newest-first, can filter by status/severity, can transition new→acknowledged→resolved. Severity badges use correct color mapping (high=red, medium=amber, low=green). Non-admin cannot access.

## Phase 10: Frontend — ManualAssistantScreen Tab Integration

**Goal**: Wire Rules and Alerts tabs into ManualAssistantScreen for admin users.

**Files**:
- `frontend/lib/screens/manual_assistant/manual_assistant_screen.dart` — increase tab count to 5 for admins, add Rules and Alerts tabs

**Change**: Update `TabController(length: _isAdmin ? 5 : 2, vsync: this)` and add conditional tabs/views for Rules and Alerts after Review Queue. Uses the same `_isAdmin` flag (from existing `widget.userRole == 'admin'` check) that gates Review Queue visibility — wrap both new tabs in the same `if (_isAdmin)` conditional block.

**Acceptance**: Admin sees 5 tabs (Chat, Knowledge, Review Queue, Rules, Alerts). Non-admin sees 2 tabs (Chat, Knowledge). Both new tabs gated by `_isAdmin` check, same pattern as Review Queue. Tab switching works correctly.

## Phase 11: Seed & Integration Testing

**Goal**: Verify end-to-end flow: seed rules → extract entities → alerts fire → admin views/manages.

**Steps**:
1. Apply migration, restart backend — verify 6 rules seeded
2. Extract entities for a work order matching "recurring fault" rule — verify alert created with status "new"
3. Trigger full scan — verify no duplicates in same month
4. Admin: view rules, toggle one off, create custom rule
5. Admin: view alerts, acknowledge one, resolve one
6. Verify pattern evaluation failure doesn't block extraction

**Acceptance**: All 6 built-in rules functional. CRUD works. Alert lifecycle works. Fire-and-forget verified.

## Complexity Tracking

No constitution violations. No complexity justifications needed.
