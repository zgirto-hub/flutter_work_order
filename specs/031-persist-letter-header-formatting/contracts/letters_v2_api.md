# API Contract Deltas — letters_v2

All four endpoints below already exist. This feature only **adds fields** to their request and/or response payloads. No new endpoints, no path changes, no breaking changes.

## Common formatting payload fragment

```json
{
  "ref_font_size": 11,
  "ref_bold": false,
  "ref_underline": false,
  "tarikh_font_size": 11,
  "tarikh_bold": false,
  "tarikh_underline": false,
  "recipient_font_size": 12,
  "recipient_bold": false,
  "recipient_underline": false,
  "subject_font_size": 13,
  "subject_bold": true,
  "subject_underline": true
}
```

All twelve keys are optional in **requests** (server applies defaults if missing — preserves backward compatibility for any external caller). All twelve are always present in **responses** (server coalesces NULL to defaults).

## `POST /letters-v2/generate`

- **Request**: existing body + the 12 keys above (already accepted today; now also persisted).
- **Response**: existing fields + the 12 keys (echoed from what was just persisted).
- **DB write**: INSERT into `generated_letters` now includes all 12 columns.

## `PUT /letters-v2/{id}`

- **Request**: existing body + the 12 keys.
- **Response**: existing fields + the 12 keys.
- **DB write**: UPDATE `generated_letters` SET ... now includes all 12 columns.

## `GET /letters-v2`

- **Response**: each item gains the 12 keys, coalescing NULL → default for legacy rows.

## `POST /letters-v2/{id}/regenerate`

- **Request**: unchanged.
- **Behavior change**: instead of constructing `LetterBodyV2` with hardcoded defaults (current bug at letters_v2.py:432-442), read the persisted values from the row and pass them to `_build_letter_pdf_v2()`. This is the line that makes the regenerated PDF match what the user saw in the editor (Spec FR-006).

## Backwards compatibility

- **Old client → new server**: client omits the new keys; server applies defaults; row is saved with the documented defaults. No error.
- **New client → old data**: server reads NULL from legacy columns, coalesces to defaults; client receives a complete object. No error.
- **Old client → new server response**: client ignores unknown keys (Dart `fromJson` only reads the keys it knows). No error.
