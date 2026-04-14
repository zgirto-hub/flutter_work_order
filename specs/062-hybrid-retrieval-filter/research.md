# Phase 0 Research — Hybrid Retrieval System Pre-filter

**Feature**: 062-hybrid-retrieval-filter
**Date**: 2026-04-14

All open questions from spec/plan were resolved during `/speckit.clarify`. This document records the rationale for each resolved decision and documents code-level findings that constrain the implementation.

---

## R1 — Registry source of truth

**Decision**: Static Python module `backend/services/system_registry.py` exporting a `KNOWN_SYSTEMS` list ordered by specificity (longest first), plus `SYSTEM_ALIASES` dict mapping each alias to its canonical name.

**Rationale**:
- Registry is small (~10–20 canonical entries, <40 total with aliases) and changes infrequently.
- Edit-deploy cycle is acceptable since registry edits are rare and coupled to the arrival of a new system manual (which already requires backend awareness).
- Avoids coupling retrieval to the existing `systems` table (spec 056), which models operational infrastructure assets and has different lifecycle concerns.
- Keeps the hot path free of extra DB lookups for the registry itself — only the per-request `manuals` lookup when a system is detected remains.
- Satisfies constitution principle VII (YAGNI): no premature abstraction.

**Alternatives considered**:
- Reading from the existing `systems` table — rejected: overloads a table with operational semantics to carry retrieval keywords; `systems.name` values may not match technician vocabulary (aliases like "CADAS ATS" vs "CADAS-ATS").
- New dedicated `system_keywords(canonical, alias, active)` table — rejected: adds migration, CRUD surface, and admin UI for a ~20-row static list.

**Upgrade path**: If/when the registry grows past ~50 entries or ops need non-developer edits, a single migration introduces the table and `system_registry.py` becomes a thin DB-backed loader with module-level cache. No caller changes.

---

## R2 — Detection algorithm

**Decision**: Case-insensitive substring scan over the question text for every entry in `KNOWN_SYSTEMS + SYSTEM_ALIASES.keys()`, ordered by string length descending. First match wins. No regex word boundaries (aliases include spacing/hyphenation variants, so specificity ordering is what prevents "CADAS" from eating "CADAS-ATS").

**Rationale**:
- FR-002: longest-match-wins is explicitly required; sort-by-length + first-match-wins is the simplest correct implementation.
- FR-010 / SC-005: pure Python `str.find` (or `in`) is <1 ms per question at corpus scale. No regex engine startup, no LLM call.
- Unambiguous bare tokens (e.g. "CADAS" without a suffix) are intentionally absent from the registry so they return `None` and fall through to unfiltered search (consistent with clarification on ambiguous shorthand).

**Alternatives considered**:
- Regex with `\b` word boundaries — rejected: hyphens and spaces are not word characters in regex default `\b`, leading to brittle behavior for "CADAS-ATS" vs "CADAS ATS". Specificity ordering handles it cleanly.
- LLM-based intent classification — rejected: violates SC-005 (<5 ms p95); overkill for a string match.

---

## R3 — Manual↔system association rule

**Decision**: Case-insensitive substring match against **both** `manuals.title` AND `manuals.file_name`, for the canonical name and every alias of the detected system. Implemented as a single Supabase query with `or()` across title/file_name × all variants.

**Rationale**:
- FR-003 clarification: spec allows both title-based and filename-based matching to catch generically-titled manuals whose system is encoded in the filename (e.g. `cadas_ats_v2.pdf` with title "Operations Manual").
- `manuals.file_name` column confirmed present in existing schema (see `supabase/migrations/20260411000000_create_manuals.sql`).
- One query, already indexed-friendly on small table (~50 rows typical).
- Accepts known blind spot: manuals that encode the system in neither field fall through to unfiltered search (documented in spec Assumptions).

**Alternatives considered**:
- Add `manuals.system_tag` column — rejected: requires migration, admin UI, and a manual tagging step at upload time. Over-engineered for the current corpus.
- Title-only match — rejected during clarification: real-world manuals have inconsistent naming.

---

## R4 — Integration point in `manual_rag_service.py`

**Decision**: Wire detection into `ask()` early (after the validated-QA early-exit check, before embedding). Produce a `retrieval_info` dict that flows through both branches:
1. **Validated-QA fast path** ([line 663](backend/services/manual_rag_service.py#L663)): include `retrieval_info` with `detected_system` populated (if any) and `filter_applied=false`.
2. **User-selected-manual single-RPC path** ([line 749](backend/services/manual_rag_service.py#L749)): same — `detected_system` populated for observability, `filter_applied=false`.
3. **Cross-manual synthesis path** ([_retrieve_chunks_per_manual](backend/services/manual_rag_service.py#L430)): narrow the `manuals_resp.data` list by intersecting with matched manual IDs; set `filter_applied=true` when matched list is non-empty, else log warning, use full list, set `fallback_reason="no_manuals_for_system"`.

**Rationale**:
- Q5 clarification: detection always runs; `filter_applied` distinguishes "narrowed" from "would have narrowed but couldn't/needn't".
- Q2 clarification: reuses existing per-manual path from spec 046 — no duplicate retrieval code.
- Q4 clarification: fallback_reason + generator prompt directive are separate concerns and wired at their respective layers (response dict for UI; prompt prefix for LLM).

**Code findings (confirmed by grep)**:
- `search_manual_chunks` RPC in [supabase/migrations/20260411000000_create_manuals.sql:76](supabase/migrations/20260411000000_create_manuals.sql#L76) signature: `(q_embedding vector(768), manual_id_filter uuid DEFAULT NULL, match_count int DEFAULT 5)` — **single uuid**, consistent with plan.
- `_retrieve_chunks_per_manual` at [line 430](backend/services/manual_rag_service.py#L430) already does `supabase.table("manuals").select("id, title").execute()` then iterates per manual — the **sole change** here is to accept an optional `allowed_manual_ids: set[str] | None` parameter and filter that loop's iteration.
- `ask()` entry point at [line 632](backend/services/manual_rag_service.py#L632); `manual_id_filter` parameter is optional UUID.

---

## R5 — Generator prompt directive for missing-manual fallback

**Decision**: When `fallback_reason="no_manuals_for_system"`, prepend a fixed directive line to the existing generator prompt, ahead of the retrieved context block:

```text
IMPORTANT: The user asked specifically about {detected_system}. No manuals for {detected_system} are currently uploaded to the system. Do NOT substitute content from other similar-sounding systems. Respond that specific information about {detected_system} is not available in the uploaded manuals.
```

**Rationale**:
- FR-006 and SC-004 require the LLM to state info is unavailable rather than substituting. System instructions from spec 040 already lean in this direction, but a targeted per-request directive is more reliable than hoping the generic prompt catches it.
- Prepending is non-destructive — existing prompt structure (context + history + question) is unchanged, satisfying the constraint "no changes to the RAG prompt structure" as read strictly (we extend with a prefix, not restructure).
- Template is short (<400 chars) so token budget impact is negligible.

**Alternatives considered**:
- Replace the answer entirely from backend without calling the LLM — rejected: inconsistent with the rest of the pipeline, and the LLM still needs to handle any conversational context that came with the question.
- Rely solely on existing system instructions — rejected: clarification Q4 explicitly chose dual-signal; observed past incident (CADAS-IMS substitution) happened despite existing instructions.

---

## R6 — Flutter model extension

**Decision**: Add a nullable `RetrievalInfo` field to `ManualQaAnswer`. Parse defensively: `retrieval_info` key may be absent (pre-deploy backends), in which case the field stays null and the chip is not rendered (FR-011 backward-compat).

**Fields**:
- `detectedSystem: String?`
- `filteredManualIds: List<String>` (default `[]`)
- `filterApplied: bool` (default `false`)
- `fallbackReason: String?`

**Rationale**: Matches the contract in `contracts/retrieval_info.schema.md`. Defensive null/default parsing is consistent with existing code style for optional RAG metadata fields.

---

## R7 — Test strategy

**Decision**:
1. **Unit tests** (`backend/tests/test_system_registry.py`): cover the four acceptance cases from spec Task-1 acceptance criteria + case-insensitivity + ambiguity-no-match + longest-match-wins.
2. **Integration-style manual test** — the 5 benchmark questions from spec Testing section, run against a dev environment with CADAS-ATS + CADAS-IMS manuals loaded. Captured in `quickstart.md`.
3. **Widget test** for the answer-card chip: pass a fake `ManualQaAnswer` with `filterApplied=true/false` and assert chip visibility.

**Rationale**: The registry is the only pure-logic component worth automating; the retrieval integration depends on Supabase + Ollama + uploaded manuals, which is impractical to fully automate. Manual benchmark is the authoritative acceptance signal tied to SC-001/SC-002/SC-004.

---

## Open items

None. All clarifications from the `/speckit.clarify` session are mapped to concrete decisions above.
