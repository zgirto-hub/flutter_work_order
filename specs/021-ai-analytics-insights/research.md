# Research: AI-Powered Analytics & Insights

**Feature**: 021-ai-analytics-insights  
**Date**: 2026-04-05

## R1: Ollama Prompt Design for Structured Data Analysis

**Decision**: Use the existing Ollama + Gemma4:e2b model with role-prefixed prompts that feed pre-aggregated statistics (never raw rows) and request 3-5 bullet points.

**Rationale**: The existing `ai_assist.py` pattern (lines 51-58) works well for single-prompt generation. For insights, the prompt must include a role prefix ("You are an operations analyst for civil aviation..."), a compact data table of aggregated stats, and an explicit output format instruction ("Provide 3-5 bullet points. No preamble."). Feeding raw rows would exceed the model's context window and produce inconsistent results. Aggregating to counts, averages, and top-N lists keeps prompts under 500 tokens.

**Alternatives considered**:
- Raw row dumps to LLM — rejected: context window limits, inconsistent output
- Multiple chained LLM calls per insight — rejected: doubles latency, unnecessary for summary-level analysis
- Streaming responses — rejected: adds complexity, bullet-point output is short enough for single response

## R2: Arabic Language Support in Prompts

**Decision**: Add a `language` parameter to the request. When Arabic is selected, append "Respond entirely in Arabic." to the prompt. The same aggregated data (in English field names) is fed to the model, but the output language is directed.

**Rationale**: Gemma4 models support Arabic text generation. The prompt instruction approach is simpler than maintaining separate Arabic prompt templates. Field names and numbers remain in English within the prompt (the model translates entity names in its output). The frontend handles RTL rendering using the existing `_detectDirection()` pattern from `form_fields.dart` (lines 50-64).

**Alternatives considered**:
- Dual prompt templates (English + Arabic) — rejected: maintenance burden, same data either way
- Post-translation of English output — rejected: adds latency, loses natural phrasing
- Auto-detect from user locale — rejected: user preference is more reliable; toggle gives explicit control

## R3: Data Aggregation Strategy

**Decision**: Three dedicated aggregation functions in the backend that query Supabase with date-range filters and return compact dicts. No new database views or stored procedures needed.

**Rationale**: The existing `system_status.py` uptime report (lines 280-357) already demonstrates the pattern: query with date filters, iterate results, compute aggregates in Python. Work order aggregation follows the same approach using `.select("status, type, department_id, created_at, closed_at")` with `.gte("created_at", cutoff)`. Department names are resolved via a separate `.select("id, name")` call to the `departments` table. All aggregation is O(N) over the filtered result set — acceptable for the expected data volumes (hundreds to low thousands of work orders per 30-day window).

**Alternatives considered**:
- Supabase RPC / stored procedures — rejected: adds migration complexity, harder to maintain
- Client-side aggregation — rejected: violates server-first principle, wasteful data transfer
- Caching aggregated results — rejected: premature for V1, adds staleness concerns

## R4: Backend Endpoint Design

**Decision**: Single new router file `backend/routers/ai_insights.py` with one endpoint: `POST /api/ai/insights`. The `insight_type` parameter determines which aggregation and prompt to use.

**Rationale**: One endpoint with a type discriminator is simpler than three separate endpoints. Follows the pattern of `ai_assist.py` (single endpoint, focused responsibility). A new router file keeps concerns separated from the description-generation feature. Role validation uses the existing `email` + `user_role` query parameter pattern from `work_orders.py`.

**Alternatives considered**:
- Three separate endpoints (`/ai/insights/overview`, etc.) — rejected: unnecessary API surface area
- Adding to existing `ai_assist.py` — rejected: different domain (generation vs. analysis), violates single responsibility

## R5: Frontend Integration Point

**Decision**: New `AiInsightsCard` widget added to `dashboard_screen.dart` between the stats row and Quick Actions section. Loads asynchronously after main dashboard data. Only visible to admin/supervisor roles.

**Rationale**: The dashboard is the primary landing page for admins (confirmed in constitution). Placing insights there maximizes visibility without adding navigation overhead. Async loading prevents blocking the dashboard paint (SC-003). Role gating follows the existing pattern at line 436 of `dashboard_screen.dart`.

**Alternatives considered**:
- Dedicated insights screen — rejected for V1: adds navigation, reduces discoverability
- More screen grid item — rejected: insights are high-value, should be front-and-center
- Bottom sheet overlay — rejected: insights need persistent visibility, not transient display

## R6: Preamble Stripping for Arabic

**Decision**: Extend the existing `_strip_preamble()` logic with Arabic preamble phrases in addition to the English ones. Import and reuse the function from `ai_assist.py` or duplicate with extensions.

**Rationale**: The Gemma4 model sometimes generates conversational preambles in Arabic (e.g., "بالتأكيد", "إليك"). The same stripping approach works: check if leading lines start with known Arabic preamble words. Duplicating the function (rather than importing) avoids coupling between two router files and allows Arabic-specific additions.

**Alternatives considered**:
- Shared utility module for preamble stripping — rejected: YAGNI, only two consumers
- No Arabic preamble stripping — rejected: would produce inconsistent output quality
