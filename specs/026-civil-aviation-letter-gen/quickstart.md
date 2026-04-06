# Quickstart: Civil Aviation Letter Generator

**Feature**: 026-civil-aviation-letter-gen  
**Date**: 2026-04-06

## Prerequisites

- Backend running (`uvicorn main:app --reload`)
- Supabase migration applied (`20260406_generated_letters.sql`)
- NotoSansArabic font files added to `backend/assets/`
- Flutter frontend running (`flutter run -d chrome`)

## Setup Steps

### 1. Apply Database Migration

```sql
-- Run in Supabase SQL editor or apply via migration
-- File: supabase/migrations/20260406_generated_letters.sql
```

### 2. Add Arabic Font Files

Download NotoSansArabic-Regular.ttf and NotoSansArabic-Bold.ttf from Google Fonts and place in `backend/assets/`.

### 3. Backend

The new router `backend/routers/letters.py` is registered in `main.py` with prefix `/api`. Endpoints:

- `POST /api/letters/generate` — Generate PDF + save record
- `GET /api/letters?email=user@example.com` — Fetch history
- `POST /api/letters/{id}/regenerate` — Regenerate PDF from saved data

### 4. Frontend

Navigate to the letter generator screen from the main navigation. The screen has two tabs:

- **New Letter**: Form with all fields → Preview → Generate PDF
- **History**: Browse past letters, tap to regenerate PDF

### 5. Payment Certificate Linking

After creating a letter, link payment certificates to it via the letter history detail view or the payment certificate edit screen.

## Testing Checklist

1. Fill all form fields with Arabic text
2. Upload a signature image (PNG/JPG < 5MB)
3. Tap "Preview" — verify layout matches DGCA format
4. Tap "Generate PDF" — verify PDF downloads with correct content
5. Check history tab — verify the letter appears
6. Tap history entry — verify PDF regenerates correctly
7. Link a payment certificate — verify it shows under the letter
