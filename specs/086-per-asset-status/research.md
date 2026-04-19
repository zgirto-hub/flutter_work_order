# Phase 0 Research: Per-Asset System Status Reporting

**Feature**: 086-per-asset-status
**Date**: 2026-04-18
**Status**: Complete — no open NEEDS CLARIFICATION items

The brainstorming phase (superpowers:brainstorming skill) resolved every major decision before the spec was written. This file records each decision with its rationale and the alternatives considered, so future maintainers can understand *why* the spec is shaped the way it is.

---

## Decision 1 — Granularity: system-level AND asset-level coexist

**Decision**: Both levels of reporting are supported. An open system-level issue does NOT block an open asset-level issue on the same system for the same day (and vice versa). `asset_id` is nullable; NULL means system-level.

**Rationale**: Operators explicitly called out the case where the whole system is fine except for one asset (e.g., AIDA NG is healthy overall, but Damascus international circuit is degraded). Forcing the choice of "system OR asset" would either (a) corrupt system-level history for small issues or (b) hide issues that deserve visibility. Historical reports stay system-level (NULL asset) with no data migration — users accept the "prior data was whole-system" framing.

**Alternatives considered**:
- *Asset-only model (drop system-level entirely)* — rejected. Would force "the whole system is down" reports to be recorded against an arbitrary asset, or require a synthetic "system itself" asset row. Both are worse than nullable.
- *Retroactive migration of existing system-level reports into a guessed lead asset* — rejected. No signal exists to guess which asset caused a prior system-level issue; inventing links corrupts the dataset.

---

## Decision 2 — Surface: Status screen drill-in sheet (not Infrastructure screen)

**Decision**: Asset-issue reporting lives exclusively on the Status screen via a new drill-in bottom sheet. The Infrastructure screen (spec 061) is untouched — no status indicators, no reporting actions.

**Rationale**: Two surfaces with the same capability creates confusion about where to go and which is authoritative. The Status screen is already the operational surface; Infrastructure is the asset registry / structural view. Keeping the responsibilities separate mirrors how operators think about the two screens.

**Alternatives considered**:
- *Status reporting action added to Infrastructure detail screen* — rejected. Operators open Infrastructure for structural edits (link/unlink, change role/site), not operations. Mixing modes on one screen increases the chance of mis-taps during a real incident.
- *Status dots shown (read-only) on Infrastructure asset rows* — rejected for this spec; a reasonable future enhancement but currently out of scope to keep the delta minimal.

---

## Decision 3 — Card layout: two-state visual (dot for system + badge for assets)

**Decision**: System card shows:
- System status via the existing green/red dot + OK/Issue label.
- New amber badge "⚠ N" when any of the system's linked assets has an open report. Shown in addition to (not instead of) the system-level indicator.
- Red dot (system down) and amber badge (assets down) can coexist on the same card.

**Rationale**: Users explicitly wanted to preserve the distinction between "whole system is down" (red) and "an asset is down" (amber). A single blended indicator would lose that distinction. Amber was chosen over red for asset issues to establish a clear visual hierarchy: red = urgent system-wide; amber = localized asset. Using count ("⚠ 1", "⚠ 2") instead of a binary flag lets the operator see severity at a glance without drilling in.

**Alternatives considered**:
- *Rollup — show red if ANY asset is down* — rejected. Loses the system-vs-asset distinction; makes system-wide outage indistinguishable from one-asset-down.
- *Icon-only badge (no count)* — rejected. Adds cognitive load ("is it one asset or many?").
- *Badge on tap (tooltip)* — rejected. Operators need at-a-glance scanning; a tooltip on a tap-target defeats the purpose.

---

## Decision 4 — Data delivery: lazy-load assets on drill-in (not pre-fetched)

**Decision**: `GET /system-status/today` returns a lightweight `asset_issues_count` per system (one integer per system; drives the badge). The full asset list + per-asset status for a given system is fetched on demand via a new `GET /system-status/systems/{id}/assets` when the user opens the drill-in sheet.

**Rationale**: The grid is the hot path (refreshed on pull-to-refresh, on app resume, etc.). Embedding every asset for every system would 10× the payload on every grid load, even for systems the user never opens. The drill-in is a cold path (user tapped a specific card; one extra request of tens of milliseconds is fine). The one integer per system added to the today endpoint comes from the same query that already fetches open reports — grouped by `system_id` on the way out — so no extra Supabase round-trip is needed for the count.

**Alternatives considered**:
- *Embed full asset list in today endpoint* — rejected. Heaviest payload, worst change to the hot path.
- *Client-side merge of `GET /systems/{id}` + status data* — rejected. The client would have to replicate the "which asset has the open report" join logic already available server-side — two sources of truth, harder to keep consistent.

---

## Decision 5 — Uptime Report: always include per-asset breakdown (no flag)

**Decision**: The existing `GET /system-status/report` endpoint gains an `assets` array on every system entry — per-asset uptime stats (`total_days`, `days_with_issues`, `uptime_pct`, `downtime_pct`, plus metadata `asset_id`, `asset_name`, `role`, `site`). No query flag is introduced.

**Constitution check trigger**: an earlier draft of this decision proposed an `include_assets=true` query param to preserve backward compatibility for hypothetical future non-UI consumers. On post-design constitution re-evaluation (principle VII — Simplicity & YAGNI), the flag was removed because (a) the only caller today is this project's own frontend, (b) the frontend always wants the per-asset breakdown, and (c) with 24 systems × single-digit assets per system the extra payload is trivially small. A flag guarding against a non-existent consumer is precisely the kind of premature configurability the constitution prohibits.

Severity thresholds (deterministic integer-based) are applied client-side at render time:
- 🟢 Green: `days_with_issues == 0`
- 🟡 Amber: `days_with_issues > 0` AND `uptime_pct >= 95.0`
- 🔴 Red: `uptime_pct < 95.0`

**All-green shortcut**: when `system.days_with_issues == 0` AND every asset's `days_with_issues == 0`, the expanded uptime tile renders a single "All assets operational for the period" line (no per-asset rows). Defined on integer counts, not pct, to sidestep float-rounding ambiguity.

**Rationale**: The "which asset hurt us this month?" question is common. Expanding per-card (`ExpansionTile`) is cheap on the UI side. Integer-based thresholds match the existing `days_with_issues` field the backend already calculates; no new float precision contract between backend and frontend.

**Alternatives considered**:
- *Separate `/asset-status/report` endpoint* — rejected. Parallel endpoints with overlapping logic duplicate the date-range joining code in `get_uptime_report`.
- *Flat list — system cards AND asset cards at the same level* — rejected. Breaks the "one entry per system, drill in for details" mental model that matches the live Status screen grid.

---

## Decision 6 — Asset status rule: `resolved_at IS NULL`, date-independent

**Decision**: An asset's current status on `/system-status/systems/{id}/assets` is "issue" if ANY of that asset's reports is unresolved, regardless of the report's date. Identical to the existing rule for system-level status (at [backend/routers/system_status.py:55-62](../../backend/routers/system_status.py#L55-L62)).

**Rationale**: Consistency with system-level behavior — an issue opened yesterday and still unresolved is still an issue today. Any other rule would introduce date-based "issue reappears tomorrow" cliff edges that confuse operators.

**Alternatives considered**: none — existing pattern is correct and users confirmed expectations match.

---

## Decision 7 — Cascading delete on asset removal

**Decision**: `asset_id UUID NULL REFERENCES assets(id) ON DELETE CASCADE`. When an asset is deleted, its open and closed asset-level reports are removed with it.

**Rationale**: Open reports tied to a deleted asset would be unreachable in the UI (drill-in sheet lists only currently-linked assets). The cleanest semantics is "the asset no longer exists, so its operational history goes with it." Alternative preservation strategies (soft-delete, orphan queue) add surface area without a stated need.

**Alternatives considered**:
- *SET NULL on asset delete (report becomes system-level)* — rejected. Rewrites history and pollutes the system-level stream with orphans.
- *RESTRICT on asset delete* — rejected. Would block asset deletion until every past report is manually purged; friction for admins with no operational benefit.

---

## Decision 8 — Uniqueness: partial unique index with COALESCE sentinel (new DB-level protection)

**Decision**: Add a new partial unique index `CREATE UNIQUE INDEX idx_system_status_reports_open_unique ON system_status_reports (system_id, COALESCE(asset_id, '00000000-0000-0000-0000-000000000000'::uuid), report_date) WHERE resolved_at IS NULL`. No existing DB-level unique index on this table is dropped (grep across all `supabase/migrations/*.sql` for "UNIQUE" on `system_status_reports` returns zero hits).

**Rationale**: The current "one unresolved issue per system per date" rule is enforced ONLY in the Python backend (`backend/routers/system_status.py` — explicit `SELECT ... WHERE` check before each INSERT/UPDATE). This leaves a theoretical race between two concurrent POSTs. Since we're touching this table anyway, we're pulling the rule into the database where it belongs and extending it to cover `asset_id`.

PostgreSQL treats `NULL` as distinct in unique indexes by default — meaning a plain `UNIQUE (system_id, asset_id, report_date)` would NOT prevent two system-level rows (both `asset_id IS NULL`) from coexisting for the same (system_id, report_date) pair. Mapping `NULL` to a sentinel UUID (the all-zero UUID, which is never a valid real asset id because UUIDv4 generation never emits zero) preserves the protection for the system-level case while simultaneously enforcing "one unresolved per (system, asset, date)" for real asset ids. This is a tight, one-line guarantee.

The existing Python-level check in the router stays in place as a fast-path check — so that a friendly 409 message with the asset/system names is returned before the DB error surfaces, matching today's error UX.

**Alternatives considered**:
- *Two separate partial indexes* (one for `asset_id IS NULL`, one for `asset_id IS NOT NULL`) — rejected. More moving parts, harder to reason about; COALESCE version is a one-liner.
- *Skip DB-level constraint, keep Python-only* — rejected. We're already touching the table; adding the correct constraint is cheap and closes the race condition. YAGNI does not forbid fixing a known flaw on the path.
- *Use `CREATE UNIQUE INDEX ... NULLS NOT DISTINCT`* (Postgres 15+) — not chosen because Supabase's hosted Postgres is Postgres 15, so this IS available — but COALESCE is portable and more explicit about intent. No real benefit to the newer syntax here.

---

## Decision 9 — Validation: asset must be linked to the system

**Decision**: On `POST /system-status/report` with an `asset_id` provided, the backend verifies the `(system_id, asset_id)` pair exists in `asset_system_links` (ANY role, ANY site — production OR contingency, primary OR standby OR client all acceptable). If not linked, return 400 with a message that identifies both names.

**Rationale**: Protects against stale clients or bad requests sending an asset id that was valid for a different system. The link table is the source of truth for "which asset belongs to which system"; anything else would drift.

**Alternatives considered**:
- *Require `role = 'primary'`* — rejected. Narrower than the UI shows (drill-in sheet lists all three roles).
- *Trust the client* — rejected on basic-hygiene grounds; the server should not accept a foreign-key-like link without verifying it.

---

## Decision 10 — Reuse existing sheet widgets (parametrize with optional asset)

**Decision**: The drill-in sheet reuses four existing bottom-sheet flows from `system_status_screen.dart` by passing an optional `asset` parameter into them: report-issue, edit-issue, resolve-issue, issue-details. When `asset` is present, the sheet header shows "System Name → Asset Name" and the POST/PUT includes `asset_id`.

**Rationale**: These four sheets are already ~600 lines of polished UI. Duplicating them for an asset-specific flow would be a maintenance trap — any future bug fix or design tweak would have to land in two places. Parameterizing keeps one source of truth.

**Alternatives considered**:
- *New dedicated "AssetReportSheet" / "AssetResolveSheet" widgets* — rejected. Duplication; drift risk.
- *Extract a shared base widget both sheets inherit from* — rejected as premature abstraction per YAGNI; optional-param approach is simpler and the surface area is small.

---

## Open questions

**None.** All decisions above were confirmed with the user during the brainstorming phase.
