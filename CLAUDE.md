# flutter_work_order Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-04-17

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
- Python 3.10 (backend only) + FastAPI, httpx, Supabase Python client (all existing) (042-rag-query-rewrite)
- N/A — no persistent data changes (042-rag-query-rewrite)
- Python 3.10 (backend only) + FastAPI, httpx, Supabase Python client, Ollama (gemma4:e2b for generation, nomic-embed-text for embedding) — all existing (043-hyde-retrieval)
- N/A — no data model changes; hypothetical answer is transient/in-memory (043-hyde-retrieval)
- Python 3.10 + FastAPI, Supabase Python client, httpx (all existing) (044-chunk-rerank-scoring)
- Supabase (PostgreSQL) with pgvector — no schema changes (044-chunk-rerank-scoring)
- Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, httpx, Ollama (gemma4:e2b) (backend); http package, Flutter Material (frontend) (045-rolling-session-summary)
- N/A — no persistent data; summary is transient/in-memory per request (045-rolling-session-summary)
- Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, httpx, Supabase Python client (backend); http, Flutter Material (frontend) (046-cross-manual-synthesis)
- Supabase (PostgreSQL) — existing `work_orders`, `users`, `departments` tables; pgvector for manual chunks (047-agentic-tool-use)
- Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, httpx, Supabase Python client, ollama_embedder (backend); http, Flutter Material (frontend) (048-feedback-loop-ai-assistant)
- Supabase (PostgreSQL) with pgvector — new `answer_ratings` and `validated_qa` tables; existing `work_orders`, `users`, `manual_chunks` tables (048-feedback-loop-ai-assistant)
- Python 3.10 + FastAPI, httpx, Supabase Python client, existing `ollama_generator.py` (049-wo-entity-extraction)
- Supabase (PostgreSQL) with pgvector — new `work_order_entities` and `extraction_failures` tables (049-wo-entity-extraction)
- Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client (backend); http, supabase_flutter, Flutter Material (frontend) (051-pattern-rules-engine)
- Supabase (PostgreSQL) — new `pattern_rules` and `pattern_alerts` tables; existing `work_order_entities`, `work_orders` tables (051-pattern-rules-engine)
- Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, httpx, Supabase Python client (backend); http, supabase_flutter, Flutter Material (frontend) (052-extraction-toggle-queue)
- Supabase (PostgreSQL) — new `system_settings` table (052-extraction-toggle-queue)
- Supabase (PostgreSQL) — new `assets` and `asset_system_links` tables (053-asset-registry)
- Supabase (PostgreSQL) — existing `work_orders` table, existing `assets` table; no schema changes (054-structured-wo-description)
- Supabase (PostgreSQL) — existing `pattern_alerts`, `assets`, `work_order_entities`, `system_settings` tables. No new tables. (055-asset-auto-suggest)
- Supabase (PostgreSQL) — new `systems` table; modified `asset_system_links`, `system_status_reports` (056-shared-systems-table)
- [e.g., Python 3.11, Swift 5.9, Rust 1.75 or NEEDS CLARIFICATION] + [e.g., FastAPI, UIKit, LLVM or NEEDS CLARIFICATION] (main)
- [if applicable, e.g., PostgreSQL, CoreData, files or N/A] (main)
- Supabase (PostgreSQL) — existing `validated_qa` table; one migration to make `rating_id` nullable (059-add-verified-answer)
- Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client (backend); `http`, `supabase_flutter`, Flutter Material (frontend) (061-infrastructure-screen)
- Supabase (PostgreSQL) — existing `systems`, `assets`, `asset_system_links`, `system_status_reports` tables; no new tables (061-infrastructure-screen)
- Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client, httpx, existing `ollama_embedder`/`ollama_generator` (backend); Flutter Material, existing answer-card widgets (frontend). **No new dependencies.** (062-hybrid-retrieval-filter)
- Supabase (PostgreSQL) — existing `manuals`, `manual_chunks` tables. No schema changes. No migrations. (062-hybrid-retrieval-filter)
- Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client, httpx (existing); `google-generativeai` (NEW — backend only, for Gemini SDK). Flutter Material + `supabase_flutter` + `http` (existing). (063-ai-provider-manager)
- Supabase (PostgreSQL) — new `app_settings` key-value table (2 rows in phase 1). No pgvector changes. Existing `user_activity_log` reused for fallback audit events. (063-ai-provider-manager)
- Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client, httpx, existing `ollama_embedder`/`ollama_generator`/`ai_providers` (backend); Flutter Material, existing answer-card widgets and `manual_assistant_service.dart` (frontend). **No new dependencies.** (066-stage-latency-breakdown)
- None — `latency_breakdown` is transient per-response only (FR-010). No Supabase schema changes, no migration, no `user_activity_log` writes. (066-stage-latency-breakdown)
- Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client, httpx (backend, existing); `services.ai_providers.resolver` (spec 063, existing); `services.ollama_embedder` (existing); `services.validated_qa_service` (existing). Flutter Material, `http`, shared widgets from `frontend/lib/widgets/bottom_sheet_widgets.dart` (existing). (068-auto-paraphrase-approve)
- Supabase (PostgreSQL + pgvector). Existing `validated_qa`, `answer_ratings` tables. No migrations. `rating_id` is already nullable (migration `20260415000000`) and has **no unique constraint** — multiple `validated_qa` rows can share the same `rating_id`, which is exactly the shared-rating design this spec needs. (068-auto-paraphrase-approve)
- Python 3.10 (backend only) + FastAPI, Supabase Python client, httpx, existing `services.ai_providers.resolver`, existing `services.ollama_embedder`, existing `services.validated_qa_service` (069-rag-quality-improvements)
- Supabase (PostgreSQL) with pgvector — existing `validated_qa` table. No schema changes. (069-rag-quality-improvements)
- Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, Supabase Python client, google-generativeai (existing), httpx (backend); http, Flutter Material (frontend) (073-smart-doc-preprocess)
- Supabase (PostgreSQL) with pgvector — `knowledge_documents`, `document_chunks`, `manual_chunks`, `app_settings` tables (073-smart-doc-preprocess)
- Python 3.10 (backend only — no Flutter/Dart changes this spec) + FastAPI, Supabase Python client, httpx, `google-generativeai` (all existing from spec 063), existing `services.ai_providers.resolver`, `services.ollama_generator` (076-gemini-default-generation)
- Supabase (PostgreSQL) — existing `app_settings` table (row `key='ai_provider'`) and existing `user_activity_log` table. No schema changes. Existing seed migration `20260415_app_settings.sql` edited in place to change the seed value; no new migration file is added. (076-gemini-default-generation)
- Python 3.10 (backend only — no Flutter/Dart changes) + FastAPI, Supabase Python client, httpx, existing `services.ollama_embedder`, existing `services.document_service`, existing `services.manual_rag_service` (075-contextual-embeddings)
- Supabase (PostgreSQL) with pgvector — existing `document_chunks`, `manual_chunks`, `knowledge_documents`, `manuals` tables. No schema changes. (075-contextual-embeddings)
- Python 3.10 (backend only — no Flutter/Dart changes) + FastAPI, existing `services.ollama_generator`, existing `services.ollama_embedder`, existing `services.ai_providers.resolver` (077-rag-pipeline-parallelize)

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
- 077-rag-pipeline-parallelize: Added Python 3.10 (backend only — no Flutter/Dart changes) + FastAPI, existing `services.ollama_generator`, existing `services.ollama_embedder`, existing `services.ai_providers.resolver`
- 075-contextual-embeddings: Added Python 3.10 (backend only — no Flutter/Dart changes) + FastAPI, Supabase Python client, httpx, existing `services.ollama_embedder`, existing `services.document_service`, existing `services.manual_rag_service`
- 076-gemini-default-generation: Added Python 3.10 (backend only — no Flutter/Dart changes this spec) + FastAPI, Supabase Python client, httpx, `google-generativeai` (all existing from spec 063), existing `services.ai_providers.resolver`, `services.ollama_generator`


<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
