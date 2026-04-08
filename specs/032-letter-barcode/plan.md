# Implementation Plan: Letter Reference Barcode

**Branch**: `032-letter-barcode` | **Date**: 2026-04-08 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/032-letter-barcode/spec.md`

## Summary

Render a Code 128 barcode encoding the letter reference number (`ishara`) directly above the existing reference text in the v2 letter PDF. Backend-only change: add `python-barcode` dependency, generate a base64 PNG data URI in `letters_v2.py` mirroring the existing `_logo_data_uri` pattern, and inject the image into `letter_template.html` via a Jinja-guarded `<img>` tag with a small CSS rule.

## Technical Context

**Language/Version**: Python 3.10 (backend)
**Primary Dependencies**: FastAPI, Jinja2, WeasyPrint, Pillow (existing); `python-barcode==0.15.1` (NEW)
**Storage**: N/A (no DB or filesystem changes — barcode is in-memory PNG → base64 data URI)
**Testing**: Manual end-to-end PDF generation + barcode-scanner verification
**Target Platform**: Linux server (production), Windows dev
**Project Type**: Web application (FastAPI backend + Flutter frontend); only backend touched
**Performance Goals**: Barcode generation < 50ms per letter; no measurable regression in letter PDF generation latency
**Constraints**: Pure-Python dependency only (no system libs); barcode height ~38px; gracefully omit barcode on encoding failure
**Scale/Scope**: One backend file, one template file, one requirements update

## Constitution Check

| Principle | Status | Notes |
|---|---|---|
| I. Full-Stack Ownership | ✅ PASS | Backend-only feature; frontend/DB explicitly excluded with documented rationale (no schema or API contract change). |
| II. Explicit Over Automatic | ✅ PASS | Barcode is explicitly rendered only when `ishara` is non-empty; guarded by template `{% if %}`. |
| III. Role-Based Access Control | ✅ N/A | No new endpoints or permissions. |
| IV. Server-First File Storage | ✅ PASS | No file storage; barcode embedded inline as data URI. |
| V. Client-Side Computation | ✅ N/A | Server-side PDF rendering, no client compute. |
| VI. Audit Everything | ✅ N/A | No new user-facing action; piggybacks on existing letter generation audit. |
| VII. Simplicity & YAGNI | ✅ PASS | One helper, one template line, one CSS rule — minimum viable change. |

**Result**: All gates pass. No Complexity Tracking entries required.

## Project Structure

### Documentation (this feature)

```text
specs/032-letter-barcode/
├── plan.md              # This file
├── spec.md              # Feature spec
├── research.md          # Phase 0 — library/option choice
├── quickstart.md        # Phase 1 — manual verification steps
└── checklists/
    └── requirements.md
```

No `data-model.md` (no entities), no `contracts/` (no new API surface).

### Source Code (repository root)

```text
backend/
├── requirements.txt                  # add python-barcode==0.15.1
├── routers/
│   └── letters_v2.py                 # add _generate_barcode_data_uri(); call in _build_letter_pdf_v2()
└── templates/
    └── letter_template.html          # add <img class="ref-barcode"> + .ref-barcode CSS
```

**Structure Decision**: Existing `backend/routers/` + `backend/templates/` layout. No new directories.

## Phase 0: Research

See [research.md](research.md). Single decision: `python-barcode` over `treepoem`/`reportlab.graphics.barcode`/`qrcode` — chosen for pure-Python install (no Ghostscript), Pillow-only PNG output, and Code 128 support with built-in human-readable text.

## Phase 1: Design

- **Data model**: None.
- **Contracts**: None — no API or schema change. The internal helper signature is `_generate_barcode_data_uri(value: str) -> str | None` (returns `None` on empty input or encoding failure so the template guard skips rendering).
- **Quickstart**: See [quickstart.md](quickstart.md).

## Complexity Tracking

None.
