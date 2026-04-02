# Implementation Plan: HTML/CSS Template PDF for Payment Certificate

**Branch**: `002-use-html-css` | **Date**: 2026-04-02 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-use-html-css/spec.md`

## Summary

Replace the programmatic `pdf` package widget tree in `PaymentCertificatePdfService` with an HTML/CSS template-based approach. The template is stored as a Flutter asset, populated with certificate data at runtime, and converted to PDF widgets using `htmltopdfwidgets` (pure Dart). The complex payment table with merged headers (colspan) remains built with direct `pdf` widgets since no pure-Dart HTML-to-PDF library reliably supports colspan on all target platforms. The `build()` method signature is unchanged — callers are unaffected.

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x  
**Primary Dependencies**: `pdf` ^3.10.7 (existing), `printing` ^5.12.0 (existing), `htmltopdfwidgets` (NEW)  
**Storage**: N/A  
**Testing**: Manual visual comparison of PDF output across platforms  
**Target Platform**: Android, iOS, iOS PWA (standalone), web browsers  
**Project Type**: Mobile/web app (Flutter)  
**Performance Goals**: PDF export within same perceived time as current approach  
**Constraints**: Client-side only (no server dependency), iOS PWA WKWebView restrictions, Arabic RTL with Calibri fonts  
**Scale/Scope**: Single service rewrite + 1 new template asset

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Frontend-only change (PDF rendering). No backend/migration needed — explicitly documented: this is a client-side rendering pipeline replacement. |
| II. Explicit Over Automatic | PASS | No implicit behaviors introduced. |
| III. Role-Based Access Control | N/A | No auth/permission changes. |
| IV. Server-First File Storage | N/A | No file storage changes. |
| V. Client-Side Computation | PASS | PDF generation remains client-side as required. |
| VI. Audit Everything | N/A | No new auditable actions — export is already user-initiated. |
| VII. Simplicity & YAGNI | PASS | Hybrid approach is simplest viable solution. No unnecessary abstractions. |

**Technology Constraints check:**
- Constitution states: "PDF (client): `pdf` Flutter package with four theme variants." The `pdf` package is retained; `htmltopdfwidgets` builds on it. This is an extension, not a replacement of the underlying technology.
- Constitution states: "PWA URL handling MUST use `openInNewTab()` from `download_helper_web.dart`." The payment certificate export uses `Printing.sharePdf()` (not URL navigation), which is already proven on iOS PWA. No change needed.

## Project Structure

### Documentation (this feature)

```text
specs/002-use-html-css/
├── plan.md              # This file
├── research.md          # Phase 0 output - HTML-to-PDF approach research
├── data-model.md        # Phase 1 output - entity documentation
├── quickstart.md        # Phase 1 output - developer guide
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
frontend/
├── assets/
│   ├── fonts/
│   │   ├── calibri.ttf          # Existing
│   │   └── calibrib.ttf         # Existing
│   └── templates/
│       └── payment_certificate.html  # NEW — HTML/CSS template
├── lib/
│   ├── models/
│   │   └── payment_certificate.dart  # UNCHANGED
│   ├── services/
│   │   └── pdf/
│   │       └── payment_certificate_pdf_service.dart  # REWRITTEN
│   └── screens/
│       └── payment_certificate/
│           └── add_payment_certificate_screen.dart  # UNCHANGED
└── pubspec.yaml  # MODIFIED — add htmltopdfwidgets dep + template asset
```

**Structure Decision**: No new directories beyond `frontend/assets/templates/`. The service file is rewritten in-place. Single-project structure (frontend only).

## Implementation Design

### Phase 1: Template Creation

Create `frontend/assets/templates/payment_certificate.html` containing:

1. **`<style>` block** with:
   - `@font-face` declarations for Calibri regular and bold (base64-encoded TTF data)
   - A4 page sizing via `@page { size: A4; margin: 30px; }`
   - RTL direction: `body { direction: rtl; font-family: Calibri; font-size: 11px; }`
   - Table styles matching current color scheme (#DCE6F1 headers, #FDE9D9 totals)
   - Signature block layout

2. **HTML body** with placeholder tokens (`{{fieldName}}`) for:
   - Title block (certificate number, extension label, extension dates)
   - Subject row (subject, contract number)
   - Invoice table (invoice number, amount, currency, period dates)
   - Contract info table (executing/supervising entity, values, durations, dates)
   - Extension rows (conditionally included by Dart logic before conversion)
   - Attachments list (dynamically built by Dart logic)
   - Signature blocks (dept head, controller, director, auditor)

3. **NOT in the template**: The payment table — built programmatically with `pdf` widgets.

### Phase 2: Service Rewrite

Rewrite `PaymentCertificatePdfService.build()` to:

1. Load HTML template from assets (`rootBundle.loadString`)
2. Load Calibri font TTF bytes, base64-encode them, inject into template's `@font-face` `src: url(data:font/ttf;base64,...)` placeholders
3. Replace `{{placeholder}}` tokens with certificate data values
4. Build conditional sections in Dart:
   - Extension rows: if dates exist, inject extension HTML rows; otherwise remove placeholder
   - Attachment rows: loop and build HTML `<tr>` elements
5. Convert populated HTML → `pw.Widget` list using `htmltopdfwidgets`
6. Build payment table using direct `pdf` widgets (migrate existing `_buildPaymentTable` logic)
7. Compose into `pw.Document` with `pw.MultiPage`:
   - HTML-derived widgets for sections 1-4, 6-7 (title, subject, invoice, contract, attachments, signatures)
   - Direct `pdf` widgets for section 5 (payment table)
8. Return `pdf.save()` as `Uint8List`

### Phase 3: Dependency & Asset Registration

1. Add `htmltopdfwidgets` to `pubspec.yaml` dependencies
2. Register `assets/templates/payment_certificate.html` in pubspec.yaml assets
3. Run `flutter pub get`

### Phase 4: Cleanup

1. Remove unused helper methods from the old service (those replaced by HTML template sections)
2. Retain `_buildPaymentTable` and its helpers (`_fmtDate`, `_fmtNum`, `_tcell`)
3. Verify no other code references the removed methods

## Complexity Tracking

No constitution violations. No complexity justifications needed.
