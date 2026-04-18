# Code Review Fixes: Spec 080 — Train the AI Tab

**Created**: 2026-04-18
**Branch**: `080-train-ai-tab`
**Status**: Implementation complete but has critical bugs found in code review

## Context

Spec 080 is implemented end-to-end but a superpowers code review found 4 critical runtime bugs that break features in production, plus several important data integrity issues. Fix these before merge.

**DO NOT** change anything outside the listed issues. Preserve existing behavior everywhere else.

Reference docs (read before starting):
- `specs/080-train-ai-tab/spec.md` — user stories and acceptance scenarios
- `specs/080-train-ai-tab/contracts/api-endpoints.md` — API contracts
- `specs/080-train-ai-tab/data-model.md` — schema and entity relationships

---

## Priority 1: CRITICAL (must fix — breaks features at runtime)

### F1. Fix `"now()"` string in mark-cache-reviewed endpoint

**File**: `backend/routers/manuals.py`

**Problem**: The endpoint passes `"now()"` as a string value to Supabase. PostgREST sends it as a JSON string literal, and PostgreSQL rejects it with `invalid input syntax for type timestamp with time zone: "now()"`. This means **every "Still Valid" and "Edit & Reconfirm" action in Section C throws 500**. Same bug was fixed in spec 070 (commit `1616553`).

**Fix steps**:

1. At the top of the file, confirm this import exists (it should be there already from previous work):
```python
from datetime import datetime, timezone
```

2. In `mark_cache_reviewed` endpoint (around line 1495), replace all `"now()"` usages with proper ISO timestamps.

**Find** (in the "confirm" branch, around line 1502):
```python
        if request.action == "confirm":
            update_data = {"verified_at": "now()"}
```

**Replace with**:
```python
        if request.action == "confirm":
            now_iso = datetime.now(timezone.utc).isoformat()
            update_data = {"verified_at": now_iso}
```

**Find** (in the same branch, around line 1522):
```python
            if target_rating_id:
                variant_resp = (
                    supabase.table("validated_qa")
                    .update({"verified_at": "now()"})
                    .eq("rating_id", target_rating_id)
                    .neq("id", request.qa_id)
                    .execute()
                )
```

**Replace with**:
```python
            if target_rating_id:
                variant_resp = (
                    supabase.table("validated_qa")
                    .update({"verified_at": now_iso})
                    .eq("rating_id", target_rating_id)
                    .neq("id", request.qa_id)
                    .execute()
                )
```

**Find** (the response at around line 1541):
```python
            return {
                "status": "confirmed",
                "qa_id": request.qa_id,
                "verified_at": "now",
                "updated_count": updated_count,
            }
```

**Replace with**:
```python
            return {
                "status": "confirmed",
                "qa_id": request.qa_id,
                "verified_at": now_iso,
                "updated_count": updated_count,
            }
```

**Verification**: After fix, clicking "Still Valid" on a stale entry should update the `verified_at` timestamp in the DB to the current UTC time, return HTTP 200, and remove the card from the UI.

---

### F2. Fix `_loadManuals` crash in Section A

**File**: `frontend/lib/screens/manual_assistant/train_ai_tab.dart`

**Problem**: `listManuals()` returns `{'manuals': List<Manual>, 'corpus_stats': CorpusStats}` where the list contains `Manual` model instances, NOT `Map`. The current code calls `Map<String, dynamic>.from(Manual)` which throws `TypeError: type 'Manual' is not a subtype of type 'Map<dynamic, dynamic>'`. The silent catch swallows it. **The dropdown stays empty forever, making Section A completely unusable.**

**Fix steps**:

1. Add the `Manual` model import at the top of `train_ai_tab.dart`:

**Find** (top of file):
```dart
import 'package:flutter/material.dart';
import '../../services/manual_assistant_service.dart';
import 'widgets/qa_candidate_card.dart';
import 'widgets/usage_suggestion_card.dart';
import 'widgets/stale_entry_card.dart';
```

**Replace with**:
```dart
import 'package:flutter/material.dart';
import '../../models/manual.dart';
import '../../services/manual_assistant_service.dart';
import 'widgets/qa_candidate_card.dart';
import 'widgets/usage_suggestion_card.dart';
import 'widgets/stale_entry_card.dart';
```

2. Change the `_manuals` field type in `_FromManualsSectionState` from `List<Map<String, dynamic>>` to `List<Manual>`:

**Find**:
```dart
class _FromManualsSectionState extends State<_FromManualsSection> {
  List<Map<String, dynamic>> _manuals = [];
  String? _selectedManualId;
```

**Replace with**:
```dart
class _FromManualsSectionState extends State<_FromManualsSection> {
  List<Manual> _manuals = [];
  String? _selectedManualId;
```

3. Fix `_loadManuals` to use the Manual model:

**Find**:
```dart
  Future<void> _loadManuals() async {
    try {
      final result = await widget.service.listManuals();
      final list = (result['manuals'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      if (mounted) {
        setState(() {
          _manuals = list;
          _loadingManuals = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingManuals = false);
    }
  }
```

**Replace with**:
```dart
  Future<void> _loadManuals() async {
    try {
      final result = await widget.service.listManuals();
      final list = (result['manuals'] as List<dynamic>?)?.cast<Manual>() ?? [];
      if (mounted) {
        setState(() {
          _manuals = list;
          _loadingManuals = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingManuals = false);
    }
  }
```

4. Fix the dropdown items to use `Manual` accessors (`.id`, `.title`):

**Find** (inside the DropdownButtonFormField):
```dart
                        items: _manuals.map((m) {
                          return DropdownMenuItem<String>(
                            value: m['id'] as String,
                            child: Text(
                              m['title'] as String? ?? 'Untitled',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedManualId = val;
                            _selectedManualTitle = _manuals
                                .firstWhere((m) => m['id'] == val)['title']
                                as String?;
                          });
                        },
```

**Replace with**:
```dart
                        items: _manuals.map((m) {
                          return DropdownMenuItem<String>(
                            value: m.id,
                            child: Text(
                              m.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedManualId = val;
                            _selectedManualTitle = _manuals
                                .firstWhere((m) => m.id == val)
                                .title;
                          });
                        },
```

**Verification**: After fix, opening the Train AI tab → From Manuals section should populate the dropdown with all processed manuals. Selecting one should enable the Generate button.

---

### F3. Fix orphaned variants on "Remove from Cache"

**Files**: `backend/services/validated_qa_service.py` AND `backend/routers/manuals.py`

**Problem**: The 4-step save flow creates a primary `validated_qa` row (with `rating_id=NULL`) then calls `_retro_expand_multi` which inserts paraphrase variants that copy `rating_id=NULL` from the primary. When admin clicks "Remove from Cache", the delete query filters on `rating_id = target_rating_id`, but since `target_rating_id` is NULL, that block is skipped. **Only the primary is deleted; the 7 variants remain in the DB forever.**

Additionally, `source_manual_id` is NOT copied to variants, so they also don't show up as stale when the source manual is updated.

**Solution**: Generate a synthetic `rating_id` UUID on the primary row during the save flow. Variants naturally copy it via the existing `_retro_expand_multi` logic. Delete then cascades correctly.

**Fix steps**:

1. In `backend/services/validated_qa_service.py`, find `create_verified_answer` and add synthetic `rating_id` generation.

**Find**:
```python
async def create_verified_answer(
    question_text: str,
    validated_answer: str,
    editor_email: str,
    source_manual_id: Optional[str] = None,
) -> dict:
    if not question_text.strip() or not validated_answer.strip():
        raise ValueError("question and answer required")

    embedding = await embed_single(question_text)
    embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"

    equipment_type = _extract_equipment_type(question_text)
    fault_code = _extract_fault_code(question_text)

    insert_data = {
        "question_text": question_text,
        "validated_answer": validated_answer,
        "question_embedding": embedding_str,
        "validated_by": editor_email,
        "equipment_type": equipment_type,
        "fault_code": fault_code,
        "source_chunks": [],
        "manual_ids": [],
    }
    if source_manual_id:
        insert_data["source_manual_id"] = source_manual_id

    result = supabase.table("validated_qa").insert(insert_data).execute()

    return result.data[0]
```

**Replace with**:
```python
async def create_verified_answer(
    question_text: str,
    validated_answer: str,
    editor_email: str,
    source_manual_id: Optional[str] = None,
) -> dict:
    import uuid as _uuid

    if not question_text.strip() or not validated_answer.strip():
        raise ValueError("question and answer required")

    embedding = await embed_single(question_text)
    embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"

    equipment_type = _extract_equipment_type(question_text)
    fault_code = _extract_fault_code(question_text)

    # Synthetic rating_id groups primary + variants for cascade delete
    # (spec 080 fix: variants copy rating_id via _retro_expand_multi,
    # so using a fresh UUID groups them even without a real rating)
    synthetic_rating_id = str(_uuid.uuid4())

    insert_data = {
        "question_text": question_text,
        "validated_answer": validated_answer,
        "question_embedding": embedding_str,
        "validated_by": editor_email,
        "equipment_type": equipment_type,
        "fault_code": fault_code,
        "source_chunks": [],
        "manual_ids": [],
        "rating_id": synthetic_rating_id,
    }
    if source_manual_id:
        insert_data["source_manual_id"] = source_manual_id

    result = supabase.table("validated_qa").insert(insert_data).execute()

    return result.data[0]
```

2. **IMPORTANT**: Check that `validated_qa.rating_id` is nullable and NOT unique. The migration `20260415000000_make_rating_id_nullable.sql` made it nullable. Verify there is no UNIQUE constraint on `rating_id` — if there is, the variants would fail to insert (they share the rating_id). If UNIQUE exists, the fix is more involved (needs a new `group_id` column). Run this to check:

```sql
SELECT conname, contype FROM pg_constraint
WHERE conrelid = 'validated_qa'::regclass
AND contype IN ('u', 'p');
```

If `rating_id` has a UNIQUE constraint, STOP and report back — this fix approach won't work. Otherwise proceed.

3. No changes needed in `mark_cache_reviewed` — the existing delete logic already handles `rating_id IS NOT NULL` correctly:

```python
if target_rating_id:
    variant_del = (
        supabase.table("validated_qa")
        .delete()
        .eq("rating_id", target_rating_id)
        .execute()
    )
```

With the synthetic UUID always set now, this branch fires and cascades to all variants.

**Verification**:
- Before fix: Save a trained entry → 8 rows in `validated_qa` with `rating_id=NULL`. Click Remove → 1 deleted, 7 orphaned.
- After fix: Save → 8 rows sharing same synthetic `rating_id`. Click Remove → all 8 deleted.

---

### F4. Delete broken `backend/train_ai.py` and `training_data.json`

**Files**:
- `backend/train_ai.py`
- `backend/training_data.json`

**Problem**: These files were added during implementation but are NOT part of spec 080. The script is broken:
- Line 53: `await provider_generate(prompt, timeout=30.0)` — `generate()` from `resolver` doesn't accept a `timeout` kwarg
- Line 54: `parse_paraphrase_output(raw, question)` — `raw` is actually a 5-tuple `(answer, provider_key, display_name, fallback_used, fallback_info)`, not a string

They cannot execute. They should not ship with the spec 080 PR.

**Fix**: Delete both files.

```bash
rm backend/train_ai.py
rm backend/training_data.json
```

**Verification**: `git status` should not show these files. No other file imports from `train_ai.py` (verify with `grep -r "from train_ai" backend/` — should return no results).

---

## Priority 2: IMPORTANT (should fix — data/perf concerns)

### F5. Lift session history to tab level (violates FR-016)

**File**: `frontend/lib/screens/manual_assistant/train_ai_tab.dart`

**Problem**: `_sessionHistory` lives on `_FromManualsSectionState`. When admin switches sections (e.g., to "From Real Usage") and comes back, Flutter disposes the state and the history is lost. FR-016 says the history should persist "for the duration of the tab session" — meaning while the Train AI tab is active, not just while viewing Section A.

**Fix**: Lift `_sessionHistory` state into `_TrainAiTabState` and pass it down to `_FromManualsSection`.

1. Add the field to `_TrainAiTabState` (near `_staleCount`):

**Find** (around line 21-23):
```dart
class _TrainAiTabState extends State<TrainAiTab> {
  int _selectedSection = 0;
  int _staleCount = 0;
```

**Replace with**:
```dart
class _TrainAiTabState extends State<TrainAiTab> {
  int _selectedSection = 0;
  int _staleCount = 0;
  final List<String> _sessionHistory = [];
```

2. Pass it to `_FromManualsSection` in `_buildSectionBody`:

**Find** (in `_buildSectionBody()`):
```dart
      case 0:
        return _FromManualsSection(
          userEmail: widget.userEmail,
          service: widget.service,
        );
```

**Replace with**:
```dart
      case 0:
        return _FromManualsSection(
          userEmail: widget.userEmail,
          service: widget.service,
          sessionHistory: _sessionHistory,
          onHistoryChanged: () => setState(() {}),
        );
```

3. Update `_FromManualsSection` to accept and use the passed-in list:

**Find**:
```dart
class _FromManualsSection extends StatefulWidget {
  final String userEmail;
  final ManualAssistantService service;

  const _FromManualsSection({
    required this.userEmail,
    required this.service,
  });

  @override
  State<_FromManualsSection> createState() => _FromManualsSectionState();
}
```

**Replace with**:
```dart
class _FromManualsSection extends StatefulWidget {
  final String userEmail;
  final ManualAssistantService service;
  final List<String> sessionHistory;
  final VoidCallback onHistoryChanged;

  const _FromManualsSection({
    required this.userEmail,
    required this.service,
    required this.sessionHistory,
    required this.onHistoryChanged,
  });

  @override
  State<_FromManualsSection> createState() => _FromManualsSectionState();
}
```

4. Remove the local `_sessionHistory` field and replace all references with `widget.sessionHistory`:

**Find** (in `_FromManualsSectionState`):
```dart
  final List<String> _sessionHistory = [];
```

**Delete this line entirely.**

**Find** (in `_saveAllApproved`):
```dart
      if (savedCount > 0) {
        _sessionHistory.add(
          '$manualName — $savedCount pairs saved · $totalEmbeddings embeddings · $ts',
        );
        if (_sessionHistory.length > 20) {
          _sessionHistory.removeAt(0);
        }
      }
```

**Replace with**:
```dart
      if (savedCount > 0) {
        widget.sessionHistory.add(
          '$manualName — $savedCount pairs saved · $totalEmbeddings embeddings · $ts',
        );
        if (widget.sessionHistory.length > 20) {
          widget.sessionHistory.removeAt(0);
        }
        widget.onHistoryChanged();
      }
```

**Find** (in the build method — the section that renders session history):
```dart
        if (_sessionHistory.isNotEmpty)
          Container(
            ...
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _sessionHistory
```

**Replace with**:
```dart
        if (widget.sessionHistory.isNotEmpty)
          Container(
            ...
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.sessionHistory
```

**Verification**: Save entries in Section A → switch to Section B → switch back to Section A. History rows should still be visible.

---

### F6. Stringify chunk_embedding before RPC call

**File**: `backend/routers/manuals.py`

**Problem**: In `generate_qa_candidates`, the code passes `chunk_embedding` (a Python list) directly to `search_validated_qa` RPC. Every other call site in the codebase passes it stringified. If supabase-py mis-serializes the list, the RPC silently fails (caught by the bare `except: pass`), dedup never runs, and `skipped_cached` stays 0 — a silent correctness bug.

**Fix**:

**Find** (around line 1212-1221):
```python
        try:
            rpc_resp = supabase.rpc(
                "search_validated_qa",
                {"q_embedding": chunk_embedding, "match_count": 1},
            ).execute()
            if rpc_resp.data and rpc_resp.data[0].get("distance", 1.0) < 0.15:
                skipped_cached += 1
                skipped_ids.add(chunk["id"])
        except Exception:
            pass
```

**Replace with**:
```python
        try:
            embedding_arg = chunk_embedding
            if isinstance(embedding_arg, list):
                embedding_arg = "[" + ",".join(str(x) for x in embedding_arg) + "]"
            rpc_resp = supabase.rpc(
                "search_validated_qa",
                {"q_embedding": embedding_arg, "match_count": 1},
            ).execute()
            if rpc_resp.data and rpc_resp.data[0].get("distance", 1.0) < 0.15:
                skipped_cached += 1
                skipped_ids.add(chunk["id"])
        except Exception as e:
            logger.warning(f"Cache dedup check failed for chunk {chunk.get('id')}: {e}")
```

Note: Also replaced bare `pass` with a warning log so future silent failures are observable.

**Verification**: Run generation on a manual with chunks similar to existing validated_qa entries. `skipped_cached` in the response should be > 0 for those chunks.

---

### F7. Add rollback to `saveTrainedEntry` on partial failure

**File**: `frontend/lib/services/manual_assistant_service.dart`

**Problem**: The 4-step save flow has 4 sequential API calls. If step 2, 3, or 4 fails, the primary `validated_qa` row from step 1 remains in the DB without variants. The frontend rethrows but doesn't clean up.

**Fix**: Wrap steps 2-4 in a try/catch that deletes the primary on failure.

**Find** (the `saveTrainedEntry` method, around line 960):
```dart
  Future<Map<String, dynamic>> saveTrainedEntry({
    required String question,
    required String answer,
    required String editorEmail,
    String? sourceManualId,
  }) async {
    try {
      final result = await createVerifiedAnswer(
        questionText: question,
        validatedAnswer: answer,
        editorEmail: editorEmail,
        sourceManualId: sourceManualId,
      );
      final primaryQaId = result['id'] as String;

      final enVariants = await generateParaphraseVariants(
        questionText: question,
        lang: 'en',
      );

      final arVariants = await generateParaphraseVariants(
        questionText: question,
        lang: 'ar',
      );

      await reviewAnswerWithVariants(
        ratingId: '',
        action: 'retro_expand',
        existingValidatedQaId: primaryQaId,
        variants: [...enVariants, ...arVariants],
      );

      return {
        'primaryQaId': primaryQaId,
        'englishCount': enVariants.length,
        'arabicCount': arVariants.length,
        'totalEmbeddings': enVariants.length + arVariants.length,
      };
    } catch (e) {
      rethrow;
    }
  }
```

**Replace with**:
```dart
  Future<Map<String, dynamic>> saveTrainedEntry({
    required String question,
    required String answer,
    required String editorEmail,
    String? sourceManualId,
  }) async {
    // Step 1: create primary entry
    final result = await createVerifiedAnswer(
      questionText: question,
      validatedAnswer: answer,
      editorEmail: editorEmail,
      sourceManualId: sourceManualId,
    );
    final primaryQaId = result['id'] as String;

    // Steps 2-4: rollback primary on any failure
    try {
      final enVariants = await generateParaphraseVariants(
        questionText: question,
        lang: 'en',
      );

      final arVariants = await generateParaphraseVariants(
        questionText: question,
        lang: 'ar',
      );

      await reviewAnswerWithVariants(
        ratingId: '',
        action: 'retro_expand',
        existingValidatedQaId: primaryQaId,
        variants: [...enVariants, ...arVariants],
      );

      return {
        'primaryQaId': primaryQaId,
        'englishCount': enVariants.length,
        'arabicCount': arVariants.length,
        'totalEmbeddings': enVariants.length + arVariants.length,
      };
    } catch (e) {
      // Rollback: remove the orphaned primary
      try {
        await deleteVerifiedAnswer(
          qaId: primaryQaId,
          editorEmail: editorEmail,
        );
      } catch (_) {
        // Best-effort cleanup; if delete fails, surface original error
      }
      rethrow;
    }
  }
```

**Verification**: Manually trigger a failure by temporarily breaking the Arabic paraphrase endpoint — the primary entry should not appear in Verified Answers after the save attempt fails.

---

## Priority 3: MINOR (optional cleanup)

### F8. Remove unused `_refreshStaleCount` indirection

**File**: `frontend/lib/screens/manual_assistant/train_ai_tab.dart`

**Problem**: `_refreshStaleCount()` just calls `_loadStaleCount()`. Redundant.

**Find**:
```dart
  void _refreshStaleCount() {
    _loadStaleCount();
  }
```

**Delete this method.**

**Find** (in `_buildSectionBody`):
```dart
        return _NeedsReviewSection(
          userEmail: widget.userEmail,
          service: widget.service,
          onRefresh: _refreshStaleCount,
        );
```

**Replace with**:
```dart
        return _NeedsReviewSection(
          userEmail: widget.userEmail,
          service: widget.service,
          onRefresh: _loadStaleCount,
        );
```

---

## Execution Order

Do fixes in this order (later fixes depend on earlier ones compiling):

1. F4 — Delete broken scratch files (trivial, reduces noise)
2. F1 — Fix `"now()"` bug (unblocks US3 testing)
3. F2 — Fix dropdown crash (unblocks US1 testing)
4. F3 — Fix orphan variants (verify DB constraint first!)
5. F6 — Stringify chunk embedding (backend-only, low risk)
6. F7 — Rollback on partial failure (defensive, low risk)
7. F5 — Lift session history (UX improvement)
8. F8 — Minor cleanup

## Verification Checklist

After applying all fixes, verify:

- [ ] `git status` does not show `backend/train_ai.py` or `backend/training_data.json`
- [ ] Flutter analyze is clean (`flutter analyze lib/screens/manual_assistant/train_ai_tab.dart`)
- [ ] Open Train AI tab as admin → From Manuals dropdown is populated
- [ ] Generate candidates → approve one → save → verify entry + 7 variants in `validated_qa` with same `rating_id`
- [ ] Re-process a manual → open Needs Review → click "Still Valid" on a stale entry → returns 200, entry disappears, DB shows updated `verified_at`
- [ ] Click "Remove from Cache" on a stale entry → primary + all variants deleted in one call
- [ ] Save entries in Section A → switch to Section B → switch back → session history still visible

## Commit Message

When done, commit with:

```
fix(080): apply code review fixes — now() bug, dropdown crash, orphan variants, session history lift

- F1: Replace "now()" strings with ISO timestamps in mark-cache-reviewed
- F2: Fix _loadManuals to handle Manual model instances (not Maps)
- F3: Add synthetic rating_id to cascade delete variants
- F4: Remove unrelated scratch files (train_ai.py, training_data.json)
- F5: Lift sessionHistory to tab scope so it survives section switches
- F6: Stringify chunk_embedding before search_validated_qa RPC
- F7: Rollback primary validated_qa on partial save failure
- F8: Collapse _refreshStaleCount indirection
```
