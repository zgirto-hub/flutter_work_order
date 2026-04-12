# flutter_work_order Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-04-12

## Active Technologies
- Dart 3.x / Flutter 3.x + `pdf` ^3.10.7 (existing), `printing` ^5.12.0 (existing), `htmltopdfwidgets` (NEW) (002-use-html-css)
- Python 3 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client (backend); http, Flutter Material (frontend) (006-edit-resolve-date)
- Supabase (PostgreSQL) — `system_status_reports` table (006-edit-resolve-date)
- Dart 3.x / Flutter 3.x + Flutter Material, GoogleFonts, app_theme.dart (centralized theme) (007-increase-font-size)
- N/A (no data changes) (007-increase-font-size)
- Dart 3.x / Flutter 3.x + Flutter Material, GoogleFonts, app_theme.dart (centralized theme), ThemeController (007-increase-font-size)
- SharedPreferences (already used by ThemeController for fontScale persistence) (007-increase-font-size)
- Dart 3.x / Flutter 3.x + Flutter Material, MediaQuery.textScaler (008-fix-status-font-scale)
- Dart 3.x / Flutter 3.x (frontend), Bash (deploy scripts), Nginx (server config) + Flutter Web (canvaskit renderer), OneSignal SDK, Supabase, Nginx (009-optimize-pwa-launch)
- N/A (no data model changes) (009-optimize-pwa-launch)
- Python 3 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI (backend), Supabase Python client, Flutter Material, http package (010-fix-wo-disappear-refresh)
- Supabase (PostgreSQL) — `work_orders`, `users` tables (010-fix-wo-disappear-refresh)
- Dart 3.x / Flutter 3.x + Flutter Material (BottomSheet, AlertDialog), existing WorkOrderService, StatusBadge widget (012-quick-status-update)
- N/A (uses existing Supabase endpoints via WorkOrderService) (012-quick-status-update)
- Python 3 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client (backend); http, signature, supabase_flutter, file_picker (frontend) (014-signature-workflow)
- Supabase (PostgreSQL) — `work_order_signatures`, `users.signature_path` columns; `backend/uploaded_files/` for signature PNG files served at `/files/<filename>` (014-signature-workflow)
- Python 3 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client, reportlab (backend — NEW dependency); http, Flutter Material (frontend) (015-export-wo-pdf)
- Supabase (PostgreSQL) — existing `work_orders`, `work_order_signatures`, `users`, `departments` tables; server filesystem for signature/logo PNGs (015-export-wo-pdf)
- Python 3 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client (backend); http, supabase_flutter, Flutter Material (frontend) (016-signature-approval-chain)
- Supabase (PostgreSQL) — `users`, `work_orders`, `work_order_signatures`, `work_order_assignments`, `technician_departments` tables (016-signature-approval-chain)
- Dart 3.x / Flutter 3.x (frontend), Bash (deploy script), JavaScript (index.html inline) + `dart:js_interop` (web interop), Flutter Material (017-pwa-version-update)
- N/A (in-memory releaseId comparison only) (017-pwa-version-update)
- Python 3 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client (backend); http, supabase_flutter, Flutter Material (frontend) (019-admin-edit-wo-fields)
- Supabase (PostgreSQL) — existing `work_orders`, `users` tables (019-admin-edit-wo-fields)
- Python 3 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, httpx (backend — already in requirements.txt at v0.28.1); http package (frontend — already used) (020-ai-wo-description)
- N/A — no persistent data; request/response only (020-ai-wo-description)
- Dart 3.x / Flutter 3.x (frontend only) + `speech_to_text` (NEW — Flutter package wrapping Web Speech API for PWA), Flutter Material (existing) (022-voice-work-order)
- N/A — no persistent data; voice is transcribed to text in-memory (022-voice-work-order)
- Python 3 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, httpx, Supabase Python client (backend); http, Flutter Material (frontend) (023-nl-search-work-orders)
- N/A — no persistent data; request/response only (023-nl-search-work-orders)
- Dart 3.x / Flutter 3.x (frontend only) + Flutter Material (existing), DictationButton from 022 (existing), AiAssistService from 024 (existing), WorkOrderService (existing), DepartmentService (existing), BottomSheetContainer from bottom_sheet_widgets.dart (existing) (025-dashboard-ai-wo-card)
- N/A — no persistent data; draft is in-memory only (025-dashboard-ai-wo-card)
- Python 3 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, ReportLab, arabic_reshaper, python-bidi (backend); http, supabase_flutter, file_picker, Flutter Material (frontend) (026-civil-aviation-letter-gen)
- Supabase (PostgreSQL) — new `generated_letters` table; `payment_certificates` table gains `letter_id` FK (026-civil-aviation-letter-gen)
- Python 3 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, httpx (backend); http, Flutter Material (frontend) (027-ai-document-expert)
- Python 3 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client, reportlab, **pypdf (NEW)** (backend); http, supabase_flutter, Flutter `pdf`, existing `PaymentCertificatePdfService` (frontend) (029-link-cert-letter)
- Supabase (PostgreSQL) — existing `generated_letters`, `payment_certificates` (`letter_id` FK already present; add `letter_link_order int` column for ordering) (029-link-cert-letter)
- Dart 3.x / Flutter 3.x + Flutter Material (existing), `AiInsightsCard` (existing), `NlInputCard` (existing) (030-collapsible-ai-cards)
- N/A — UI state only, in-memory, not persisted (030-collapsible-ai-cards)
- Python 3.10 (backend) + FastAPI, Jinja2, WeasyPrint, Pillow (existing); `python-barcode==0.15.1` (NEW) (032-letter-barcode)
- N/A (no DB or filesystem changes — barcode is in-memory PNG → base64 data URI) (032-letter-barcode)
- Dart 3.x / Flutter 3.x (embedded HTML5 / JS ES5 inside string constant) + Flutter Material (existing), browser-native `document.execCommand`, `Range`, `TreeWalker`, CSS `zoom` (033-gdocs-editor-toolbar)
- N/A — all state lives in editor DOM; persists as inline HTML via existing letters_v2 save pipeline (033-gdocs-editor-toolbar)
- Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Pillow 12.1.1 (backend); http, file_picker, Flutter Material (frontend) (034-editor-image-insert)
- Server filesystem `backend/uploaded_files/letters/` — no database changes (034-editor-image-insert)
- Dart 3.x / Flutter 3.x + Flutter Material, AppColors/AppShadows/AppTheme (centralized theme), shared widgets from `claude_widgets.dart` (EmptyState, SectionLabel) (035-letters-v2-ui-refactor)
- Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI (backend), Flutter Material (frontend) — no new dependencies (036-cleanup-dead-letters-v1)
- N/A — no data model changes (036-cleanup-dead-letters-v1)
- Dart 3.x / Flutter 3.x (frontend only, primarily web target); Python 3.10 + FastAPI (backend, minimal touch for audit endpoint) + `package:web` (existing — JS interop for `navigator.share`, `navigator.canShare`, `Blob`, `File`, anchor download), `package:printing` (existing — already used for `PdfPreview`; its `allowPrinting`/`allowSharing`/`actions` params control the built-in toolbar), `package:http` (existing — activity log POST), existing `download_helper_web.dart` to be extended (038-ios-pwa-share)
- N/A — PDF bytes are transient (built → shared/downloaded → released). No database changes. No new file storage. (038-ios-pwa-share)
- Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend, primarily web target via PWA) (040-manual-rag-assistant)
- Dart 3.x / Flutter 3.x + Flutter Material, existing shared widgets (ClaudeFAB, EmptyState, ValidatedTextField, SectionLabel from `claude_widgets.dart`), existing DocumentRegistryService, existing RegistryEntry model (041-registry-v2-refactor)
- N/A — no data model or backend changes (041-registry-v2-refactor)

- Dart 3.x / Flutter 3.x + Flutter Material, fl_chart, supabase_flutter, app_theme (001-status-cards-redesign)
- Python 3 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client, httpx (backend); http, Flutter Material (frontend) (021-ai-analytics-insights)
- N/A — no persistent data; request/response only (021-ai-analytics-insights)

## Project Structure

```text
backend/
frontend/
tests/
```

## Commands

# Add commands for Dart 3.x / Flutter 3.x

## Code Style

Dart 3.x / Flutter 3.x: Follow standard conventions

## Recent Changes
- 041-registry-v2-refactor: Added Dart 3.x / Flutter 3.x + Flutter Material, existing shared widgets (ClaudeFAB, EmptyState, ValidatedTextField, SectionLabel from `claude_widgets.dart`), existing DocumentRegistryService, existing RegistryEntry model
- 040-manual-rag-assistant: Added Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend, primarily web target via PWA)
- 038-ios-pwa-share: Added Dart 3.x / Flutter 3.x (frontend only, primarily web target); Python 3.10 + FastAPI (backend, minimal touch for audit endpoint) + `package:web` (existing — JS interop for `navigator.share`, `navigator.canShare`, `Blob`, `File`, anchor download), `package:printing` (existing — already used for `PdfPreview`; its `allowPrinting`/`allowSharing`/`actions` params control the built-in toolbar), `package:http` (existing — activity log POST), existing `download_helper_web.dart` to be extended


<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
