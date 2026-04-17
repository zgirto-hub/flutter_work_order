# Tasks: Train the AI Tab — 3-Stage Learning Pipeline

**Input**: Design documents from `/specs/080-train-ai-tab/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api-endpoints.md

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks grouped by user story for independent implementation.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1, US2, US3)
- Exact file paths included in every task

---

## Phase 1: Setup

**Purpose**: Database migration and shared service changes needed by all stories

- [ ] T001 Create migration `supabase/migrations/20260418000000_train_ai_staleness.sql` — ALTER `validated_qa` to add `verified_at TIMESTAMPTZ DEFAULT now()` and `source_manual_id UUID REFERENCES manuals(id) ON DELETE SET NULL`; backfill `verified_at = created_at` where NULL; add partial index `idx_validated_qa_source_manual` on `source_manual_id WHERE source_manual_id IS NOT NULL`; ALTER `manuals` to add `updated_at TIMESTAMPTZ DEFAULT now()`; backfill `updated_at = created_at` where NULL. See `specs/080-train-ai-tab/data-model.md` for exact SQL.

- [ ] T002 Extend `validated_qa_service.create_verified_answer()` in `backend/services/validated_qa_service.py` — add optional `source_manual_id: str = None` parameter. When provided, include `source_manual_id` in the inserted `validated_qa` row. Do NOT change existing callers — the param defaults to None so existing calls are unaffected. Also set `verified_at = now()` on insert (already handled by DB default).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared endpoint changes and tab skeleton that ALL stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [ ] T003 [P] Extend `POST /manuals/paraphrase-variants` in `backend/routers/manuals.py` — add optional `lang: str = "en"` field to `ParaphraseVariantsRequest` model. When `lang="ar"`, use Arabic-specific prompt: `"Translate this question to Arabic, then generate 3 natural Arabic paraphrase variants a maintenance technician might use. The variants must sound natural in Arabic, not like direct translations. Return JSON only — no preamble, no markdown: {\"variants\": [\"...\", \"...\", \"...\"]}\nQuestion: {q}"`. When `lang="en"`, existing behavior is unchanged (uses `PARAPHRASE_PROMPT_TEMPLATE`). See `specs/080-train-ai-tab/contracts/api-endpoints.md`.

- [ ] T004 [P] Extend `generateParaphraseVariants()` in `frontend/lib/services/manual_assistant_service.dart` — add optional `String lang = 'en'` parameter. Pass `'lang': lang` in the JSON body alongside `question_text` and `rating_id`. Default `'en'` preserves existing behavior.

- [ ] T005 [P] Extend `POST /manuals/verified-answers` request model (`CreateVerifiedAnswerRequest`) in `backend/routers/manuals.py` — add optional `source_manual_id: Optional[str] = None` field. Pass it through to `validated_qa_service.create_verified_answer()`. Do NOT change the endpoint's response or error handling.

- [ ] T006 Add "Train the AI" tab to `frontend/lib/screens/manual_assistant/manual_assistant_screen.dart` — increase admin tab count from 6 to 7. Add the new tab at index 6 (after Documents). Tab label: "Train AI". Import and render `TrainAiTab` in the TabBarView. Guard with existing `if (_isAdmin)` pattern. Follow the exact pattern used for other admin tabs (Review, Rules, Alerts, Verified, Documents).

- [ ] T007 Create `frontend/lib/screens/manual_assistant/train_ai_tab.dart` — skeleton widget with `SegmentedButton` navigation for 3 sections: "From Manuals" (index 0), "From Real Usage" (index 1), "Needs Review" (index 2). Use `StatefulWidget`. Accept `ManualAssistantService` and `userEmail` as constructor params. The SegmentedButton controls which section body is displayed below it. "Needs Review" segment should show a `Badge` with stale count when > 0 (fetch count on init and expose refresh). Each section body will be populated in US1/US2/US3 tasks — for now use `Center(child: Text('Section A/B/C'))` placeholders. Support RTL layout.

**Checkpoint**: Foundation ready — Tab visible for admin, 3-segment navigation works, paraphrase supports Arabic, verified-answers accepts source_manual_id.

---

## Phase 3: User Story 1 — Bootstrap Cache from Manuals (Priority: P1) MVP

**Goal**: Admin selects a manual, generates Q&A candidates, reviews/edits, and saves approved pairs to cache with EN+AR paraphrase variants.

**Independent Test**: Select a processed manual → Generate → Approve 1+ → Save All Approved → Verify entries appear in Verified Answers tab with correct variant count.

### Implementation for User Story 1

- [ ] T008 [P] [US1] Create `POST /manuals/generate-qa-candidates` endpoint in `backend/routers/manuals.py` — Admin-only via `_admin_check(user_email)`. Request model: `GenerateQACandidatesRequest` with `manual_id: str` and `max_candidates: int = 20`. Logic: (1) fetch manual by ID, return 404 if not found; (2) fetch chunks from `manual_chunks` WHERE `manual_id` matches, return 400 `no_chunks` error if empty; (3) for each chunk embedding, call `search_validated_qa` RPC with `match_count=1` and skip chunk if distance < 0.15 (cosine >= 0.85 similarity); (4) group remaining chunks in batches of 3; (5) for each batch, call `provider_generate` (import `generate` from `services.ai_providers.resolver`) with prompt from spec (generate ONE practical Q&A as JSON); (6) parse JSON response, skip on parse failure; (7) for dedup, embed each generated question via `embed_single()` and check against already-generated questions (skip if cosine >= 0.85); (8) stop at max_candidates; (9) return `{candidates: [{question, answer, source_title, source_chunk_ids}], total, skipped_cached}`. Log activity. See `specs/080-train-ai-tab/contracts/api-endpoints.md` for full contract.

- [ ] T009 [P] [US1] Add `generateQACandidates({required String manualId, int maxCandidates = 20})` method to `frontend/lib/services/manual_assistant_service.dart` — POST to `/manuals/generate-qa-candidates?user_email=...` with JSON body `{manual_id, max_candidates}`. Return parsed `List<Map<String, dynamic>>` of candidates plus `skippedCached` count. Handle errors (404 not_found, 400 no_chunks) by throwing with error code.

- [ ] T010 [P] [US1] Add `saveTrainedEntry({required String question, required String answer, required String editorEmail, String? sourceManualId})` method to `frontend/lib/services/manual_assistant_service.dart` — implements the 4-step save flow: Step 1: call existing `createVerifiedAnswer()` (add `sourceManualId` param) and capture returned `id` as `primaryQaId`; Step 2: call `generateParaphraseVariants(questionText: question, lang: 'en')` → get 4 English variants; Step 3: call `generateParaphraseVariants(questionText: question, lang: 'ar')` → get 3 Arabic variants; Step 4: call `reviewAnswerWithVariants(ratingId: '', action: 'retro_expand', existingValidatedQaId: primaryQaId, variants: [...englishVariants, ...arabicVariants])`. Return `{primaryQaId, englishCount, arabicCount, totalEmbeddings}`. Also extend `createVerifiedAnswer()` to pass optional `source_manual_id` in the request body.

- [ ] T011 [P] [US1] Create `frontend/lib/screens/manual_assistant/widgets/qa_candidate_card.dart` — `StatefulWidget` displaying a single Q&A candidate. Props: `question` (String), `answer` (String), `sourceTitle` (String), `onApprove` callback, `onReject` callback, `onEdit(String newQ, String newA)` callback. Layout: Card with green border when approved. Question as editable `TextField` (read-only by default, editable in edit mode). Answer as collapsible `TextField` showing first 3 lines with "Show more" toggle. Source label read-only. Action row with Approve (checkmark icon), Edit (pencil icon), Reject (X icon) buttons. Rejected state: trigger `AnimatedList` remove with slide animation. Follow existing card widget patterns from `widgets/review_entry_card.dart` for styling. Support RTL.

- [ ] T012 [US1] Implement "From Manuals" section body in `frontend/lib/screens/manual_assistant/train_ai_tab.dart` — replace Section A placeholder. Layout: (1) `DropdownButtonFormField` populated from `_service.listManuals()` (fetch on init); (2) "Generate Q&A Candidates" `ElevatedButton` (disabled until manual selected); (3) progress indicator during generation: `LinearProgressIndicator` + text "Generating candidates... X / 20"; (4) scrollable `ListView` of `QaCandidateCard` widgets; (5) sticky bottom bar with approved count text + "Save All Approved" `ElevatedButton` (disabled until >= 1 approved); (6) empty state: "Select a manual above to generate Q&A candidates" with icon. On "Save All Approved": iterate approved candidates, call `saveTrainedEntry()` for each, show success snackbar with counts "X Q&A pairs saved · Y embeddings created (Z English + W Arabic)". Disable button and show loading during save. Handle errors per-entry (continue on failure, report partial success). Loading states on Generate and Save.

- [ ] T013 [US1] Add session history display to "From Manuals" section in `frontend/lib/screens/manual_assistant/train_ai_tab.dart` — after each successful "Save All Approved", append an in-memory summary row below the form: "check-mark [Manual name] — X pairs saved · Y embeddings · [timestamp]". Display as a `Column` of styled `ListTile` widgets. In-memory only (`List<String>` state) — clears when leaving the tab.

**Checkpoint**: US1 complete — admin can generate, review, and save Q&A pairs from any processed manual. Verify in Verified Answers tab.

---

## Phase 4: User Story 2 — Promote Real Usage to Cache (Priority: P2)

**Goal**: Surface positively-rated technician questions not yet cached, allow admin to add them to cache with one tap.

**Independent Test**: Have 2+ positive ratings on an uncached question → open "From Real Usage" → verify it appears → "Add to Cache" → verify entry created in Verified Answers.

### Implementation for User Story 2

- [ ] T014 [P] [US2] Create `GET /manuals/real-usage-suggestions` endpoint in `backend/routers/manuals.py` — Admin-only. Logic: (1) query `answer_ratings` WHERE `rating = 'positive'`; (2) GROUP BY `question_text, answer_text`, count as `rating_count`, MAX `created_at` as `last_asked_at`; (3) filter `rating_count >= 2`; (4) for each group, embed question via `embed_single()`, call `search_validated_qa` RPC with `match_count=1`, exclude if distance < 0.20 (similarity >= 0.80); (5) order by `rating_count DESC`, limit 50; (6) return `{suggestions: [{question, answer, rating_count, last_asked_at}]}`. Log activity. See `specs/080-train-ai-tab/contracts/api-endpoints.md`.

- [ ] T015 [P] [US2] Add `getRealUsageSuggestions()` method to `frontend/lib/services/manual_assistant_service.dart` — GET to `/manuals/real-usage-suggestions?user_email=...`. Return parsed `List<Map<String, dynamic>>`.

- [ ] T016 [P] [US2] Create `frontend/lib/screens/manual_assistant/widgets/usage_suggestion_card.dart` — `StatefulWidget` displaying a usage suggestion. Props: `question` (String), `answer` (String), `ratingCount` (int), `lastAskedAt` (DateTime), `onAddToCache` callback, `onEditThenAdd(String newQ, String newA)` callback, `onDismiss` callback. Layout: Card with question text, collapsible answer (3-line preview + "Show more"), rating badge ("thumbs-up X ratings"), date ("Last asked: X days ago"), action row: "Add to Cache" (green), "Edit then Add" (pencil), "Dismiss" (X). Edit mode: inline TextFields for question and answer. Follow existing card patterns. Support RTL.

- [ ] T017 [US2] Implement "From Real Usage" section body in `frontend/lib/screens/manual_assistant/train_ai_tab.dart` — replace Section B placeholder. Layout: (1) subtitle text "Questions technicians asked that got good ratings — not yet in the cache"; (2) `RefreshIndicator` wrapping scrollable `ListView` of `UsageSuggestionCard` widgets; (3) sticky bottom bar with "Approve All" button; (4) empty state: "No suggestions yet. As technicians use the AI assistant, highly-rated answers will appear here." with icon. Fetch on section activation. "Add to Cache" calls `saveTrainedEntry()` (same 4-step flow from US1). "Dismiss" removes card from local list (in-memory only). "Approve All" shows confirmation dialog first, then processes all visible. Loading states on all actions. Pull-to-refresh reloads.

**Checkpoint**: US2 complete — real-usage suggestions appear and can be promoted to cache with variants.

---

## Phase 5: User Story 3 — Review Stale Cache Entries (Priority: P3)

**Goal**: Detect and surface cached Q&A entries whose source manual was updated, allow admin to confirm, edit, or remove them.

**Independent Test**: Re-embed a manual's chunks → open "Needs Review" → verify derived entries appear as stale → "Still Valid" → verify entry exits stale list.

### Implementation for User Story 3

- [ ] T018 [P] [US3] Create `GET /manuals/stale-cache-entries` endpoint in `backend/routers/manuals.py` — Admin-only. Query: `SELECT vq.id, vq.question_text, vq.validated_answer, m.title, m.updated_at FROM validated_qa vq JOIN manuals m ON m.id = vq.source_manual_id WHERE vq.source_manual_id IS NOT NULL AND m.updated_at > vq.verified_at`. Compute `days_since_update` as `(now() - m.updated_at).days`. Return `{stale_entries: [{qa_id, question, answer, manual_title, manual_updated_at, days_since_update}], total}`. See contracts.

- [ ] T019 [P] [US3] Create `POST /manuals/mark-cache-reviewed` endpoint in `backend/routers/manuals.py` — Admin-only. Request model: `MarkCacheReviewedRequest` with `qa_id: str`, `action: str` ("confirm" or "delete"), `updated_question: Optional[str] = None`, `updated_answer: Optional[str] = None`. For `action="confirm"`: UPDATE `validated_qa SET verified_at = now() WHERE id = qa_id`; also update variant rows sharing same `rating_id`; if `updated_question` or `updated_answer` provided, re-embed question via `embed_single()` and update `question_text`, `question_embedding`, `validated_answer` on the row. For `action="delete"`: get `rating_id` from the target row, then DELETE all `validated_qa` rows WHERE `id = qa_id OR (rating_id = target_rating_id AND rating_id IS NOT NULL)`. Return status and counts. Log activity.

- [ ] T020 [P] [US3] Verify and fix re-embed flow in `backend/routers/manuals.py` — find the existing re-embed endpoint (`/manuals/{manual_id}/chunks/re-embed`). After successful chunk re-embedding, add: `supabase.table("manuals").update({"updated_at": datetime.utcnow().isoformat()}).eq("id", manual_id).execute()`. This is the staleness trigger. Do NOT break existing re-embed behavior — only add the `updated_at` update after the existing logic succeeds.

- [ ] T021 [P] [US3] Add `getStaleCacheEntries()` and `markCacheReviewed({required String qaId, required String action, String? updatedQuestion, String? updatedAnswer})` methods to `frontend/lib/services/manual_assistant_service.dart` — `getStaleCacheEntries()`: GET to `/manuals/stale-cache-entries?user_email=...`, return parsed list. `markCacheReviewed()`: POST to `/manuals/mark-cache-reviewed?user_email=...` with JSON body, return response map.

- [ ] T022 [P] [US3] Create `frontend/lib/screens/manual_assistant/widgets/stale_entry_card.dart` — `StatefulWidget`. Props: `qaId` (String), `question` (String), `answer` (String), `manualTitle` (String), `daysSinceUpdate` (int), `onConfirm` callback, `onEditConfirm(String newQ, String newA)` callback, `onRemove` callback. Layout: Card with question (read-only), collapsible answer (read-only, 3-line preview), warning label "Source manual was updated X days ago" with warning icon, manual name. Action row: "Still Valid" (green checkmark), "Edit & Reconfirm" (pencil), "Remove from Cache" (trash, red). "Edit & Reconfirm" enters edit mode with inline TextFields. "Remove from Cache" shows confirmation dialog: "Remove this answer and all its variants from the cache? This cannot be undone." Support RTL.

- [ ] T023 [US3] Implement "Needs Review" section body in `frontend/lib/screens/manual_assistant/train_ai_tab.dart` — replace Section C placeholder. Layout: (1) scrollable `ListView` of `StaleEntryCard` widgets; (2) empty state with green checkmark icon: "All cached answers are up to date". Fetch stale entries on section activation and on tab init (for badge count). Wire badge count to SegmentedButton "Needs Review" segment — show `Badge(label: Text('$count'))` when count > 0. "Still Valid" calls `markCacheReviewed(action: 'confirm')`, removes card from list. "Edit & Reconfirm" calls `markCacheReviewed(action: 'confirm', updatedQuestion: ..., updatedAnswer: ...)`. "Remove from Cache" calls `markCacheReviewed(action: 'delete')`. Refresh stale count after each action. Loading states on all actions.

**Checkpoint**: All 3 stories complete. Stale detection works end-to-end when manuals are re-processed.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final quality pass across all stories

- [ ] T024 [P] Add activity logging (`background_tasks.add_task(log_activity, ...)`) to all new backend endpoints in `backend/routers/manuals.py` — category `"manual_assistant"`, actions: `"generated_qa_candidates"`, `"saved_trained_entries"`, `"fetched_usage_suggestions"`, `"fetched_stale_entries"`, `"reviewed_stale_entry"`. Follow existing logging pattern from `create_verified_answer` endpoint.

- [ ] T025 [P] Audit all loading states and confirm dialogs across `frontend/lib/screens/manual_assistant/train_ai_tab.dart` — ensure every async action (Generate, Save All, Add to Cache, Approve All, Still Valid, Edit & Reconfirm, Remove from Cache) shows a loading indicator and disables the triggering button during execution. Confirm "Remove from Cache" and "Approve All" have confirmation dialogs per spec.

- [ ] T026 Verify RTL layout in `frontend/lib/screens/manual_assistant/train_ai_tab.dart` and all 3 card widgets — test with Arabic text, ensure `Directionality` is respected, action buttons don't overflow, text alignment is correct.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (migration must exist, service extended)
- **User Stories (Phase 3-5)**: All depend on Phase 2 completion
  - US1 (Phase 3): Independent after Phase 2
  - US2 (Phase 4): Independent after Phase 2 (reuses `saveTrainedEntry` from US1 frontend service — method exists in service file regardless)
  - US3 (Phase 5): Independent after Phase 2
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2. No dependencies on other stories.
- **US2 (P2)**: Can start after Phase 2. Reuses `saveTrainedEntry()` from T010 — if implementing in parallel, T010 must complete first.
- **US3 (P3)**: Can start after Phase 2. Fully independent from US1 and US2.

### Within Each User Story

- Backend endpoints can be built in parallel with frontend widgets [P]
- Frontend service methods can be built in parallel with backend endpoints [P]
- Section UI (T012, T017, T023) depends on its card widget and service methods being complete
- Models before services, services before UI integration

### Parallel Opportunities

**Phase 2** (all 4 tasks are [P] — different files):
- T003 (backend paraphrase) || T004 (frontend paraphrase) || T005 (backend verified-answers) || T006 (screen tab) || T007 (tab skeleton)

**US1** (backend || frontend widget || frontend service):
- T008 (backend endpoint) || T009 + T010 (service methods) || T011 (card widget)
- Then T012 (section UI) after T008-T011 complete

**US2** (same pattern):
- T014 (backend) || T015 (service) || T016 (card widget)
- Then T017 (section UI) after T014-T016 complete

**US3** (same pattern):
- T018 + T019 + T020 (backend endpoints) || T021 (service methods) || T022 (card widget)
- Then T023 (section UI) after T018-T022 complete

---

## Parallel Example: User Story 1

```text
# Launch backend and frontend in parallel:
Task T008: "POST /manuals/generate-qa-candidates in backend/routers/manuals.py"
Task T009: "generateQACandidates() in frontend/lib/services/manual_assistant_service.dart"
Task T010: "saveTrainedEntry() in frontend/lib/services/manual_assistant_service.dart"
Task T011: "qa_candidate_card.dart in frontend/lib/screens/manual_assistant/widgets/"

# Then integrate:
Task T012: "From Manuals section UI in train_ai_tab.dart" (depends on T008-T011)
Task T013: "Session history in train_ai_tab.dart" (depends on T012)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (migration + service extension)
2. Complete Phase 2: Foundational (paraphrase lang, tab skeleton)
3. Complete Phase 3: US1 — Bootstrap from Manuals
4. **STOP and VALIDATE**: Generate candidates from a real manual, approve, save, verify in Verified Answers tab
5. Deploy if ready — US1 alone delivers ~80% of the training value

### Incremental Delivery

1. Setup + Foundational → Tab visible with 3-section navigation
2. Add US1 → Admin can bulk-seed cache from manuals (MVP!)
3. Add US2 → Self-improving loop from real technician usage
4. Add US3 → Staleness detection keeps cache current
5. Polish → Activity logging, RTL, confirm dialogs audit

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story
- All backend endpoints use existing `_admin_check(user_email)` pattern
- All frontend service methods follow existing pattern in `manual_assistant_service.dart`
- Card widgets follow existing patterns from `widgets/review_entry_card.dart`
- The 4-step save flow (verified-answer → EN paraphrases → AR paraphrases → retro_expand) is shared between US1 and US2
- `provider_generate` = `from services.ai_providers.resolver import generate`
- Commit after each task or logical group
