# Research: Natural Language Search for Work Orders

**Feature**: 023-nl-search-work-orders  
**Date**: 2026-04-06

## R1: Ollama Prompt Strategy for Filter Extraction

**Decision**: Use a single Ollama prompt that instructs the model to output a JSON object with structured filter fields. The prompt includes the list of valid statuses, types, and department names so the model maps user language to exact values.

**Rationale**: The existing ai_assist.py and ai_insights.py patterns show that Ollama responds well to explicit instructions with constrained output formats. Requesting JSON output (with `"stream": False`) allows direct parsing. Including valid enum values in the prompt reduces hallucinated filter values.

**Alternatives considered**:
- Multi-step parsing (extract intent, then map to filters) — rejected as overly complex for the constrained domain
- Regex/rule-based parsing without AI — rejected because natural language is too varied ("plumbing", "plumbing dept", "the plumbing team" all mean the same department)

**Prompt design**:
- System context: "You are a work order search filter parser"
- Input: raw user query + list of valid statuses, types, department names
- Output: JSON with fields: `status`, `type`, `department`, `location`, `date_from`, `date_to`, `min_resolution_days`
- Each field is nullable — only include filters the user actually mentioned
- Date fields resolved to ISO date strings relative to current server date
- Preamble stripping applied before JSON parse attempt

## R2: Backend Endpoint Design

**Decision**: Create a new `POST /api/search/nl` endpoint in `backend/routers/ai_search.py`. It accepts the raw query text, calls Ollama to extract filters, then queries the work_orders table with those filters. Falls back to keyword search on failure.

**Rationale**: A separate endpoint (rather than extending GET /api/work-orders) keeps the NL parsing logic isolated and avoids complicating the existing well-tested list endpoint. POST is appropriate because the request carries a body (query text + user context) and triggers server-side processing.

**Alternatives considered**:
- Extend GET /api/work-orders with a `q=` param — rejected because NL parsing is a different concern with different error modes and timeout behavior
- Two-step flow (frontend calls parse endpoint, then calls list endpoint with filters) — rejected as unnecessary round-trip; backend can do both in one request

## R3: Filter Validation and Department Matching

**Decision**: After Ollama returns extracted filters, validate each against known values. For departments, use case-insensitive partial matching against department names from the database. For status and type, exact match against known enums. Invalid filters are silently dropped.

**Rationale**: Ollama may return approximate matches (e.g., "Plumbing" when the department is "Plumbing Department"). Fuzzy matching handles this. Silently dropping invalid filters (rather than erroring) ensures users always get some results, even if the AI misinterprets part of the query.

**Alternatives considered**:
- Strict matching (reject query if any filter is invalid) — rejected as too fragile for natural language input
- Levenshtein distance matching — rejected as over-engineering; simple `contains` matching on department names is sufficient given the small number of departments

## R4: Timeout and Fallback Strategy

**Decision**: Set Ollama timeout to 5 seconds (vs 60s for existing AI features). On timeout, connection error, or JSON parse failure, fall back to keyword search using the original query text against job_no, title, and description fields. Return a `fallback: true` flag in the response.

**Rationale**: Search UX demands fast feedback. The 60-second timeout used by ai_assist.py and ai_insights.py is acceptable for those features (one-time generation), but users typing search queries expect near-instant results. 5 seconds is generous for filter extraction (a simpler task than generating descriptions or insights).

**Alternatives considered**:
- No timeout (use Ollama's default) — rejected; blocks UI too long on slow responses
- 3-second timeout — considered but 5s gives more headroom for first-request model loading

## R5: Frontend Integration Approach

**Decision**: Enhance the existing search bar in `work_order_home.dart`. On Enter/button press, call the new NL search service. Replace `FilterController` state with NL-extracted filters. Hide manual filter controls (status chips, date picker, employee filter) while NL search is active. Display extracted filters as removable chips. On clear, restore manual filter controls.

**Rationale**: Reusing the existing search bar avoids UI duplication. The FilterController already supports `clearAll()` and individual filter setters, making it natural to represent NL-extracted filters in the same state model.

**Alternatives considered**:
- New dedicated NL search screen — rejected per spec (search bar on work orders list screen)
- Separate NL search widget alongside existing search — rejected per clarification (NL replaces manual filters while active)

## R6: Existing Search Service Reuse

**Decision**: Do NOT reuse `frontend/lib/features/search/search_service.dart` (AdvancedSearchService). Create a new `ai_search_service.dart` instead.

**Rationale**: The existing search service targets non-existent backend endpoints (`/api/search/work-orders`, `/api/search/suggestions`, `/api/search/facets`), uses an over-engineered SearchFilters model with features we don't need (facets, suggestions, priority, tags, sort options), and would require both backend and frontend changes to adapt. A focused new service is simpler and follows YAGNI.

**Alternatives considered**:
- Implement the AdvancedSearchService's expected backend endpoints — rejected as scope creep; we'd be implementing two features instead of one
- Adapt AdvancedSearchService to call our new endpoint — rejected as awkward; the model shapes don't align

## R7: Activity Logging

**Decision**: Log NL search requests using the existing `log_activity()` utility with category `"search"`, action `"nl_search"`, target_label as the raw query text, and detail containing whether AI parsing succeeded or fell back to keyword.

**Rationale**: Constitution Principle VI requires auditing all user-facing actions. The fire-and-forget pattern used by existing features ensures logging doesn't impact search latency.

**Alternatives considered**:
- Skip logging for search (read-only operation) — rejected; constitution requires audit trail for all user-facing actions
- Log only failed searches — rejected; all searches should be auditable
