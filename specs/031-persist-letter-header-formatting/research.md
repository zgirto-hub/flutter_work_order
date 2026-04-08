# Phase 0 Research — Persist Letter Header Field Formatting

**Date**: 2026-04-07
**Status**: Complete — no `NEEDS CLARIFICATION` items remain.

## Investigation summary

The bug is a missing-persistence defect, not a missing-feature defect. The frontend already produces the formatting attributes, the backend already accepts them in the request body, and the Jinja PDF template already renders them. The single break in the chain is that the backend never writes them to the database, so on reload there is nothing to restore.

## Decisions

### D1 — Storage shape: plain columns, not JSONB

**Decision**: Add eight nullable columns to `generated_letters`, one per attribute × four header fields:

- `ref_font_size numeric`, `ref_bold boolean`, `ref_underline boolean`
- `tarikh_font_size numeric`, `tarikh_bold boolean`, `tarikh_underline boolean`
- `recipient_font_size numeric`, `recipient_bold boolean`, `recipient_underline boolean`
- `subject_font_size numeric`, `subject_bold boolean`, `subject_underline boolean`

(Note: the spec lists 8 attributes in the conversational summary; the actual count is 12 — three attributes × four fields. The template has only ever used `subject_underline` so far, but for symmetry and to match the deferred rich-text design we add `*_underline` for all four fields. This is a one-line cost in the migration and avoids a follow-up ALTER.)

**Rationale**: Whole-field granularity means the data is genuinely flat. JSONB would require Postgres operators to query, complicate the Pydantic schema, and offer no benefit. Plain columns are searchable, indexable, and trivial for both Supabase REST and direct SQL.

**Alternatives considered**:
- JSONB column `header_format` — rejected: adds parsing both sides for zero queryability gain at this granularity.
- Reuse existing `body_text` style storage — rejected: body has no formatting persistence today either, and conflating the two slows down a future body-formatting feature.

### D2 — Default values match existing hardcoded UI defaults

**Decision**: Column defaults in the migration mirror the current hardcoded values in [letter_form_tab_v2.dart:34-58](frontend/lib/screens/letters_v2/letter_form_tab_v2.dart#L34-L58) and [letters_v2.py:87-93](backend/routers/letters_v2.py#L87-L93):

| Field | font_size | bold | underline |
|---|---|---|---|
| Reference Number | 11 | false | false |
| Date (tarikh) | 11 | false | false |
| Recipient | 12 | false | false |
| Subject | 13 | true | true |

**Rationale**: Legacy rows (saved before this migration) get NULL on the new columns; the frontend `fromJson` and the backend GET response coalesce NULL to these defaults. Result: a legacy letter loaded today looks identical to a legacy letter loaded after the fix — no visual regression, no data backfill required (Spec FR-005, SC-003).

**Alternatives considered**:
- Backfill existing rows with defaults at migration time — rejected: unnecessary write amplification; coalescing on read achieves the same outcome.
- Make columns NOT NULL with defaults — rejected: makes it impossible to distinguish "user explicitly chose default" from "legacy row"; harmless for now but loses optionality cheaply.

### D3 — Date field gains formatting controls in the form

**Decision**: Add a font-size / bold / underline control row to the Date field in `LetterFormTabV2`, matching the existing pattern used by Reference Number, Recipient, and Subject. Three new state variables: `_dateFontSize`, `_dateBold`, `_dateUnderline`.

**Rationale**: The user explicitly requested the date field be included in this fix. Today the date row has no formatting controls at all, so persistence alone is insufficient — there is nothing for the user to set. The control row is a copy-paste of the existing pattern.

**Alternatives considered**:
- Persist date formatting columns but skip the UI — rejected: stores attributes the user can never change; violates Constitution Principle II (Explicit Over Automatic).

### D4 — PDF template untouched

**Decision**: No edit to [letter_template.html](backend/templates/letter_template.html). The template already styles each header line from the request body variables. The only PDF-side fix is in the regenerate endpoint, which currently builds a `LetterBodyV2` with hardcoded defaults instead of reading the stored values. Once the read path returns saved formatting, regenerate will pass them through unchanged.

**Rationale**: Smallest possible blast radius; preserves current PDF layout exactly (zero risk of layout regression — see the discussion of Arabic shaping deferred to the future rich-text feature).

### D5 — No new endpoints, no new screens

**Decision**: All changes happen on existing endpoints (`POST /letters-v2/generate`, `PUT /letters-v2/{id}`, `GET /letters-v2`, `POST /letters-v2/{id}/regenerate`) and existing files. No router additions, no navigation wiring.

**Rationale**: Constitution Principle VII (Simplicity & YAGNI). The bug is purely in the persistence layer of an existing flow.

## Open questions

None. Ready for Phase 1.
