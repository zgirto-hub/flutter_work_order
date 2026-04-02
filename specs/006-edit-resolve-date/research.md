# Research: Edit Resolve Date

## R1: How is `resolved_at` currently stored and used?

**Decision**: Reuse the existing `resolved_at` column (nullable timestamp in `system_status_reports` table).

**Rationale**: The column already exists and stores ISO 8601 timestamps. The uptime calculation (recently updated) already reads `resolved_at` to compute downtime spans. No schema migration is needed.

**Alternatives considered**:
- Adding a separate `resolved_date` column (date-only): Rejected — introduces redundancy with `resolved_at` and requires migration.

## R2: Where should resolve date editing be triggered in the UI?

**Decision**: Two entry points:
1. **During resolution** (P2): Add an optional date picker to the existing resolve bottom sheet (`_showResolveSheet`).
2. **After resolution** (P1): Extend the existing edit bottom sheet (`_showEditIssueSheet`) to show a resolve date picker when the issue is already resolved.

**Rationale**: Reuses existing UI patterns (modal bottom sheets with date pickers). The edit sheet already has a date picker for `report_date` that can serve as a template.

**Alternatives considered**:
- Separate "Edit Resolve Date" button/sheet: Rejected — adds UI clutter and a new method when the existing edit sheet can be extended.
- Inline editing in the history list: Rejected — inconsistent with current interaction patterns.

## R3: Backend approach — new endpoint vs extend existing?

**Decision**: Extend existing endpoints:
1. Add optional `resolved_at` field to `UpdateIssueBody` model (for editing after resolution).
2. Add optional `resolved_at` field to `ResolveIssueBody` model (for setting during resolution).

**Rationale**: Keeps the API surface minimal. The PUT endpoint already handles conditional updates; adding another optional field follows the same pattern.

**Alternatives considered**:
- New dedicated PATCH endpoint for resolve date: Rejected — violates YAGNI; the PUT endpoint already updates issue fields.

## R4: Validation rules for resolve date

**Decision**: Server-side validation:
- `resolved_at` must be >= `report_date` (cannot resolve before issue was reported)
- `resolved_at` must be <= today (cannot resolve in the future)
- When editing via PUT, the issue must already be resolved (`resolved_at` is not null)

**Rationale**: Prevents logically impossible dates that would corrupt uptime calculations.

## R5: Date format handling

**Decision**: Frontend sends date as `YYYY-MM-DD` string. Backend converts to full ISO timestamp by appending `T23:59:59` (end of day) when receiving a date-only string, or uses `datetime.utcnow().isoformat()` as current default when no date is provided.

**Rationale**: The date picker in Flutter returns a `DateTime` but the user only selects a date (no time). Using end-of-day ensures the full resolution day counts as "resolved" in uptime calculations.

**Alternatives considered**:
- Send full timestamp from frontend: Rejected — time component is not meaningful for this feature.
- Use start-of-day (T00:00:00): Rejected — end-of-day better represents "resolved on this day" semantics.
