# Spec 087 — Post-Review Fixes for Opencode

Hand-off brief after Claude's Superpowers code review. Implementation for spec 087 is mostly in place but has 3 contract-level blockers, a bad test, a polluted branch, and 3 missing test files. Work these items in order; the groups are independent enough to commit separately.

**Branch**: `087-thumbs-down-reason` (already checked out, all work uncommitted).
**Do NOT commit anything before finishing Group A.**

---

## Group A — Blockers (must ship in the 087 PR)

### A1. Tighten `RatingFeedbackRequest` validation

**File**: `backend/routers/manuals.py` (around lines 860–865).

The Pydantic model currently accepts any string for `feedback_reason` and has no length cap on `feedback_comment`. Contract ([specs/087-thumbs-down-reason/contracts/patch-rating-feedback.md](contracts/patch-rating-feedback.md)) requires 422 for both cases. FR-013 and FR-014 rely on this.

**Change:**
- Ensure `from pydantic import BaseModel, Field` (add `Field` if missing).
- Add `from typing import Literal` (add to the existing typing import line).
- Rewrite the model as:

```python
class RatingFeedbackRequest(BaseModel):
    feedback_reason: Literal[
        "inaccurate", "incomplete", "outdated", "wrong_source", "unclear"
    ]
    feedback_comment: Optional[str] = Field(None, max_length=2000)
    user_email: str
```

After this change, unknown reasons and 2001+ char comments return 422 at the request-parsing layer (before the handler runs). The existing `ValueError` paths in the handler become dead code for those cases, which is fine — keep them as belt-and-braces.

### A2. Remove duplicate `rated_answer_feedback` activity log

**Files**: `backend/routers/manuals.py` (lines ~875–884) and `backend/services/validated_qa_service.py` (lines ~144–152).

Today both layers call `log_activity(..., 'rated_answer_feedback', ...)`. Every PATCH produces two audit rows — one with a real `target_label` (from the service) and one with an empty `target_label` (from the router). Constitution VI says audit is required but must be correct.

**Keep** the service-layer emission (inside `update_rating_feedback`, has the real `target_label=<first 80 chars of question_text>`). **Remove** the router-layer copy entirely. Leave the fire-and-forget `try/except` wrapper on whichever call remains.

Spot-check after the fix: a successful PATCH should insert exactly one row in `user_activity_log` with `action='rated_answer_feedback'` and a non-empty `target_label`.

### A3. Fix `TestDismissalPath` mock

**File**: `backend/tests/routers/test_manuals_rating_feedback.py` (the `TestDismissalPath` class, currently failing with `KeyError: 'validated_answer'`).

Root cause: `get_flagged_answers()` calls `supabase.table('answer_ratings')` first, then `supabase.table('validated_qa')`. The existing mock has one chain that serves both calls, so the `validated_qa` query returns the same rating-shaped row and the loop crashes on `row['validated_answer']`.

**Fix — route by table name**:

```python
def test_negative_rating_row_is_queryable_without_feedback(self):
    row = {
        "id": "11111111-1111-1111-1111-111111111111",
        "question_text": "How do I restart AIDA NG?",
        "answer_text": "Press RESET.",
        "rating": "negative",
        "rater_email": "tech@example.com",
        "feedback_reason": None,
        "feedback_comment": None,
    }

    mock_ratings_table = MagicMock()
    mock_ratings_table.select.return_value.eq.return_value.order.return_value.execute.return_value = MockResponse([row])

    mock_validated_table = MagicMock()
    mock_validated_table.select.return_value.eq.return_value.order.return_value.execute.return_value = MockResponse([])

    def table_router(name):
        if name == "answer_ratings":
            return mock_ratings_table
        if name == "validated_qa":
            return mock_validated_table
        return MagicMock()

    mock_db = MagicMock()
    mock_db.table.side_effect = table_router

    with patch.object(vqa_svc, "supabase", mock_db):
        result = vqa_svc.get_flagged_answers()

    assert len(result) == 1
    assert result[0]["feedback_reason"] is None
    assert result[0]["feedback_comment"] is None
```

The implementation is correct — only the test needs to change.

### A4. 422 tests are false positives — patch the right supabase

**File**: `backend/tests/routers/test_manuals_rating_feedback.py` — `TestPatchRatingFeedbackEndpoint::test_422_on_unknown_reason` and `test_422_on_comment_over_2000_chars`.

After A1 these should naturally return 422 at the Pydantic layer (no supabase reached). Audit the tests: if they patch `vqa_svc.supabase` but not `m_router.supabase`, they may still spuriously pass via a different failure mode. Verify with `pytest -v` that both explicitly assert `response.status_code == 422` and `response.json()['detail'][0]['type']` (or equivalent Pydantic validation-error shape) — not a generic 500.

### A5. Split 086-era and harness changes off the branch

`git status` currently shows files that do NOT belong in spec 087:

- `backend/routers/system_status.py`
- `frontend/lib/screens/system_status_screen.dart`
- `frontend/lib/services/system_status_service.dart`
- `frontend/lib/widgets/system_status_sheet.dart`
- `.opencode/command/speckit.implement.md`
- `CLAUDE.md`
- untracked `OPENCODE.md`

Before committing 087, stash these or move them to a separate branch. The 087 PR must only touch the spec's declared file set (see plan.md §Project Structure).

---

## Group B — Suggested commit breakdown (after Group A clears)

Once blockers are fixed, land as six focused commits (git-friendly, reviewable):

1. **Migration** — `supabase/migrations/20260419000000_add_rating_feedback.sql` only.
2. **Backend PATCH endpoint + service** — `backend/routers/manuals.py` (tightened model, single log_activity) + `backend/services/validated_qa_service.py` (new `update_rating_feedback`, `get_flagged_answers` returns new columns).
3. **Backend contract tests** — `backend/tests/routers/test_manuals_rating_feedback.py` (with A3 and A4 fixes applied).
4. **Frontend service + feedback sheet widget** — `frontend/lib/services/manual_assistant_service.dart` + `frontend/lib/screens/manual_assistant/widgets/feedback_reason_sheet.dart`.
5. **Wire sheet into chat + render chips in review card** — `frontend/lib/screens/manual_assistant/chat_tab.dart` + `frontend/lib/screens/manual_assistant/widgets/review_entry_card.dart`.
6. **Flutter widget tests** — see Group C.

Each commit message should follow the existing project style (spec 086's commits are good references):

```
spec 087: <component> — <what changed in one line>
```

No Claude Code co-author line — per project memory the user doesn't use them on opencode work.

---

## Group C — Missing tasks (in-scope for this PR per tasks.md)

These tasks from [tasks.md](tasks.md) were skipped. Implement before the final commit of the PR.

### C1. Move and fix feedback sheet widget test (T010)

**Currently**: `frontend/test/widget/feedback_reason_sheet_test.dart` — wrong directory, and the `Skip returns null` test contains non-compiling code.

**Target**: `frontend/test/screens/manual_assistant/widgets/feedback_reason_sheet_test.dart`.

Re-implement the four assertions properly using `testWidgets`:

- (a) tapping Skip returns `null` from `FeedbackReasonSheet.show(context)`
- (b) swipe-to-dismiss returns `null`
- (c) Save button is disabled until a reason chip is selected
- (d) selecting a chip + tapping Save returns a `FeedbackSheetResult` with the correct reason and comment
- (e) a chat_tab or equivalent test: `_handleRate(rating: 'positive')` does NOT call `showModalBottomSheet` (mock `rateAnswer` to return a dummy rating id; use `expect` with a spy or just assert the sheet's Save callback is never invoked)

Use `tester.pumpWidget`, `tester.tap`, and `tester.pumpAndSettle`. No network mocks needed (the widget itself makes no server calls; the chat-tab branch needs `_service.rateAnswer` stubbed).

### C2. Add review card widget test (T014)

**Create**: `frontend/test/screens/manual_assistant/widgets/review_entry_card_test.dart`.

Six assertions (one per chip state):

- Inaccurate → expect `Chip` with label text "Inaccurate" and background color `0xFFE57373` (red shade400)
- Incomplete → "Incomplete", `0xFFFFB74D` (orange shade400)
- Outdated → "Outdated", `0xFFFFCA28` (amber shade600)
- Wrong source → "Wrong source", `Colors.deepPurple.shade400` — **NOTE**: current implementation uses `0xFFBA68C8` (purple.shade400). Fix the implementation to match research Decision 7 (`deepPurple.shade400`); the test locks in the correct value.
- Unclear → "Unclear", `0xFF90A4AE` (blueGrey shade400)
- null → "No reason given" chip with grey color (`0xFFE0E0E0` or equivalent shade400)

Use `tester.pumpWidget` with a `MaterialApp` wrapper and a mocked `entry` map.

### C3. FR-011 regression test (T019)

**Create**: `backend/tests/routers/test_manuals_reason_informational.py`.

Seed 5 `answer_ratings` rows (one per reason) plus 5 control rows with NULL reason. Exercise:

- `update_validated_rating` — assert the reflag threshold behavior (`thumbs_up_count`, `thumbs_down_count`, `is_reflagged`) is identical regardless of `feedback_reason` value.
- `/manuals/real-usage-suggestions` — assert the ordering and grouping logic is identical.
- The approve/correct flow (via `review_answer`) — assert the generated `validated_qa` row is identical.

Mock Supabase responses; no live DB required.

### C4. SC-006 approve/correct smoke test (T020)

**Create**: `backend/tests/routers/test_manuals_approve_correct_regression.py`.

Seed one flagged rating with a populated reason + comment. Invoke `review_answer(action='approve')`. Assert:

- Exactly one `validated_qa` row is produced
- No extra round-trips to Supabase (count the table calls or just assert on the result shape)
- The `validated_answer` is unchanged from the rating's `answer_text`

Repeat with `action='correct'` and a `corrected_answer`, assert the `validated_answer` equals the corrected text.

---

## Group D — Minor cleanups (low severity, can slip to follow-up PR if needed)

### D1. Fix wrong-source chip color

**File**: `frontend/lib/screens/manual_assistant/widgets/feedback_reason_sheet.dart` (and anywhere the color is duplicated).

Change `0xFFBA68C8` (purple.shade400) → `Colors.deepPurple.shade400` (`0xFF7E57C2`). Research Decision 7 specifies `deepPurple`. The palette mismatch is small but now that C2 test pins it, keep implementation and test aligned.

### D2. Mounted check before `FeedbackReasonSheet.show`

**File**: `frontend/lib/screens/manual_assistant/chat_tab.dart` (around line 263).

Immediately before `FeedbackReasonSheet.show(context)`, add:

```dart
if (!mounted) return;
```

Prevents a `use_build_context_synchronously` lint if strict analyzer rules turn on. Current outer try/catch hides the race but the check is free.

### D3. AppColors for semantic colors

**File**: `frontend/lib/screens/manual_assistant/widgets/feedback_reason_sheet.dart`.

Local constants `_textSecondary`, `_border2` should pull from `app_theme.dart` / `AppColors` if equivalents exist. Chip colors are spec-locked (research Decision 7) and can stay hardcoded. Low priority.

---

## Verification checklist (run after Group A + Group B + Group C)

```bash
cd backend
pytest tests/routers/test_manuals_rating_feedback.py -v
pytest tests/routers/test_manuals_reason_informational.py -v
pytest tests/routers/test_manuals_approve_correct_regression.py -v
ruff check .

cd ../frontend
flutter test test/screens/manual_assistant/widgets/
flutter analyze
```

All must be green before opening the PR.

## After-merge (not part of this PR)

- T021 deploy: apply the migration to production Supabase, restart `document_server.service`.
- T022: invoke the `architecture-doc-updater` agent to refresh ARCHITECTURE.md and AGENT.md with the new endpoint/columns.

---

**Nothing here requires re-spec or re-plan.** The spec, plan, research, data-model, and contracts are correct. The implementation just drifted from the contract in a few small but consequential places.
