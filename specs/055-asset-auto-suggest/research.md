# Research: Auto-Suggest Asset Registry Additions (055)

**Date**: 2026-04-14 | **Branch**: `055-asset-auto-suggest`

## R1: Suggestions Query Strategy

**Decision**: Server-side aggregation using two queries: (1) fetch all distinct `equipment_id` values from `pattern_alerts` with counts, (2) fetch all asset names + dismissed list, then compute the diff in Python.

**Rationale**: The suggestion computation requires a cross-table comparison (alerts vs assets vs dismissed). PostgREST doesn't support `NOT IN` subqueries or `LEFT JOIN ... WHERE NULL` elegantly. Two simple queries with Python-side filtering is clear, performant for the expected scale (~50 alerts, ~200 assets), and follows the project's established pattern of doing joins in Python (see N+1 fix in spec 053).

**Alternatives considered**:
- **Single SQL RPC**: Create a Supabase function that does the aggregation. Rejected — adds a migration for a query that's simple enough in Python.
- **Client-side computation**: Frontend fetches alerts + assets and computes diff. Rejected — leaks alert data to frontend unnecessarily and violates Constitution V (this requires cross-table query, not client-side filtering of a single dataset).

## R2: Metadata Inference Approach

**Decision**: Query `work_order_entities` for the suggested equipment_id, aggregate `equipment_type` by frequency, and return the most common non-null value as the inferred type.

**Rationale**: The extraction pipeline already stores `equipment_type` per work order. The most common type across multiple extractions for the same equipment is the best guess. If all extractions have different types or null, return null and let the Admin choose.

**Alternatives considered**:
- **AI inference**: Ask Gemma to classify the equipment name. Rejected — YAGNI, adds latency, and the extraction data already has this.
- **No inference**: Always leave type blank. Rejected — reduces the value proposition of pre-filling the form.

## R3: Dismissed Suggestions Storage

**Decision**: Store dismissed equipment_ids as a JSON array in the existing `system_settings` table (key: `dismissed_asset_suggestions`).

**Rationale**: Per clarification. The `system_settings` table already exists (spec 052) and supports key-value JSON pairs. A simple array of strings is sufficient — no audit trail needed, no per-user dismiss tracking. The list is bounded by the number of distinct equipment_ids in alerts.

**Alternatives considered**:
- **New table**: `dismissed_asset_suggestions(id, equipment_id, dismissed_by, dismissed_at)`. Rejected — overkill for a string blocklist.
- **Flag on pattern_alerts**: Add `suggestion_dismissed` column. Rejected — conflates alert data with suggestion UI state.

## R4: Case-Insensitive Matching

**Decision**: Convert both asset names and alert equipment_ids to lowercase for comparison in Python.

**Rationale**: The spec requires case-insensitive matching (FR-001). Doing this in Python after fetching both lists is simple and avoids needing a database function or collation change. The comparison is: `equipment_id.lower() not in {name.lower() for name in asset_names}`.
