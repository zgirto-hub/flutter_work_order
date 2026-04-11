# Quickstart: 036-cleanup-dead-letters-v1

**Date**: 2026-04-11

## What This Feature Does

Removes all dead code from the old letters v1 feature that has been fully superseded by letters v2.

## Files to Modify

### Delete
- `backend/routers/letters.py` — entire file (359 lines)

### Edit
- `backend/main.py` — remove `letters` import (line 28) and `app.include_router(letters.router, ...)` (line 88)
- `frontend/lib/services/letter_service.dart` — remove 5 dead v1 methods:
  - `fetchAll()` (lines 11-23)
  - `generate()` (lines 25-39)
  - `regenerate()` (lines 41-48)
  - `update()` (lines 127-140)
  - `linkPaymentCertificate()` (lines 178-189)

### Do NOT Modify
- `backend/requirements.txt` — `reportlab`, `arabic-reshaper`, `python-bidi` are shared with `reports.py`
- `generated_letters` database table — shared between v1 and v2
- Any v2 files or endpoints

## Verification Steps

1. Backend starts without import errors
2. All v2 endpoints respond correctly
3. Flutter app compiles without errors
4. No references to old v1 endpoints remain in the codebase
