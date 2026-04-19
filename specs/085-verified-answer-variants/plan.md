# Implementation Plan: Verified Answer Variants

**Branch**: `085-verified-answer-variants` | **Date**: 2026-04-18 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/085-verified-answer-variants/spec.md`

## Summary

Add a "Generate variants" action to the Verified Answers admin tab so an admin can broaden the semantic matching of a curated answer by managing the set of question phrasings (variants) linked to that answer. The flow reuses the existing `variants_modal.dart` UI, the existing `POST /manuals/paraphrase-variants` AI paraphrase endpoint, and the shared-`rating_id` grouping introduced in spec 068. Two new backend endpoints reconcile a submitted variant list against the stored set using full-replace, text-based matching; embedding failures abort the save atomically.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend — primarily web/PWA)
**Primary Dependencies**: FastAPI, Supabase Python client, existing `services.validated_qa_service`, existing `services.ollama_embedder` (backend); Flutter Material, existing `variants_modal.dart`, existing `manual_assistant_service.askParaphraseVariants` (frontend). **No new dependencies.**
**Storage**: Supabase (PostgreSQL + pgvector) — existing `validated_qa` table. **No schema changes, no migration.** Shared-`rating_id` design already present from spec 068; legacy rows with `rating_id IS NULL` get a synthetic UUID assigned on first save.
**Testing**: pytest (backend, alongside existing `test_paraphrase_generation.py` and `test_validated_qa_lookup.py`); manual quickstart flow for the Flutter UI (no widget test infra is in active use for this tab).
**Target Platform**: Linux backend (FastAPI on Uvicorn behind Nginx); Flutter web PWA on modern browsers.
**Project Type**: web (FastAPI backend + Flutter frontend) — Option 2 structure.
**Performance Goals**: Modal opens within 5 s of clicking "Generate variants" at p95 (SC-002). Save reconcile completes within 10 s at p95 for up to 10 variants (embedding-bound).
**Constraints**: Atomic save: embedding failure on any variant aborts the whole operation (FR-008a). Max 500 chars/variant (FR-011). Reconcile uses trimmed, case-insensitive text matching (FR-006 after clarification). Existing admin-only gating on the Verified Answers tab is the only access control.
**Scale/Scope**: Low-frequency admin operation; typical group size 1–10 variants; rarely >20. Expected concurrent admins editing the same entry: effectively 0 in the target deployment.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance | Notes |
|---|---|---|
| I. Full-Stack Ownership | ✅ Pass | Backend: 2 new endpoints + reconcile service function. Frontend: new button in Edit dialog, new service methods, modal extension. No migration needed (no schema change). Docs updated via `update-agent-context`. |
| II. Explicit Over Automatic | ✅ Pass | Variants are only generated on explicit admin click; save only happens on explicit "Save all". Legacy `rating_id = NULL` backfill is explicit and documented (assigned on first save from this flow). No silent fallback — paraphrase failure shows a notice banner. |
| III. Role-Based Access Control | ✅ Pass | Existing admin-only gating on the Verified Answers tab covers this feature; no new permission surface. Backend endpoints reuse the same `user_email` gating pattern already in place for `PUT/DELETE /manuals/verified-answers/{qa_id}`. |
| IV. Server-First File Storage | N/A | No files touched. |
| V. Client-Side Computation Where Possible | N/A | Reconcile must live on the server (owns DB + embeddings). Client-side only prepares the variant list. |
| VI. Audit Everything | ✅ Pass | FR-015 mandates an activity-log entry for every save. Action: `updated_verified_answer_variants`, category `admin`, target_id `qa_id`, detail `added=X, updated=Y, removed=Z`. Fire-and-forget via `backend.utils.activity.log_activity`. |
| VII. Simplicity & YAGNI | ✅ Pass | Reuses `variants_modal.dart`, `POST /manuals/paraphrase-variants`, `services.validated_qa_service` shared-rating grouping. No new abstractions; 2 endpoints + 1 button + 2 service methods. No concurrent-edit locking (deferred per clarification). |

**No violations.** Complexity Tracking section omitted.

## Project Structure

### Documentation (this feature)

```text
specs/085-verified-answer-variants/
├── plan.md              # This file
├── spec.md              # Feature spec (already written)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── get-variants.md
│   └── put-variants.md
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit.specify)
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── manuals.py                         # Add: GET/PUT /manuals/verified-answers/{qa_id}/variants
├── services/
│   └── validated_qa_service.py            # Add: get_variants_group(qa_id), reconcile_variants(qa_id, texts, editor_email)
└── tests/
    └── test_verified_answer_variants.py   # New: unit + integration coverage for reconcile logic

frontend/
└── lib/
    ├── screens/manual_assistant/
    │   ├── verified_answers_tab.dart      # Add: "Generate variants" button in _showEditDialog, handler, reload-on-save
    │   └── widgets/
    │       └── variants_modal.dart        # Extend: new optional `savedVariantTexts` set + visual marker on saved chips
    └── services/
        └── manual_assistant_service.dart  # Add: getVerifiedAnswerVariants(qaId), updateVerifiedAnswerVariants(qaId, variants, editorEmail)
```

**Structure Decision**: Web application (backend + frontend). No new top-level directories. All changes slot into existing files alongside the spec-068 shared-rating infrastructure.

## Complexity Tracking

N/A — no constitutional violations.
