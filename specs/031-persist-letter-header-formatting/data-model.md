# Data Model — Persist Letter Header Field Formatting

## Database: `generated_letters` (Supabase / PostgreSQL)

New columns (additive, nullable, with defaults):

| Column | Type | Default | Notes |
|---|---|---|---|
| `ref_font_size` | `numeric` | `11` | Reference Number font size in points |
| `ref_bold` | `boolean` | `false` | Reference Number bold flag |
| `ref_underline` | `boolean` | `false` | Reference Number underline flag |
| `tarikh_font_size` | `numeric` | `11` | Date font size in points |
| `tarikh_bold` | `boolean` | `false` | Date bold flag |
| `tarikh_underline` | `boolean` | `false` | Date underline flag |
| `recipient_font_size` | `numeric` | `12` | Recipient font size |
| `recipient_bold` | `boolean` | `false` | Recipient bold flag |
| `recipient_underline` | `boolean` | `false` | Recipient underline flag |
| `subject_font_size` | `numeric` | `13` | Subject font size |
| `subject_bold` | `boolean` | `true` | Subject bold flag |
| `subject_underline` | `boolean` | `true` | Subject underline flag |

All columns nullable so legacy rows (pre-migration) carry NULL and read-side coalesces to the defaults.

Migration file: `supabase/migrations/20260407_letter_header_formatting.sql`.

## Backend Pydantic schemas (`backend/routers/letters_v2.py`)

### `LetterBodyV2` (already exists — extend)

Add three fields not currently present:
- `ref_underline: bool = False`
- `tarikh_font_size: float = 11`
- `tarikh_bold: bool = False`
- `tarikh_underline: bool = False`
- `recipient_underline: bool = False`

(`ref_font_size`, `ref_bold`, `recipient_font_size`, `recipient_bold`, `subject_font_size`, `subject_bold`, `subject_underline` already exist.)

### Letter response (the dict returned by GET / generate / update)

Same 12 keys included alongside the existing text fields. Coalesce DB NULL to the documented defaults before serializing.

## Frontend Dart model (`frontend/lib/models/generated_letter.dart`)

### `GeneratedLetter` — new fields

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

### `fromJson`

For each field, read the JSON key (snake_case to match backend) and fall back to the documented default when the key is missing or null. Example:

```dart
refFontSize: (json['ref_font_size'] as num?)?.toDouble() ?? 11,
refBold:     json['ref_bold'] as bool? ?? false,
// ...
subjectUnderline: json['subject_underline'] as bool? ?? true,
```

### `toJson`

Serialize all 12 fields with snake_case keys.

## Frontend form state (`frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`)

### New state variables

```dart
double _dateFontSize  = 11;
bool   _dateBold      = false;
bool   _dateUnderline = false;
bool   _refUnderline  = false;       // pair with existing _refFontSize/_refBold
bool   _recipientUnderline = false;  // pair with existing recipient vars
```

### `initState` restoration block

When loading an existing letter, after the existing text restoration lines (≈ 79-81), add:

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

### Save bodies

The three POST/PUT bodies (≈ lines 241-259, 380-397, 499-516) already include the formatting keys for the existing fields. Add the missing date keys + `*_underline` keys for ref/recipient.

## Validation rules

- `*_font_size` MUST be a positive number. Reasonable bounds in the form: 8–48 pt (matches existing slider/dropdown ranges in the editor — verify when implementing).
- `*_bold` and `*_underline` MUST be boolean.
- No additional cross-field constraints.
