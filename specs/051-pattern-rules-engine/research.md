# Research: Pattern Rules Engine

**Date**: 2026-04-13 | **Branch**: `051-pattern-rules-engine`

## Decision 1: Detection Type Architecture

**Decision**: Six hardcoded detection type functions, one per built-in rule type. Custom rules select from the same six types with configurable parameters.

**Rationale**: Structured detection types with dedicated Python functions are safer than dynamic SQL execution from user input. Each function is testable, auditable, and cannot produce SQL injection. Admins configure thresholds via form fields — the detection logic is fixed per type.

**Alternatives considered**:
- Dynamic SQL WHERE clauses from admin input — rejected due to SQL injection risk and complexity for non-technical admins
- Rule DSL (custom expression language) — rejected per YAGNI; six types cover the identified use cases
- Stored procedures in PostgreSQL — rejected; keeps logic in Python where it's easier to debug and test

## Decision 2: Six Detection Types

**Decision**: The following detection type identifiers map to evaluation functions:

| Type ID | Built-in Rule | Parameters | Evaluation Logic |
|---------|--------------|------------|-----------------|
| `recurring_fault` | Recurring fault threshold | `threshold_count` (default 3), `threshold_days` (default 180) | COUNT entities with same equipment_id + fault_type within threshold_days |
| `technician_recurring` | Same technician recurring fault | `threshold_count` (default 3) | COUNT entities with same technician_id + fault_type (no time window) |
| `procedure_deviation` | Procedure deviation | (none) | Check action_taken and procedure_followed are both non-empty AND differ via case-insensitive normalized comparison (strip whitespace, lowercase). No similarity scoring or LLM call — this is a strict mismatch flag. Free-text fields may produce false positives; the alert message instructs senior engineer to review manually. |
| `seasonal_pattern` | Seasonal pattern | `threshold_years` (default 2) | Same equipment_type + fault_type in same calendar month across threshold_years distinct years |
| `long_resolution` | Long resolution time | `threshold_days` (default 14) | Work order open_date to close_date exceeds threshold_days |
| `parts_replaced_recurrence` | Parts replaced but fault recurs | `threshold_days` (default 30) | parts_replaced not empty + same fault_type on same equipment_id recurs within threshold_days |

**Rationale**: Each type addresses a distinct maintenance concern identified in the spec. Parameters are minimal and numeric, suitable for form-field editing.

**Rationale**: Each type addresses a distinct maintenance concern identified in the spec. Parameters are minimal and numeric, suitable for form-field editing.

**Procedure deviation note**: Rule 3 compares free-text fields (action_taken vs procedure_followed). A strict normalized string comparison will produce false positives when technicians use different wording for the same procedure. Alternatives considered:
- Embedding similarity score (cosine threshold) — rejected for v1; adds Ollama dependency to every pattern check, increasing latency
- Gemma LLM call to judge equivalence — rejected; too slow for fire-and-forget and would consume server RAM
- Exact match after normalization — **chosen**; simplest, fast, and the alert message explicitly says "flag for senior engineer review" — false positives are acceptable because a human reviews every hit

Future improvement: if false positive rate is too high, add embedding-based similarity as an optional threshold parameter for this detection type.

**Alternatives considered**:
- Combining recurring_fault and technician_recurring into one type with optional grouping — rejected for clarity; they serve different purposes (equipment focus vs technician focus)

## Decision 3: Fire-and-Forget Integration Pattern

**Decision**: Call `await evaluate_patterns(work_order_id)` inside a try/except block after the entity upsert in `entity_extractor.py`. Failures are logged at WARNING level.

**Rationale**: Entity extraction is the critical path (spec 049). Pattern evaluation is an enhancement that must never degrade the extraction pipeline. The existing `entity_extractor.py` returns the parsed data after upsert — pattern evaluation runs between upsert and return.

**Alternatives considered**:
- Background task queue (Celery, asyncio.create_task) — rejected per YAGNI; synchronous-within-try/except is simpler and evaluation should complete in <5s
- Separate cron job — rejected; real-time detection after extraction is a spec requirement

## Decision 4: Deduplication Strategy

**Decision**: Full scan dedup key is `rule_id + equipment_id + fault_type + YYYY-MM` (calendar month). Triggered mode (post-extraction) always creates new alerts without dedup checking.

**Rationale**: Monthly reset allows recurring patterns to re-surface for review each period. Triggered mode fires independently because each new extraction represents a genuinely new event. Full scan needs dedup because it re-evaluates all historical data.

**Alternatives considered**:
- Hash of matching work_order_ids — rejected; fragile when new work orders are added
- No dedup (always create) — rejected for full scan; would create hundreds of duplicates

## Decision 5: Alert Lifecycle Implementation

**Decision**: Alert `status` column with CHECK constraint (`new`, `acknowledged`, `resolved`). Transitions enforced in the API endpoint: new→acknowledged, acknowledged→resolved. No backwards transitions.

**Rationale**: Simple three-state lifecycle covers the triage workflow without overcomplicating the data model. Enforcement at API level (not database trigger) keeps logic visible and debuggable.

**Alternatives considered**:
- Database-level trigger enforcing transitions — rejected; harder to debug, and we use service role key
- Free-form status with no transition enforcement — rejected; spec requires ordered lifecycle

## Decision 6: Tab Ordering in ManualAssistantScreen

**Decision**: Admin tabs ordered as: Chat, Knowledge, Review Queue, Rules, Alerts. TabController length changes from `_isAdmin ? 3 : 2` to `_isAdmin ? 5 : 2`.

**Rationale**: Keeps existing tabs in place (no disruption to admin muscle memory). Rules before Alerts because rules are configured less frequently — alerts (the action-oriented tab) is rightmost for quick access.

**Alternatives considered**:
- Alerts before Rules — considered but Rules is the setup step, Alerts is the monitoring step; logical left-to-right flow
- Separate navigation destination — rejected per spec; ManualAssistantScreen is the home for AI-related admin tools

## Decision 7: Custom Rule Field Matching

**Decision**: Custom rules specify `target_field` (dropdown from work_order_entities columns: equipment_id, equipment_type, fault_type, technician_id) and `group_by_field` (optional second field for aggregation). Combined with detection type and thresholds, this covers all six built-in patterns and allows admins to create variations.

**Rationale**: The six detection types operate on different field combinations. Rather than hardcoding fields per type, allowing field selection makes the same types reusable for custom rules (e.g., recurring_fault by equipment_type instead of equipment_id).

**Alternatives considered**:
- Fixed fields per detection type — simpler but limits custom rule flexibility
- Arbitrary field expressions — rejected per YAGNI and safety

## Decision 8: Date Parsing for Text-Type Date Column

**Decision**: The `work_order_entities.date` column is `text` type (not timestamp). All date-dependent rules (`recurring_fault`, `seasonal_pattern`, `long_resolution`, `parts_replaced_recurrence`) MUST parse the date text using Python's `datetime.strptime(date_str, '%Y-%m-%d')` with a try/except fallback that skips unparseable dates. SQL queries using this column MUST cast via `TO_DATE(date, 'YYYY-MM-DD')`.

**Rationale**: The entity extraction LLM outputs dates as text strings. Assuming timestamp type would crash at runtime. Defensive parsing with skip-on-failure aligns with FR-012 (skip records with missing/invalid fields).

**Alternatives considered**:
- Migrating the date column to timestamptz — rejected; would break existing spec 049 extraction pipeline
- Parsing only in Python (no SQL cast) — rejected; some queries (seasonal, recurring within window) are more efficient as SQL with proper date casting

## Decision 9: Built-in Rule Deletion Policy

**Decision**: Built-in rules (`is_built_in = true`) are deletable by admins. The DELETE endpoint does NOT block deletion of built-in rules. The `is_built_in` flag is informational only — it marks which rules were auto-seeded so the UI can display a "built-in" badge. If all rules are deleted, the next seed check (on startup) will re-create the 6 built-in rules.

**Rationale**: The spec (User Story 2, Scenario 6) explicitly allows deletion of any rule. Blocking deletion of built-in rules adds complexity for no clear user benefit — admins who want a clean slate should be able to get one. Re-seeding on empty table provides a safety net.

**Alternatives considered**:
- Block deletion of built-in rules (403) — rejected; contradicts spec and limits admin control
- Soft-delete with hidden flag — rejected per YAGNI

## Decision 10: Alert Severity Color Mapping (Frontend)

**Decision**: Alert and rule severity badges use consistent color coding across the UI:
- `high` → red (`Colors.red`)
- `medium` → amber (`Colors.amber`)
- `low` → green (`Colors.green`)

**Rationale**: Standard traffic-light convention. Matches existing severity/status badge patterns in the app (e.g., StatusBadge widget).
