# Research: Civil Aviation Letter Generator

**Feature**: 026-civil-aviation-letter-gen  
**Date**: 2026-04-06

## Decision Log

### 1. PDF Generation Approach

**Decision**: Use ReportLab server-side (matching existing `reports.py` pattern)

**Rationale**: The project already has ReportLab with `arabic_reshaper` + `python-bidi` in `requirements.txt`. The existing `reports.py` demonstrates logo embedding, Arabic text handling, and StreamingResponse delivery. Reusing this pattern avoids adding new dependencies.

**Alternatives considered**:
- WeasyPrint (mentioned in original spec) — NOT used in this project; would add a heavy dependency with system-level requirements (Cairo, Pango). Rejected.
- Client-side `pdf` package (used by payment certificate PDF) — Viable but does not align with spec requirement for server-side generation and on-demand regeneration from history.

### 2. Arabic Font for PDF

**Decision**: Use NotoSansArabic (Regular + Bold) for the letter PDF body. Cairo font was originally specified but NotoSansArabic is already referenced in the codebase (`reports.py` lines 36-45) with graceful fallback.

**Rationale**: NotoSansArabic is a widely-used, high-quality Arabic font. The backend code already attempts to load it from `backend/assets/`. The font files need to be added (currently missing), but the loading infrastructure is in place.

**Alternatives considered**:
- Cairo (Google Fonts) — Would require downloading and adding new font files. NotoSansArabic is equivalent quality and already partially integrated.
- Amiri — Beautiful for formal Arabic but less readable at smaller sizes. NotoSansArabic is more versatile.

### 3. Payment Certificate Linkage

**Decision**: Add `letter_id` nullable FK column to `payment_certificates` table, referencing `generated_letters.id`.

**Rationale**: The letter is the parent (cover letter); payment certificates are children. Adding a FK to `payment_certificates` is the simplest relational approach — no junction table needed since a payment certificate belongs to at most one letter.

**Alternatives considered**:
- Junction table — Overkill for a simple parent-child relationship.
- JSON array of certificate IDs in the letter record — Loses referential integrity; harder to query.

### 4. Preview Implementation

**Decision**: Build an HTML string client-side from form values, display in a dialog using Flutter's built-in rendering (no WebView needed). The preview is a styled container matching the PDF layout.

**Rationale**: The letter is a single page with a fixed structure. A styled Flutter widget (Container with RTL text, logo images, styled sections) provides instant preview without the overhead of WebView or HTML rendering. This matches the existing project pattern of keeping things simple.

**Alternatives considered**:
- WebView with HTML template — Adds `webview_flutter` dependency; complex for a single-page preview.
- Generate PDF and show with `printing` package preview — Too slow for live preview; user wants to see changes instantly.

### 5. History Tab Pattern

**Decision**: Use custom tab widget with state-based switching (matching `add_work_order.dart` pattern).

**Rationale**: The project uses a custom `_Tab` widget pattern (not Material TabBar) in `add_work_order.dart`. Consistency with existing codebase is preferred.

### 6. Signature Storage

**Decision**: Store signature as base64 string in the `generated_letters` Supabase record.

**Rationale**: The project already stores signatures as base64 in `work_order_signatures.signature_data`. This is consistent and allows on-demand PDF regeneration without needing to resolve file paths.

### 7. Activity Logging

**Decision**: Log letter creation and regeneration to `user_activity_log` with category `letter` and actions `created`, `regenerated`.

**Rationale**: Constitution Principle VI (Audit Everything) requires all user-facing actions to produce activity log entries. Use existing `backend/utils/activity.py` fire-and-forget pattern.
