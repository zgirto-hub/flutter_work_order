# Research: HTML-to-PDF Conversion in Flutter

**Feature**: 002-use-html-css | **Date**: 2026-04-02

## Key Finding

No single Flutter package can convert arbitrary HTML/CSS to PDF **client-side** on **all target platforms** (Android, iOS, iOS PWA, web) with full Arabic RTL support and HTML colspan merged headers.

## Options Evaluated

### 1. `Printing.convertHtml()` (printing package)
- **Android/iOS**: Works via native WebView rendering
- **Web/PWA**: **NOT IMPLEMENTED** — throws `UnimplementedError` (confirmed in dart_pdf issues #206, #857)
- **Verdict**: REJECTED — fails on web/iOS PWA entirely

### 2. `flutter_html_to_pdf` / `html_to_pdf`
- Uses native WebView to render HTML to PDF
- **Web/PWA**: Not supported (requires platform channels)
- **Verdict**: REJECTED — no web support

### 3. JavaScript interop (html2pdf.js / jsPDF) on web
- html2pdf.js rasterizes HTML via html2canvas → produces image-based PDF (not vector, not selectable text)
- jsPDF's `.html()` vector path has **broken Arabic rendering** (confirmed in jsPDF issues #3474, #3657)
- Would require platform-split code (JS on web, native on mobile)
- **Verdict**: REJECTED — broken Arabic, rasterized output, complex dual-path maintenance

### 4. `htmltopdfwidgets` (pure Dart)
- Parses HTML tags → converts to `pdf` package `pw.Widget` objects
- Pure Dart = works on ALL platforms (no platform channels)
- Builds on existing `pdf` package (proven RTL + Calibri support)
- **Limitation**: Supports basic HTML subset; **colspan/rowspan support is uncertain/limited**
- CSS support is minimal (basic inline styles, not full CSS)
- **Verdict**: VIABLE for simple sections; insufficient alone for complex merged-header tables

### 5. Hybrid: HTML template + `pdf` widgets for complex sections
- Use HTML template for overall structure and simple sections (title, subject, contract info, attachments, signatures)
- Build complex payment table (with colspan merged headers) using `pdf` package widgets directly
- Template loaded from asset, populated with data via string replacement
- `htmltopdfwidgets` converts simple HTML sections → `pw.Widget`
- Complex sections built programmatically as today
- **Verdict**: RECOMMENDED

## Decision: Hybrid Approach

- **Chosen**: HTML template asset for structure + `htmltopdfwidgets` for simple sections + direct `pdf` widgets for payment table
- **Rationale**: Only approach that works on all platforms, produces vector PDF, supports Arabic RTL with Calibri, and handles colspan merged headers
- **Alternatives rejected**: All pure-HTML approaches fail on either web platform support, Arabic rendering, or complex table features
- **Spec impact**: FR-013 and FR-014 need adjustment — the template is HTML-based but complex table sections remain in Dart code. The HTML template is still the primary layout source and is stored as a separate asset.

## Dependency Addition

- `htmltopdfwidgets` — pure Dart HTML-to-pdf-widget converter (builds on existing `pdf` dependency)
- No other new dependencies required
