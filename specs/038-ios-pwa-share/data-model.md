# Phase 1 Data Model — iOS PWA Native Share for Letters & Work Order PDFs

**Feature**: 038-ios-pwa-share
**Date**: 2026-04-11

This feature introduces **no persistent data model changes** — no Supabase migration, no new tables, no new columns. The two entities below are transient, client-side runtime artefacts only. A single pre-existing table (`user_activity_log`) gains new rows of a type that is already supported by its schema.

---

## Transient (in-memory) entities

### ShareableDocument

A one-shot artefact constructed at the moment the user taps the share button and released as soon as the share sheet closes (or the fallback download completes).

| Field | Type | Required | Source | Notes |
|-------|------|----------|--------|-------|
| `bytes` | `Uint8List` | yes | Returned by the caller's `onShare` / cached `buildPdf()` | The PDF payload. Not persisted. |
| `fileName` | `String` (ASCII-safe) | yes | Built by the caller | Letters: `letter_${id.substring(0, 8)}.pdf` (history) or `letter_${millis}.pdf` (form). Work orders: `WO-${jobNo}.pdf`. No UTF-8 in filename per research decision 8. |
| `title` | `String` (UTF-8) | yes | Built by the caller | Human-readable title shown in the share sheet source label (may contain Arabic, e.g., the letter `almawdoo` subject). |
| `mimeType` | `String` | implicit | `'application/pdf'` | Not passed around as a separate field — derived from filename extension by the share helper (existing `_mimeFromName` in `download_helper_web.dart` already handles this). |

**Lifecycle**: Constructed in the `onShare` callback handler → passed to `sharePdfBytes(bytes, fileName, title)` → wrapped in `Blob` → wrapped in `File` → assigned to `shareData.files` → handed to `navigator.share()` (or the anchor-download fallback) → released when the promise settles.

**Validation rules**:
- `bytes` MUST be non-empty. An empty PDF is a failure (show error, do not invoke share sheet).
- `fileName` MUST end in `.pdf`. Enforced by `sharePdfBytes` at the top of the function (prepend `.pdf` if missing — defensive).
- `title` MAY be empty. If empty, the share sheet falls back to just the filename for its source label — acceptable.

**Not modelled as a Dart class**: the three fields are passed as positional/named arguments to `sharePdfBytes`. Creating a `ShareableDocument` class for three parameters would violate Principle VII (Simplicity). This table documents the conceptual shape for the spec-to-code reviewer, not a code artefact.

---

### ShareCapability

A runtime determination of whether the current browser/device should see the native share control or the legacy "Open in new tab" / full `printing` toolbar.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| `canUseNativeShareControl` | `bool` | `share_capability_web.dart` → UA-sniff for iOS/Android mobile | `true` only on iOS Safari (any, standalone or tab) and Android Chrome. `false` on all desktop browsers including macOS Safari. No raw `canShare({files})` check (per Q1 clarification). |

**Lifecycle**: Computed once per screen build (not cached across screens — cheap enough to recompute). Conditional-imported via `share_capability.dart` façade so the same call compiles on native and web targets.

**Not modelled as a class**: one boolean — exposed as a top-level function `bool canUseNativeShareControl()` in the `share_capability_*.dart` files. No state, no configuration.

---

## Persistent state: audit log row

The only persistent side-effect of a share action is **one row** inserted into the pre-existing `user_activity_log` table (Supabase PostgreSQL). This table's schema is already established by the existing activity log feature — no migration is required.

**Shape of the inserted row** (illustrative — actual column set is whatever `backend/utils/activity.py` already writes):

| Column | Value on share |
|--------|----------------|
| `id` | auto (UUID) |
| `user_email` | Supabase auth current user email |
| `category` | `'work_order'` or `'file'` (new category TBD at implementation — `'work_order'` for WO share, `'file'` for letter share since letters are in the Files/Letters area conceptually; confirm at task time by inspecting how existing letter actions categorise themselves in `backend/utils/activity.py`) |
| `action` | `'shared'` |
| `target_type` | `'letter'` or `'work_order'` (free-form string) |
| `target_id` | letter id or work order id |
| `created_at` | now (UTC) |

**Semantics**: one row = one **share intent** (the moment the user tapped the share button). We do NOT try to observe share completion (unreliable across platforms per research decision 7). If the fire-and-forget `POST /activity-log/shared` fails (network, server down), the share action still proceeds — the audit write MUST NOT block the primary user action, per Principle VI.

**No new columns, no new indexes, no new RLS policies**: the existing `user_activity_log` infrastructure handles this.

---

## Why there is no `data-model.md` diagram

This feature has:
- 0 new database tables
- 0 new columns
- 0 new Flutter models
- 0 new serializable entities
- 2 transient in-memory value bundles (documented above, neither warranting a class)
- 1 new row type in 1 pre-existing table

A data-model diagram would be three boxes with no edges. The table form above is the complete picture.
