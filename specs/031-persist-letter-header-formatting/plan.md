# Implementation Plan: Persist Letter Header Field Formatting

**Branch**: `031-persist-letter-header-formatting` | **Date**: 2026-04-07 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/031-persist-letter-header-formatting/spec.md`

## Summary

Bug fix: the letter generator (v2) accepts whole-field formatting (font size, bold, underline) for the Reference Number, Date, Recipient, and Subject header fields in the editor and forwards it to the backend at save time, but the backend never stores those attributes. On reload, only the plain text is restored — formatting silently reverts to defaults.

The fix is end-to-end persistence of the existing whole-field attributes that the UI already produces:

1. Add formatting columns to `generated_letters` (Supabase migration).
2. Backend (`letters_v2.py`) writes them on insert/update and includes them in the read response; the regenerate path reads the saved values instead of hardcoded defaults.
3. Frontend `GeneratedLetter` model gains the formatting fields and (de)serializes them.
4. `LetterFormTabV2.initState` restores the formatting state variables when an existing letter is loaded.
5. The Date row in the form gains the same font-size / bold / underline controls already present on the other three rows (it currently has none — this is the only UI addition).

Rich-text per-character formatting is **out of scope** for this feature and explicitly deferred (see Clarifications session 2026-04-07).

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x (frontend), Python 3 (backend)
**Primary Dependencies**: FastAPI, Supabase Python client, Jinja2 (backend); supabase_flutter, http, Flutter Material (frontend) — all already in the project, no new dependencies
**Storage**: Supabase (PostgreSQL) — `generated_letters` table
**Testing**: Manual end-to-end via the letter editor (create → save → reopen → verify); no automated test harness exists for the letters_v2 screen today
**Target Platform**: Flutter Web (PWA) + FastAPI on Linux
**Project Type**: Web application (frontend + backend)
**Performance Goals**: No change — payload grows by ~8 small scalars per letter, negligible
**Constraints**: Must remain backwards-compatible with legacy `generated_letters` rows (no formatting columns) — they load with default styling, no errors
**Scale/Scope**: Single screen, single table, ~6 file edits + 1 migration

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| I. Full-Stack Ownership | Touches backend router, migration, frontend model, frontend service consumer (form tab), no new screen needed | ✅ |
| II. Explicit Over Automatic | All formatting attributes are explicitly stored and explicitly read; no inference, no silent defaults except for legacy rows where we document a fallback | ✅ |
| III. Role-Based Access Control | No permission changes — uses existing letter endpoints; no new endpoints introduced | ✅ |
| IV. Server-First File Storage | No file storage involved | N/A |
| V. Client-Side Computation | No new computation; serialization only | N/A |
| VI. Audit Everything | Letter create/update already audited via existing flows; no new user-facing action introduced | ✅ |
| VII. Simplicity & YAGNI | Whole-field scalars only (no JSONB, no rich text, no editor rewrite); rich-text option explicitly deferred per clarification | ✅ |

**Result**: PASS — no violations, no Complexity Tracking entries needed.

## Project Structure

### Documentation (this feature)

```text
specs/031-persist-letter-header-formatting/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 — investigation findings (no NEEDS CLARIFICATION)
├── data-model.md        # Phase 1 — column additions and model field list
├── quickstart.md        # Phase 1 — manual verification steps
├── contracts/
│   └── letters_v2_api.md  # Phase 1 — request/response schema deltas
└── checklists/
    └── requirements.md  # From /speckit.specify
```

### Source Code (repository — files to be touched)

```text
backend/
├── routers/
│   └── letters_v2.py                       # Persist + return formatting; regenerate from DB values
└── templates/
    └── letter_template.html                # No change — already renders the formatting it receives

supabase/
└── migrations/
    └── 20260407_letter_header_formatting.sql   # NEW — add columns

frontend/
└── lib/
    ├── models/
    │   └── generated_letter.dart           # Add 8 formatting fields + (de)serialize
    └── screens/
        └── letters_v2/
            └── letter_form_tab_v2.dart     # Restore formatting on load; add Date row controls
```

**Structure Decision**: Web application layout (Option 2) — backend (FastAPI) + frontend (Flutter) — matches the project's existing convention. No new directories.

## Phase 0 — Outline & Research

No `NEEDS CLARIFICATION` items. The Explore agent already mapped the relevant code paths; findings are recorded in [research.md](research.md). Key resolved decisions:

- **Storage shape**: 8 plain columns on `generated_letters` (one per attribute × four fields). JSONB rejected — adds query/migration complexity for no benefit at whole-field granularity.
- **Default values**: Match the current hardcoded defaults already used in `LetterFormTabV2` and `LetterBodyV2` so legacy rows render identically to today.
- **Backwards compatibility**: New columns are nullable with defaults; `fromJson` falls back to defaults when keys are missing; no migration of existing rows is required.
- **PDF rendering**: No template change. The Jinja template already consumes these attributes from the request body; the only fix is ensuring the regenerate path passes saved values instead of hardcoded ones.

## Phase 1 — Design & Contracts

Artifacts:
- [data-model.md](data-model.md) — column list, types, defaults, and Dart/Pydantic field mapping.
- [contracts/letters_v2_api.md](contracts/letters_v2_api.md) — request/response schema deltas for `POST /letters-v2/generate`, `PUT /letters-v2/{id}`, `GET /letters-v2`, and `POST /letters-v2/{id}/regenerate`.
- [quickstart.md](quickstart.md) — manual verification script covering all four acceptance scenarios from the spec.

**Agent context update**: Skipped — no new technologies, dependencies, or storage paradigms introduced. `CLAUDE.md`'s Active Technologies list does not need a new entry.

**Post-design Constitution re-check**: PASS — design adds only nullable columns and field-level scalars; no architectural changes.

## Complexity Tracking

No violations. Table intentionally empty.
