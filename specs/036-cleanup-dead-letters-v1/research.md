# Research: 036-cleanup-dead-letters-v1

**Date**: 2026-04-11

## R1: Can `reportlab`, `arabic-reshaper`, `python-bidi` be removed?

**Decision**: NO — all three are shared dependencies, also used by `backend/routers/reports.py`.

**Rationale**: `reports.py` imports `reportlab` (lines 11-25, 258, 456), `arabic_reshaper` (line 70), and `bidi` (line 71). Removing them would break the reports feature.

**Alternatives considered**: Remove only from letters.py and leave in requirements.txt — this is the chosen approach since no dependency changes are needed.

## R2: Is `backend/routers/letters.py` imported anywhere besides `main.py`?

**Decision**: Only imported in `main.py` line 28, registered at line 88.

**Rationale**: Grep for `from routers.*letters[^_]` and `import.*letters[^_v]` returned no matches outside main.py. Safe to remove both the import and the router registration.

## R3: Are any frontend files calling v1 endpoints besides `letter_service.dart`?

**Decision**: No. All v1 endpoint calls are isolated to the 5 dead methods in `letter_service.dart`.

**Rationale**: Searched for `/letters/generate`, `/letters?`, `letters/$letterId/regenerate` (without `-v2`), and `link-letter` across all Dart files. Only matches are in `letter_service.dart` methods: `fetchAll()` (line 11), `generate()` (line 25), `regenerate()` (line 41), `update()` (line 127), `linkPaymentCertificate()` (line 178).

## R4: Are the dead v1 methods in `letter_service.dart` called from any screen or widget?

**Decision**: No — they are never called.

**Rationale**: The active screens (`letter_generator_screen_v2.dart`, `letter_form_tab_v2.dart`, `letter_history_tab_v2.dart`) exclusively use v2 methods: `fetchAllV2()`, `generateV2()`, `updateV2()`, `regenerateV2()`, `fetchOneV2()`, `uploadImage()`, `exportLetterWithAttachments()`, `delete()`.

## R5: Constitution Principle VII (Simplicity & YAGNI) — "unused features MUST be documented as unused rather than silently removed"

**Decision**: This principle applies to features whose future value is uncertain. The letters v1 is a fully superseded predecessor with zero callers and identical data — it has no future value. Documenting this removal in the commit message and spec is sufficient.

**Rationale**: Principle VII's intent is to prevent accidental removal of potentially useful code. Letters v1 is not "potentially useful" — it's a superseded implementation. The v2 replacement is complete and in production. Keeping dead code contradicts Principle VII's "Simplicity" mandate.
