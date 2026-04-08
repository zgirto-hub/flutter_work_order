# Tasks: Persist Letter Header Field Formatting

**Feature**: 031-persist-letter-header-formatting
**Branch**: `031-persist-letter-header-formatting`
**Spec**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Data model**: [data-model.md](data-model.md) · **Contract**: [contracts/letters_v2_api.md](contracts/letters_v2_api.md)

Single user story (P1): "Header fields and their formatting persist across sessions." Four header fields in scope: Reference Number, Date, Recipient, Subject. Whole-field formatting (font size, bold, underline). Rich-text deferred.

---

## Phase 1 — Setup

_(none — additive change to an existing feature, no scaffolding required)_

## Phase 2 — Foundational

- [x] T001 Create Supabase migration `supabase/migrations/20260408_letter_header_formatting.sql` adding 12 nullable columns to `generated_letters`

## Phase 3 — User Story 1: Persist & restore header formatting (P1)

**Goal**: Saved letters reload with the same Reference Number, Date, Recipient, and Subject text **and** formatting that the user left them with.

**Independent test**: Apply migration → restart backend → run frontend → create a letter with non-default formatting on all four header fields → save → reopen → verify all four rows show original text and formatting → verify exporting to PDF reflects the same formatting.

### Backend

- [x] T002 [US1] Extend `LetterBodyV2` Pydantic schema in `backend/routers/letters_v2.py` with the 5 missing formatting fields
- [x] T003 [US1] Update `POST /letters-v2/generate` handler in `backend/routers/letters_v2.py` to write all 12 formatting columns on INSERT
- [x] T004 [US1] Update `PUT /letters-v2/{id}` handler in `backend/routers/letters_v2.py` to write all 12 formatting columns on UPDATE
- [x] T005 [US1] Update letter read/serialize path in `backend/routers/letters_v2.py` (GET list/detail) to include all 12 formatting keys, coalescing NULL → defaults
- [x] T006 [US1] Fix `POST /letters-v2/{id}/regenerate` in `backend/routers/letters_v2.py` to read saved formatting from the row instead of hardcoded defaults

### Frontend (model)

- [x] T007 [P] [US1] Add 12 formatting fields + (de)serialization to `frontend/lib/models/generated_letter.dart`
- [x] T008 [US1] Add 5 missing state variables (date + ref/recipient underlines) to `_LetterFormTabV2State` in `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
- [x] T009 [US1] Restore all 12 formatting state vars from `widget.existingLetter` in `initState` in `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
- [x] T010 [US1] Include all 12 formatting keys in the three save-payload bodies in `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
- [x] T011 [US1] Add font-size / bold / underline control row to the Date field in `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`, matching the pattern used by Reference Number

## Phase 4 — Polish

- [x] T012 Run the manual verification script in [quickstart.md](quickstart.md) end-to-end and confirm all scenarios pass

---

## Dependency graph

```
T001 ──┐
       ├─→ T002 ─→ T003 ─→ T005 ─→ T006
       │            │
       │            └─→ T004 ─┘
       │
       └─ (independent of frontend)

T007 ──┐  (parallel with all backend tasks T001–T006)
       └─→ T008 ─→ T009 ─→ T010
                   │        │
                   └────────┴─→ T011 (UI row, depends on T008 state vars)

All of the above ─→ T012 (manual verify)
```

## Parallel opportunities

- **T007** runs in parallel with the entire backend chain (T001–T006). They touch disjoint files.
- Within the backend chain, T003 and T004 can run in parallel after T002 (different functions, no shared mutable state in code).

## MVP scope

The entire feature is one P1 story; the MVP is the full task list. There is no smaller deliverable that fixes the reported bug.

---

# Task details

---

## T001 — Migration: add formatting columns

**File**: `supabase/migrations/20260408_letter_header_formatting.sql` (NEW)

**What to add**: A single SQL file that adds 12 nullable columns to `generated_letters` with the documented defaults.

**Exact SQL**:

```sql
-- Feature 031: persist letter header field formatting (whole-field).
-- Adds font_size / bold / underline columns for Reference Number, Date,
-- Recipient, and Subject fields. All nullable; legacy rows coalesce to
-- the documented defaults on read.

alter table public.generated_letters
  add column if not exists ref_font_size       numeric default 11,
  add column if not exists ref_bold            boolean default false,
  add column if not exists ref_underline       boolean default false,
  add column if not exists tarikh_font_size    numeric default 11,
  add column if not exists tarikh_bold         boolean default false,
  add column if not exists tarikh_underline    boolean default false,
  add column if not exists recipient_font_size numeric default 12,
  add column if not exists recipient_bold      boolean default false,
  add column if not exists recipient_underline boolean default false,
  add column if not exists subject_font_size   numeric default 13,
  add column if not exists subject_bold        boolean default true,
  add column if not exists subject_underline   boolean default true;
```

**Dependencies**: none.

**Acceptance**: Migration file exists at the path above with exactly the SQL shown. Applying it against an existing Supabase instance succeeds, is idempotent (safe to re-run), and adds 12 columns visible via `\d generated_letters`. Existing rows have NULL in all 12 new columns.

---

## T002 — Extend `LetterBodyV2` Pydantic schema

**File**: `backend/routers/letters_v2.py`

**What to modify**: The `LetterBodyV2` class (around lines 77–98) currently exposes 7 formatting fields. Add the 5 missing ones so the schema covers all 12.

**Fields to add** (with exact types and defaults — keep the existing field order and append these):

```python
ref_underline: bool = False
tarikh_font_size: float = 11
tarikh_bold: bool = False
tarikh_underline: bool = False
recipient_underline: bool = False
```

**Dependencies**: none (can technically precede T001, but logically grouped).

**Acceptance**: `LetterBodyV2` has exactly 12 formatting fields covering `{ref, tarikh, recipient, subject} × {font_size, bold, underline}`. Existing field names are unchanged. Defaults match `data-model.md`. The module imports nothing new. `python -c "from backend.routers.letters_v2 import LetterBodyV2; print(LetterBodyV2.__fields__.keys())"` lists all 12.

---

## T003 — Persist on INSERT (generate endpoint)

**File**: `backend/routers/letters_v2.py`

**What to modify**: The `POST /letters-v2/generate` handler (around lines 277–327). The dict that is passed to the Supabase `insert(...)` call currently writes only text fields. Extend that dict to include all 12 formatting keys read from the validated `LetterBodyV2` request body.

**Keys to add to the insert payload** (snake_case, matching the migration columns):

```python
"ref_font_size":       body.ref_font_size,
"ref_bold":            body.ref_bold,
"ref_underline":       body.ref_underline,
"tarikh_font_size":    body.tarikh_font_size,
"tarikh_bold":         body.tarikh_bold,
"tarikh_underline":    body.tarikh_underline,
"recipient_font_size": body.recipient_font_size,
"recipient_bold":      body.recipient_bold,
"recipient_underline": body.recipient_underline,
"subject_font_size":   body.subject_font_size,
"subject_bold":        body.subject_bold,
"subject_underline":   body.subject_underline,
```

**Dependencies**: T001, T002.

**Acceptance**: After this task, calling `POST /letters-v2/generate` with formatting fields in the request body causes those exact values to appear in the corresponding columns of the new row. Verified by inspecting Supabase row directly. No other behavior changes; existing text fields and PDF generation still work.

---

## T004 — Persist on UPDATE (PUT endpoint)

**File**: `backend/routers/letters_v2.py`

**What to modify**: The `PUT /letters-v2/{letter_id}` handler (around lines 356–396). The dict passed to the Supabase `update(...)` call currently writes only text fields. Extend it with the same 12 formatting keys (same expression list as T003).

**Dependencies**: T001, T002.

**Acceptance**: Editing a saved letter and PUT-ing the new body persists the new formatting values to the row's columns. A subsequent GET returns the updated values.

---

## T005 — Include formatting in read responses

**File**: `backend/routers/letters_v2.py`

**What to modify**: Wherever the router converts a `generated_letters` row into the JSON response returned by the GET list endpoint (and the GET-by-id / generate / update responses if they reuse the same shape). Ensure each returned letter object includes all 12 formatting keys, **coalescing NULL to the documented defaults** so legacy rows render identically.

**Helper to introduce** (private module-level function):

```python
def _coalesce_letter_format(row: dict) -> dict:
    """Return a dict containing the 12 formatting keys with NULL → defaults applied."""
    return {
        "ref_font_size":       row.get("ref_font_size") if row.get("ref_font_size") is not None else 11,
        "ref_bold":            row.get("ref_bold") if row.get("ref_bold") is not None else False,
        "ref_underline":       row.get("ref_underline") if row.get("ref_underline") is not None else False,
        "tarikh_font_size":    row.get("tarikh_font_size") if row.get("tarikh_font_size") is not None else 11,
        "tarikh_bold":         row.get("tarikh_bold") if row.get("tarikh_bold") is not None else False,
        "tarikh_underline":    row.get("tarikh_underline") if row.get("tarikh_underline") is not None else False,
        "recipient_font_size": row.get("recipient_font_size") if row.get("recipient_font_size") is not None else 12,
        "recipient_bold":      row.get("recipient_bold") if row.get("recipient_bold") is not None else False,
        "recipient_underline": row.get("recipient_underline") if row.get("recipient_underline") is not None else False,
        "subject_font_size":   row.get("subject_font_size") if row.get("subject_font_size") is not None else 13,
        "subject_bold":        row.get("subject_bold") if row.get("subject_bold") is not None else True,
        "subject_underline":   row.get("subject_underline") if row.get("subject_underline") is not None else True,
    }
```

Then merge `_coalesce_letter_format(row)` into every letter object the router returns from GET / generate / update endpoints (i.e. spread the keys into the response dict before returning).

**Dependencies**: T001.

**Acceptance**: Every endpoint that returns a letter (or list of letters) includes all 12 formatting keys in each item. Legacy rows (with NULL columns) are returned with the documented defaults. New rows are returned with their stored values. No keys are missing. JSON shape matches `contracts/letters_v2_api.md`.

---

## T006 — Regenerate from DB instead of hardcoded defaults

**File**: `backend/routers/letters_v2.py`

**What to modify**: The `POST /letters-v2/{id}/regenerate` handler (around lines 432–442) currently constructs a `LetterBodyV2` with hardcoded default formatting. Replace those literals with the values read from the loaded row, falling back to the documented defaults via the helper from T005.

**Approach**: After loading the existing row from Supabase, build the `LetterBodyV2` like:

```python
fmt = _coalesce_letter_format(row)
body = LetterBodyV2(
    ishara=row["ishara"],
    tarikh=row["tarikh"],
    alsayed=row["alsayed"],
    almawdoo=row["almawdoo"],
    body_text=row["body_text"],
    alasm=row["alasm"],
    **fmt,
)
```

(Adapt argument list to whatever fields `LetterBodyV2` requires; the point is `**fmt` replaces the previously-hardcoded formatting kwargs.)

**Dependencies**: T002, T005.

**Acceptance**: Regenerating the PDF for a letter that was saved with non-default formatting produces a PDF that matches what the editor shows. Verified by visually comparing the regenerated PDF to the editor for a Subject set to size 18, bold off, underline off. Legacy rows still regenerate correctly using the documented defaults.

---

## T007 — Add formatting fields to `GeneratedLetter` model

**File**: `frontend/lib/models/generated_letter.dart`

**What to modify**:

1. Add 12 final fields to the class:

```dart
final double refFontSize;
final bool   refBold;
final bool   refUnderline;
final double tarikhFontSize;
final bool   tarikhBold;
final bool   tarikhUnderline;
final double recipientFontSize;
final bool   recipientBold;
final bool   recipientUnderline;
final double subjectFontSize;
final bool   subjectBold;
final bool   subjectUnderline;
```

2. Add them as named parameters to the constructor with the documented defaults:

```dart
this.refFontSize       = 11,
this.refBold           = false,
this.refUnderline      = false,
this.tarikhFontSize    = 11,
this.tarikhBold        = false,
this.tarikhUnderline   = false,
this.recipientFontSize = 12,
this.recipientBold     = false,
this.recipientUnderline = false,
this.subjectFontSize   = 13,
this.subjectBold       = true,
this.subjectUnderline  = true,
```

3. In `fromJson`, read each key with default fallback:

```dart
refFontSize:        (json['ref_font_size']       as num?)?.toDouble() ?? 11,
refBold:             json['ref_bold']            as bool?           ?? false,
refUnderline:        json['ref_underline']       as bool?           ?? false,
tarikhFontSize:     (json['tarikh_font_size']    as num?)?.toDouble() ?? 11,
tarikhBold:          json['tarikh_bold']         as bool?           ?? false,
tarikhUnderline:     json['tarikh_underline']    as bool?           ?? false,
recipientFontSize:  (json['recipient_font_size'] as num?)?.toDouble() ?? 12,
recipientBold:       json['recipient_bold']      as bool?           ?? false,
recipientUnderline:  json['recipient_underline'] as bool?           ?? false,
subjectFontSize:    (json['subject_font_size']   as num?)?.toDouble() ?? 13,
subjectBold:         json['subject_bold']        as bool?           ?? true,
subjectUnderline:    json['subject_underline']   as bool?           ?? true,
```

4. In `toJson`, emit all 12 keys with snake_case names and the corresponding field values.

**Dependencies**: none (independent of backend; can run in parallel).

**Acceptance**: `GeneratedLetter` exposes 12 new fields. `GeneratedLetter.fromJson({})` (empty map) returns an instance with the documented default values for all 12. `fromJson` followed by `toJson` round-trips the values for a populated map. No existing field is renamed or removed. The file still compiles and existing call sites that omit the new fields still work because every new constructor parameter has a default.

---

## T008 — Add missing form state variables

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`

**What to modify**: In `_LetterFormTabV2State` (the field-declarations area around lines 34–58), add the 5 missing state variables alongside the existing ones, with the documented defaults:

```dart
bool   _refUnderline       = false;
double _dateFontSize       = 11;
bool   _dateBold           = false;
bool   _dateUnderline      = false;
bool   _recipientUnderline = false;
```

(`_refFontSize`, `_refBold`, `_recipientFontSize`, `_recipientBold`, `_subjectFontSize`, `_subjectBold`, `_subjectUnderline` already exist — do not duplicate.)

**Dependencies**: none for the additions themselves, but T009/T010/T011 depend on these existing.

**Acceptance**: All 12 state variables exist on `_LetterFormTabV2State`. The file compiles. No other state is touched.

---

## T009 — Restore formatting state on load

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`

**What to modify**: `initState` (the existing-letter restoration block around lines 76–111). After the existing text-restoration lines (the ones that assign `_isharaCtrl.text`, `_alsayedCtrl.text`, `_almawdooCtrl.text`, and the date), add 12 assignments restoring formatting from `widget.existingLetter!`:

```dart
_refFontSize        = widget.existingLetter!.refFontSize;
_refBold            = widget.existingLetter!.refBold;
_refUnderline       = widget.existingLetter!.refUnderline;
_dateFontSize       = widget.existingLetter!.tarikhFontSize;
_dateBold           = widget.existingLetter!.tarikhBold;
_dateUnderline      = widget.existingLetter!.tarikhUnderline;
_recipientFontSize  = widget.existingLetter!.recipientFontSize;
_recipientBold      = widget.existingLetter!.recipientBold;
_recipientUnderline = widget.existingLetter!.recipientUnderline;
_subjectFontSize    = widget.existingLetter!.subjectFontSize;
_subjectBold        = widget.existingLetter!.subjectBold;
_subjectUnderline   = widget.existingLetter!.subjectUnderline;
```

These assignments must be inside the same `if (widget.existingLetter != null) { ... }` branch that already restores the text fields. Do not call `setState` — `initState` runs before the first build.

**Dependencies**: T007 (model fields must exist), T008 (state vars must exist).

**Acceptance**: Opening a letter that was saved with `subjectFontSize: 18, subjectBold: false` results in the Subject row's font-size control reading 18 and the Bold toggle being off, before the user touches anything. Legacy letters (with default values from `fromJson` fallback) load with the documented defaults.

---

## T010 — Include formatting in save payloads

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`

**What to modify**: The three places that build the request body for letter save/generate/update (around lines 241–259, 380–397, 499–516). Each currently includes some formatting keys but not all 12. Extend each body to include exactly these 12 keys with the corresponding state variables:

```dart
'ref_font_size':       _refFontSize,
'ref_bold':            _refBold,
'ref_underline':       _refUnderline,
'tarikh_font_size':    _dateFontSize,
'tarikh_bold':         _dateBold,
'tarikh_underline':    _dateUnderline,
'recipient_font_size': _recipientFontSize,
'recipient_bold':      _recipientBold,
'recipient_underline': _recipientUnderline,
'subject_font_size':   _subjectFontSize,
'subject_bold':        _subjectBold,
'subject_underline':   _subjectUnderline,
```

Do not change any other keys in those bodies.

**Dependencies**: T008.

**Acceptance**: All three save/update HTTP request bodies contain all 12 formatting keys with the values currently held in state. Verified by reading the source and (optionally) inspecting the network tab when saving from the editor.

---

## T011 — Date row formatting controls

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`

**What to modify**: The Date field row (currently around lines 615–635, where `showDatePicker` is wired up). Add a control row immediately under (or beside) the date input that lets the user adjust font size, bold, and underline for the Date field — visually and behaviorally matching the existing Reference Number control row at lines 595–611.

**Constraints**:
- Reuse the **exact same widget pattern** the Reference Number row uses (size selector, Bold toggle, Underline toggle). Do not introduce a new widget abstraction.
- The size selector must be bound to `_dateFontSize`, the bold toggle to `_dateBold`, the underline toggle to `_dateUnderline`.
- Wrap state changes in `setState(() { ... })`.
- Do not change the date picker behavior, the date format, or any other field.

**Dependencies**: T008.

**Acceptance**: The Date row has a font-size selector, a Bold toggle, and an Underline toggle that visibly match the styling and layout of the Reference Number row. Changing them updates the corresponding state variables. After saving and reopening, the chosen values persist (verified together with T009 + T010).

---

## T012 — Manual end-to-end verification

**File**: N/A (testing task).

**What to do**: Apply the migration to the dev Supabase, restart the FastAPI backend, run the Flutter frontend, and execute every scenario in [quickstart.md](quickstart.md): Scenarios 1–4, the Date field check, the Legacy letter edge case, the PDF export edge case, and the Cleared formatting edge case.

**Dependencies**: T001–T011 all complete.

**Acceptance**: All quickstart scenarios pass. No errors in browser console. No errors in backend logs. PDF export visibly reflects the saved formatting on all four header fields.

---

# Implementation prompts

--- IMPLEMENTATION PROMPT T001 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: SQL (Postgres / Supabase)
File: supabase/migrations/20260408_letter_header_formatting.sql (NEW)
Task: Create a new Supabase migration that adds 12 nullable columns to public.generated_letters with the documented defaults to persist whole-field formatting (font_size, bold, underline) for the Reference Number, Date (tarikh), Recipient, and Subject header fields.
Signatures required: none (DDL only)
Constraints:
- Use `add column if not exists` for every column so the migration is idempotent.
- Column types: numeric for *_font_size, boolean for *_bold and *_underline.
- Defaults: ref/tarikh font_size=11; recipient font_size=12; subject font_size=13; subject_bold=true; subject_underline=true; all other booleans default false.
- All 12 columns must be nullable (do not add NOT NULL).
- Do not create indexes, triggers, or RLS changes.
- File must be a single SQL file with a brief leading comment referencing feature 031.
Acceptance criteria:
- File exists at the exact path above.
- Running it on a Postgres instance that already has `public.generated_letters` adds the 12 columns successfully.
- Re-running the file is a no-op (no errors).
- Existing rows now have NULL in the 12 new columns; new inserts that omit the columns get the defaults.
--- END PROMPT T001 ---

--- IMPLEMENTATION PROMPT T002 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py
Task: Extend the `LetterBodyV2` Pydantic model so it exposes all 12 whole-field formatting fields for the four header fields {ref, tarikh, recipient, subject} × {font_size, bold, underline}. Today the class already declares ref_font_size, ref_bold, recipient_font_size, recipient_bold, subject_font_size, subject_bold, subject_underline. Add the 5 missing fields: ref_underline, tarikh_font_size, tarikh_bold, tarikh_underline, recipient_underline.
Signatures required:
- ref_underline: bool = False
- tarikh_font_size: float = 11
- tarikh_bold: bool = False
- tarikh_underline: bool = False
- recipient_underline: bool = False
Constraints:
- Do not rename or reorder existing fields.
- Do not change defaults of existing fields.
- Do not add new imports.
- Place the new fields adjacent to the related existing field for readability (e.g. ref_underline next to ref_bold).
Acceptance criteria:
- `LetterBodyV2.__fields__` contains exactly 12 formatting fields covering all combinations.
- The module still imports cleanly (`python -c "import backend.routers.letters_v2"`).
- Existing tests (if any) that construct LetterBodyV2 with only the previous field set still work because all new fields have defaults.
--- END PROMPT T002 ---

--- IMPLEMENTATION PROMPT T003 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py
Task: In the `POST /letters-v2/generate` handler, extend the dict passed to `supabase.table("generated_letters").insert(...)` so it persists all 12 formatting fields from the validated `LetterBodyV2` request body. The text-field portion of the insert payload is unchanged.
Signatures required: none (modifying the existing handler body)
Constraints:
- Read each formatting value from the request body parameter (the `LetterBodyV2` instance), not from a global or default.
- Use snake_case keys exactly matching the column names from migration T001: ref_font_size, ref_bold, ref_underline, tarikh_font_size, tarikh_bold, tarikh_underline, recipient_font_size, recipient_bold, recipient_underline, subject_font_size, subject_bold, subject_underline.
- Do not change any other key in the insert payload.
- Do not change the return shape of the endpoint (T005 will handle response shaping).
Acceptance criteria:
- After calling the endpoint with a body that includes formatting values, those exact values appear in the new row when queried directly from Supabase.
- A request that omits formatting fields still succeeds (Pydantic supplies the defaults from T002), and the row carries the default values.
--- END PROMPT T003 ---

--- IMPLEMENTATION PROMPT T004 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py
Task: In the `PUT /letters-v2/{letter_id}` handler, extend the dict passed to `supabase.table("generated_letters").update(...)` so it persists all 12 formatting fields from the validated `LetterBodyV2` request body. The text-field portion of the update payload is unchanged.
Signatures required: none (modifying the existing handler body)
Constraints:
- Same 12 snake_case keys as T003.
- Do not change any other key.
- Do not change the return shape (T005 owns response shaping).
Acceptance criteria:
- PUT-ing a letter with new formatting values updates exactly those 12 columns in the row.
- Subsequent GET returns the updated values.
--- END PROMPT T004 ---

--- IMPLEMENTATION PROMPT T005 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py
Task: Introduce a private helper `_coalesce_letter_format(row: dict) -> dict` that returns the 12 formatting keys with NULL coalesced to the documented defaults. Then, wherever this router builds a JSON-serializable letter dict for an HTTP response (GET list, GET by id if present, the response of `POST /letters-v2/generate`, the response of `PUT /letters-v2/{id}`), spread the helper's output into the response object so every returned letter contains all 12 formatting keys.
Signatures required:
- def _coalesce_letter_format(row: dict) -> dict
Constraints:
- Defaults inside the helper:
    ref_font_size=11, ref_bold=False, ref_underline=False,
    tarikh_font_size=11, tarikh_bold=False, tarikh_underline=False,
    recipient_font_size=12, recipient_bold=False, recipient_underline=False,
    subject_font_size=13, subject_bold=True, subject_underline=True.
- Use `row.get(key)` and an explicit `is None` check when coalescing — do not use truthiness (so `False` and `0` are not replaced).
- Do not change the existing text-field keys in any response.
- Do not break legacy clients: only ADD keys, never rename or remove.
- Keep the helper module-private (leading underscore) and do not export it.
Acceptance criteria:
- Every HTTP response returning a letter (singular or list item) contains all 12 formatting keys.
- A row whose new columns are NULL is returned with the documented defaults.
- A row with stored values returns those stored values unchanged.
- Existing endpoints continue to return all the fields they returned before.
--- END PROMPT T005 ---

--- IMPLEMENTATION PROMPT T006 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py
Task: Fix the `POST /letters-v2/{id}/regenerate` handler so it builds the `LetterBodyV2` from the **stored** row values (formatting included) instead of hardcoded defaults. Use `_coalesce_letter_format(row)` from T005 to obtain the 12 formatting kwargs, then pass them to `LetterBodyV2(...)` via `**fmt`.
Signatures required: none (modifying existing handler body)
Constraints:
- Do not change the URL or signature of the endpoint.
- Do not change `_build_letter_pdf_v2()`.
- Preserve the text fields (ishara, tarikh, alsayed, almawdoo, body_text, alasm, etc.) — read them from the row exactly as today.
- Replace ONLY the formatting kwargs that were previously hardcoded.
Acceptance criteria:
- Regenerating a letter that was saved with non-default formatting produces a PDF whose Reference Number / Date / Recipient / Subject rows visually match what the editor showed.
- Regenerating a legacy letter (NULL formatting columns) produces the same PDF it produced before this feature shipped (defaults).
--- END PROMPT T006 ---

--- IMPLEMENTATION PROMPT T007 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/models/generated_letter.dart
Task: Extend the `GeneratedLetter` class with 12 final fields covering whole-field formatting for {ref, tarikh, recipient, subject} × {font_size, bold, underline}. Add corresponding constructor parameters with defaults, deserialize from snake_case JSON keys with default fallback, and serialize back via `toJson`.
Signatures required (add to the class):
- final double refFontSize;
- final bool   refBold;
- final bool   refUnderline;
- final double tarikhFontSize;
- final bool   tarikhBold;
- final bool   tarikhUnderline;
- final double recipientFontSize;
- final bool   recipientBold;
- final bool   recipientUnderline;
- final double subjectFontSize;
- final bool   subjectBold;
- final bool   subjectUnderline;
Constructor parameters (named, with defaults):
- this.refFontSize = 11, this.refBold = false, this.refUnderline = false,
- this.tarikhFontSize = 11, this.tarikhBold = false, this.tarikhUnderline = false,
- this.recipientFontSize = 12, this.recipientBold = false, this.recipientUnderline = false,
- this.subjectFontSize = 13, this.subjectBold = true, this.subjectUnderline = true,
fromJson key mapping (with defaults if missing/null):
- ref_font_size       → refFontSize        (num → double, default 11)
- ref_bold            → refBold            (default false)
- ref_underline       → refUnderline       (default false)
- tarikh_font_size    → tarikhFontSize     (default 11)
- tarikh_bold         → tarikhBold         (default false)
- tarikh_underline    → tarikhUnderline    (default false)
- recipient_font_size → recipientFontSize  (default 12)
- recipient_bold      → recipientBold      (default false)
- recipient_underline → recipientUnderline (default false)
- subject_font_size   → subjectFontSize    (default 13)
- subject_bold        → subjectBold        (default true)
- subject_underline   → subjectUnderline   (default true)
toJson must emit all 12 keys with the snake_case names above.
Constraints:
- Do not rename or remove any existing field.
- Do not change the existing constructor's existing parameters' defaults.
- All new constructor parameters must be optional (have defaults) so existing call sites compile unchanged.
- Use `(json['key'] as num?)?.toDouble() ?? <default>` for the font_size fields.
- Use `json['key'] as bool? ?? <default>` for the boolean fields.
- No new package imports.
Acceptance criteria:
- `GeneratedLetter.fromJson({})` produces an instance with the documented defaults for all 12 new fields and does not throw.
- `GeneratedLetter.fromJson({'subject_font_size': 18, 'subject_bold': false}).subjectFontSize == 18` and `.subjectBold == false`.
- `letter.toJson()` includes all 12 snake_case keys with the field values.
- The file compiles. No existing usage of `GeneratedLetter` elsewhere in the repo breaks (because new params are optional).
--- END PROMPT T007 ---

--- IMPLEMENTATION PROMPT T008 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart
Task: In the State class `_LetterFormTabV2State` (the field declarations area near the top, around lines 34–58), add 5 new mutable state variables alongside the existing formatting state. Do not duplicate any field that already exists.
Signatures required (add as instance fields in `_LetterFormTabV2State`):
- bool   _refUnderline       = false;
- double _dateFontSize       = 11;
- bool   _dateBold           = false;
- bool   _dateUnderline      = false;
- bool   _recipientUnderline = false;
Constraints:
- Do not modify any existing field.
- Do not introduce a class, struct, or helper.
- Place the additions next to the related existing fields for readability (e.g. `_refUnderline` next to `_refBold`).
- No new imports.
Acceptance criteria:
- The State class now declares all 12 formatting state variables in total (7 existing + 5 new).
- The file still compiles.
--- END PROMPT T008 ---

--- IMPLEMENTATION PROMPT T009 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart
Task: In `initState`, inside the existing `if (widget.existingLetter != null)` branch that already restores text fields (around lines 76–111), add 12 assignments that copy the formatting values from `widget.existingLetter!` into the corresponding state variables. Place these assignments after the text-field assignments and after the date restoration logic.
Signatures required: none (modifying the existing initState body)
Assignments to add (exactly):
- _refFontSize        = widget.existingLetter!.refFontSize;
- _refBold            = widget.existingLetter!.refBold;
- _refUnderline       = widget.existingLetter!.refUnderline;
- _dateFontSize       = widget.existingLetter!.tarikhFontSize;
- _dateBold           = widget.existingLetter!.tarikhBold;
- _dateUnderline      = widget.existingLetter!.tarikhUnderline;
- _recipientFontSize  = widget.existingLetter!.recipientFontSize;
- _recipientBold      = widget.existingLetter!.recipientBold;
- _recipientUnderline = widget.existingLetter!.recipientUnderline;
- _subjectFontSize    = widget.existingLetter!.subjectFontSize;
- _subjectBold        = widget.existingLetter!.subjectBold;
- _subjectUnderline   = widget.existingLetter!.subjectUnderline;
Constraints:
- Do not call `setState` (initState runs before first build).
- Do not touch any existing text-field restoration line.
- Do not introduce conditionals around individual assignments — `GeneratedLetter` always provides values via its defaults.
- These assignments must be inside the same `if (widget.existingLetter != null) { ... }` block.
Dependencies: T007 (the model fields), T008 (the state variables).
Acceptance criteria:
- Reopening a letter that was saved with `subjectBold: false` shows the Subject's Bold toggle off in the editor on first build.
- Reopening a legacy letter shows the documented default formatting on every header row.
--- END PROMPT T009 ---

--- IMPLEMENTATION PROMPT T010 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart
Task: In each of the three places this file builds the JSON request body for letter save/generate/update (around lines 241–259, 380–397, 499–516), ensure the body map contains all 12 formatting keys with the corresponding state variables. Some keys are already present today; add the missing ones and do not duplicate the existing ones.
Signatures required: none (modifying existing map literals)
Keys (snake_case) and their bindings:
- 'ref_font_size':       _refFontSize,
- 'ref_bold':            _refBold,
- 'ref_underline':       _refUnderline,
- 'tarikh_font_size':    _dateFontSize,
- 'tarikh_bold':         _dateBold,
- 'tarikh_underline':    _dateUnderline,
- 'recipient_font_size': _recipientFontSize,
- 'recipient_bold':      _recipientBold,
- 'recipient_underline': _recipientUnderline,
- 'subject_font_size':   _subjectFontSize,
- 'subject_bold':        _subjectBold,
- 'subject_underline':   _subjectUnderline,
Constraints:
- Do not change any other key in any of the three bodies.
- Do not introduce a helper function or shared map; copy the keys into each of the three sites verbatim (the file already follows this pattern).
- Snake_case keys must match the backend Pydantic field names from T002.
Dependencies: T008.
Acceptance criteria:
- All three save/update HTTP request bodies include exactly the 12 keys above.
- The file compiles.
- Saving a letter with non-default formatting causes those values to appear in the network request body.
--- END PROMPT T010 ---

--- IMPLEMENTATION PROMPT T011 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart
Task: Add a font-size / bold / underline control row to the Date field row (around lines 615–635, where `showDatePicker` is wired up) so the Date field has the same formatting controls already present on the Reference Number row (lines 595–611). The new controls must be bound to `_dateFontSize`, `_dateBold`, and `_dateUnderline`.
Signatures required: none (only widget tree changes)
Constraints:
- Mirror the EXACT widget pattern used by the Reference Number row — same widgets, same callback shape, same visual style. Do NOT introduce a new abstraction or shared helper widget.
- Wrap each state mutation in `setState(() { ... })`.
- Bindings:
    size selector value ↔ _dateFontSize
    bold toggle value   ↔ _dateBold
    underline toggle    ↔ _dateUnderline
- Do not change the date picker behavior, the displayed date format, or any other widget on this row.
- Do not modify any other field's row.
Dependencies: T008.
Acceptance criteria:
- The Date row visually shows three controls matching the Reference Number row.
- Adjusting them mutates the corresponding state variables and triggers a rebuild.
- With T009 + T010 in place, the chosen Date formatting persists across save/reload.
--- END PROMPT T011 ---

--- IMPLEMENTATION PROMPT T012 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: N/A (manual verification)
File: N/A — execute the steps in specs/031-persist-letter-header-formatting/quickstart.md
Task: Run every scenario in quickstart.md against a dev environment where the migration from T001 has been applied, the backend has been restarted, and the frontend is running. Report any failure with the exact step number and observed vs expected behavior.
Signatures required: none
Constraints:
- Do not write code.
- Do not skip the legacy-letter scenario or the PDF export scenario.
- Use a real Supabase row that pre-dates the migration for the legacy scenario.
Acceptance criteria:
- All quickstart scenarios pass.
- No errors in browser console or backend logs during the run.
- PDF export visually reflects the saved formatting on all four header fields.
--- END PROMPT T012 ---
