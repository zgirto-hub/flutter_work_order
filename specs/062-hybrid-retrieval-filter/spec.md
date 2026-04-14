# Feature Specification: Hybrid Retrieval — System Keyword Pre-filtering

**Feature Branch**: `062-hybrid-retrieval-filter`
**Created**: 2026-04-14
**Status**: Draft
**Input**: User description: "Hybrid Retrieval — System Keyword Pre-filtering: detect system names (CADAS-ATS, AIDA-NG, etc.) in user questions and narrow manual chunk search to matching manuals before cosine vector search"

## Clarifications

### Session 2026-04-14

- Q: Where should the known-system registry live? → A: Static Python constant module (edit = code change + deploy). DB-backed registry deferred as a future upgrade path.
- Q: Multi-manual retrieval path when a system matches N manuals? → A: Reuse the existing per-manual retrieval + rerank path (spec 046); narrow its manuals-list input to the matched subset. Single code path for both single- and multi-manual matches.
- Q: How do we associate a detected system name with manuals? → A: Case-insensitive substring match against BOTH `manuals.title` AND `manuals.file_name`, for the canonical name and every alias. Catches generically-titled manuals whose filename encodes the system (e.g. `cadas_ats_v2.pdf`). No schema changes.
- Q: How is "system detected but no manuals exist" signaled? → A: Dual signal — (1) add `retrieval_info.fallback_reason = "no_manuals_for_system"` on the response, and (2) prepend an explicit hint to the generator prompt instructing it to state information is unavailable and not substitute content from other systems. Enforces honesty at both UI and LLM layers.
- Q: Does detection run for validated-QA and user-selected-manual paths too? → A: Yes, always detect. `retrieval_info.detected_system` populated whenever a system keyword is present; `retrieval_info.filter_applied` (boolean) is true only when detection actually narrowed retrieval. Validated-QA hits and explicit-selection get `detected_system` for observability but `filter_applied=false`. UI chip is shown only when `filter_applied=true`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Accurate answers for system-specific questions (Priority: P1)

A technician asks the AI assistant about a specific named system (e.g. "what is the backup for CADAS-ATS?"). The assistant detects the system name in the question and narrows its search to manuals that are actually about that system, so the answer quotes the correct procedure instead of a near-neighbor system's procedure.

**Why this priority**: This is the root reason the feature exists. Today, cosine similarity across all chunks returns results from the wrong system (e.g. CADAS-IMS instead of CADAS-ATS) because the domain vocabulary is shared. Users have observed this and lost trust in the assistant. Fixing the retrieval layer is the only way to guarantee correctness — downstream prompt instructions are a safety net, not a fix.

**Independent Test**: Ask "what is the backup for CADAS-ATS?" with both CADAS-ATS and CADAS-IMS manuals uploaded. Verify the cited chunks all come from CADAS-ATS-titled manuals and the answer references CADAS-ATS procedures only.

**Acceptance Scenarios**:

1. **Given** manuals for CADAS-ATS and CADAS-IMS are both uploaded, **When** a user asks "what is the backup for CADAS-ATS?", **Then** only chunks from CADAS-ATS-titled manuals are retrieved and the answer is about CADAS-ATS.
2. **Given** manuals for CADAS-ATS and CADAS-IMS are both uploaded, **When** a user asks "what is the backup for CADAS-IMS?", **Then** only chunks from CADAS-IMS-titled manuals are retrieved.
3. **Given** an AIDA-NG manual is uploaded, **When** a user asks "how to restart aida-ng?" (lowercase), **Then** the system is detected case-insensitively and AIDA-NG chunks are retrieved.

---

### User Story 2 - Unchanged experience for general questions (Priority: P1)

A user asks a general question that does not reference any known system (e.g. "what are the general maintenance rules?" or "backup procedure"). The assistant behaves exactly as it does today: cosine search runs across all manual chunks with no pre-filter.

**Why this priority**: No regression is acceptable. Most questions do not mention a system by name, and forcing a filter would break them.

**Independent Test**: Ask a general question containing no system name. Verify retrieved chunks span multiple manuals and behavior matches current production.

**Acceptance Scenarios**:

1. **Given** a question contains no recognized system name, **When** it is submitted, **Then** chunk retrieval searches all manuals (no filter applied) and the response indicates no system was detected.
2. **Given** a question mentions an ambiguous shorthand (e.g. bare "CADAS") that does not match any canonical entry, **When** no specific match is found, **Then** no filter is applied and all manuals are searched.

---

### User Story 3 - Graceful fallback when a system is named but no manual exists (Priority: P2)

A user asks about a system whose name is in the registry but has no uploaded manual yet. The assistant logs the situation, falls back to searching all manuals, and the answer honestly reports that no information is available for that system rather than silently returning results from a similar-sounding system.

**Why this priority**: This scenario is rare but important: silently returning wrong-system content is the exact failure mode this feature exists to prevent, so the fallback must not reintroduce it.

**Independent Test**: Do not upload the CADAS-ATS manual. Ask "what is the backup for CADAS-ATS?". Verify (a) the system is detected, (b) fallback retrieval runs, (c) the answer states CADAS-ATS information is not available rather than returning CADAS-IMS content.

**Acceptance Scenarios**:

1. **Given** CADAS-ATS is a known system name but no manual with that name is uploaded, **When** the user asks about CADAS-ATS, **Then** the system is detected, a warning is logged, retrieval falls back to all manuals, and the response indicates CADAS-ATS-specific information is unavailable.

---

### User Story 4 - User-selected manual takes precedence (Priority: P2)

When a user has already selected a specific manual from the dropdown in the Flutter UI, that choice overrides system detection. Keyword-based narrowing runs only when no manual is explicitly selected.

**Why this priority**: Explicit user intent should always win over inferred intent.

**Independent Test**: Select "CADAS-IMS manual" in the dropdown and ask "what is the backup for CADAS-ATS?". Verify chunks come from the selected CADAS-IMS manual, not from CADAS-ATS.

**Acceptance Scenarios**:

1. **Given** the user has selected a manual in the UI, **When** the question also contains a different system name, **Then** the user's selection is used and system detection is skipped.

---

### User Story 5 - Visible filter indication in the answer card (Priority: P3)

When the assistant narrowed the search to a specific system, the Flutter answer card shows a small "Filtered to: <system>" chip so the user can see why the answer is scoped the way it is. When no filter was applied, no chip is shown.

**Why this priority**: Transparency helps users trust and debug answers, but the feature provides full value even without the UI element.

**Independent Test**: Ask a system-named question and a general question in sequence. Verify the chip appears for the first and is absent for the second.

**Acceptance Scenarios**:

1. **Given** a system was detected and used for filtering, **When** the answer renders, **Then** a "Filtered to: <system-name>" chip appears under the "Synthesized from N manuals" banner.
2. **Given** no system was detected, **When** the answer renders, **Then** no filter chip is shown and the existing layout is unchanged.

---

### Edge Cases

- **Multiple systems named in one question** (e.g. "compare CADAS-ATS and CADAS-IMS"): first match in the ordered registry wins, ambiguity is logged. Multi-system comparison answers are out of scope and tracked as a follow-up.
- **Partial/ambiguous name** (e.g. bare "CADAS"): no canonical match, no filter applied.
- **System has multiple manuals** (e.g. "CADAS-ATS v1" and "CADAS-ATS v2"): both must be searched — no matching manual may be silently dropped.
- **Registry entry exists but zero manuals match**: detect, log warning, fall back to unfiltered search; never return empty results silently.
- **Mixed-case and hyphenation variants**: "cadas-ats", "CADAS ATS", "Cadas-ATS" all resolve to the same canonical name.
- **Response contract compatibility**: clients that ignore the new retrieval metadata must continue to work unchanged.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST detect when a user question references a known system by name, using case-insensitive matching against a maintainable registry of canonical names and common aliases.
- **FR-002**: System MUST resolve overlapping names by matching the most specific (longest) entry first, so that "CADAS-ATS" is preferred over "CADAS" and "CADAS-IMS" is never confused with "CADAS-ATS".
- **FR-003**: When a system is detected, System MUST restrict chunk retrieval to manuals where the canonical name or any registered alias appears (case-insensitive substring match) in EITHER the manual's title OR its file name. This covers manuals whose title is generic but whose filename encodes the system.
- **FR-004**: When one or more manuals match the detected system, System MUST retrieve and rank chunks using the existing cross-manual retrieval path (per-manual chunk fetch + merge + rerank from spec 046), with its manuals-list input narrowed to the matched subset. No matching manual may be silently dropped. The chunk-search RPC signature remains unchanged.
- **FR-005**: When no system is detected, System MUST perform chunk retrieval across all manuals, preserving the current behavior and ranking.
- **FR-006**: When a system is detected but no manuals match, System MUST (a) log a warning, (b) fall back to unfiltered retrieval, (c) set `retrieval_info.fallback_reason = "no_manuals_for_system"` on the response, and (d) prepend a directive to the generator prompt instructing it to state that information for the detected system is unavailable and not to substitute content from other systems. The generated answer MUST reflect that directive.
- **FR-007**: When the user has explicitly selected a manual in the UI, System MUST use that selection for retrieval and MUST NOT apply system-keyword narrowing. Detection itself MAY still run for observability (see FR-008) but `filter_applied` MUST be false on the response.
- **FR-008**: System MUST include retrieval metadata in the response on every path (cross-manual synthesis, user-selected-manual, validated-QA fast path): `detected_system` (canonical name or null), `filtered_manual_ids` (list, empty when no narrowing), `filter_applied` (boolean — true only when the set of searched manuals was actually narrowed by system detection), and optional `fallback_reason` (e.g. `"no_manuals_for_system"`).
- **FR-009**: The response contract MUST remain backward compatible; clients that do not read `retrieval_info` MUST continue to function without modification.
- **FR-010**: System detection MUST add negligible latency to question handling (pure string matching, no model or network call in the hot path).
- **FR-011**: The Flutter answer card MUST display a "Filtered to: <system>" indicator when the response reports `filter_applied=true`, and MUST render unchanged otherwise (no system detected, detection ran but filter not applied, or `retrieval_info` absent).
- **FR-012**: The known-system registry MUST live in a dedicated code module (static Python constant with canonical names and aliases), isolated from the retrieval pipeline module so that additions/edits do not require changes to retrieval logic. A future migration to a database-backed registry is an accepted non-goal for v1.
- **FR-013**: System MUST NOT modify the existing chunk-search database function's signature, the embedding pipeline, or the generation prompt structure — only the set of chunks passed into the existing pipeline changes.

### Key Entities *(include if feature involves data)*

- **Known System**: A canonical name for a named operational system (e.g. "CADAS-ATS", "AIDA-NG") plus a set of case-insensitive aliases and shorthand forms used by technicians. Used for keyword detection only; this feature does not introduce a new persistent table.
- **Manual**: An existing uploaded document with a title. A manual's title is the association point between a detected system name and the chunks eligible for retrieval.
- **Retrieval Info**: A response-level record produced per question containing: the detected system name (or none), the list of manual identifiers used to scope retrieval, and — when applicable — a `fallback_reason` code (e.g. `"no_manuals_for_system"`) indicating why no filter was applied despite detection. Displayed in the UI and used for debugging/observability.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With both CADAS-ATS and CADAS-IMS manuals present, 100% of CADAS-ATS-named questions return chunks sourced exclusively from CADAS-ATS-titled manuals, and vice versa for CADAS-IMS.
- **SC-002**: Cross-system contamination (answer cites wrong-system content for a clearly system-named question) drops to zero on the documented test set of five benchmark questions.
- **SC-003**: Zero regressions on general (non-system-named) questions: retrieval set composition and ranking for those questions is identical to pre-feature behavior.
- **SC-004**: When a system is detected but no manual exists for it, the answer explicitly states that information is unavailable in 100% of cases — never silently substitutes near-neighbor content.
- **SC-005**: Added latency from system detection stays under 5 milliseconds per question at the 95th percentile.
- **SC-006**: The filter indicator chip is visible to users for every question where a system was detected and filtering was applied.

## Assumptions

- The existing `manuals` table exposes both `title` and `file_name` columns; matching against both is sufficient coverage for this corpus, without introducing a manual↔system relationship table. Manuals that encode the system in neither field are a known blind spot and will fall through to unfiltered retrieval.
- The initial set of named systems is small (~10–20 entries) and changes infrequently; a static module-level list is acceptable for v1, with an upgrade path to a DB-backed registry later.
- Each named system has fewer than ~10 matching manuals, so retrieving across all matching manuals and re-ranking remains performant without changing the existing chunk-search function's signature.
- Multi-system comparison questions ("compare A and B") are out of scope and will be addressed in a follow-up feature.
- Existing RAG pipeline stages (HyDE, reranking, session summary, tool use, generation) remain untouched; only the input chunk set to the pipeline changes.
- The existing Flutter answer model can be extended in a non-breaking way to carry the new retrieval metadata field.
