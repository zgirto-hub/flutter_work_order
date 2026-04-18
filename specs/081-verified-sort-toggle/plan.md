# Verified Tab Sort Toggle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a three-option sort dropdown ("Most recent", "Most used", "Most problematic") to the Verified tab so admins can surface greatest-hits and problematic entries without leaving the screen.

**Architecture:** Pure additive change. One new query parameter (`sort`) on the existing `/manuals/verified-answers` endpoint. The service-layer function `get_all_verified_answers` branches its WHERE/ORDER BY on the sort value. The count query uses the same WHERE filter so the "N verified answers" badge matches the list. Frontend adds one `DropdownButton` next to the existing search field and re-fetches on change.

**Tech Stack:** Python 3.10 + FastAPI + Supabase Python client (backend); Dart 3.x + Flutter Material (frontend); pytest + unittest.mock for backend tests.

---

## File Structure

**Backend — Modify:**
- [backend/services/validated_qa_service.py](backend/services/validated_qa_service.py) — `get_all_verified_answers()` gains a `sort` parameter and branches the query builder.
- [backend/routers/manuals.py](backend/routers/manuals.py) — `/manuals/verified-answers` route gains a `sort` query param with validation.

**Backend — Create:**
- [backend/tests/test_verified_sort.py](backend/tests/test_verified_sort.py) — Unit tests for the service-layer branching and route validation.

**Frontend — Modify:**
- [frontend/lib/services/manual_assistant_service.dart](frontend/lib/services/manual_assistant_service.dart) — `getVerifiedAnswers()` gains an optional `sort` parameter that becomes a query string.
- [frontend/lib/screens/manual_assistant/verified_answers_tab.dart](frontend/lib/screens/manual_assistant/verified_answers_tab.dart) — Add `_sort` state, a dropdown widget, pass `sort` through `_loadEntries`, update the empty-state text based on the active sort.

No schema changes. No migrations. No new routes.

---

### Task 1: Backend — Service-layer sort branching

**Files:**
- Modify: [backend/services/validated_qa_service.py:360-381](backend/services/validated_qa_service.py#L360-L381)
- Test: [backend/tests/test_verified_sort.py](backend/tests/test_verified_sort.py) (create)

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_verified_sort.py`:

```python
"""
Tests for Verified tab sort toggle (spec 081).

Verifies that get_all_verified_answers() applies the correct
WHERE filter and ORDER BY for each sort value, and that the
count query uses the same filter as the data query.
"""
import pytest
from unittest.mock import MagicMock, patch


def _build_mock_supabase():
    """Shared mock supabase that records .select().gt().ilike().order().range() chain."""
    mock_query = MagicMock()
    mock_query.select.return_value = mock_query
    mock_query.gt.return_value = mock_query
    mock_query.ilike.return_value = mock_query
    mock_query.order.return_value = mock_query
    mock_query.range.return_value = mock_query
    mock_query.execute.return_value = MagicMock(data=[], count=0)

    mock_client = MagicMock()
    mock_client.table.return_value = mock_query
    return mock_client, mock_query


class TestGetAllVerifiedAnswersSort:
    def test_default_recent_sort_has_no_vote_filter(self):
        from services import validated_qa_service

        mock_client, mock_query = _build_mock_supabase()
        with patch.object(validated_qa_service, "supabase", mock_client):
            validated_qa_service.get_all_verified_answers(sort="recent")

        # Should NOT call .gt() on thumbs_up_count or thumbs_down_count
        gt_calls = [c.args for c in mock_query.gt.call_args_list]
        assert gt_calls == [], f"Expected no .gt() calls for 'recent', got {gt_calls}"

        # Should order by updated_at desc
        order_calls = [c.args for c in mock_query.order.call_args_list]
        assert ("updated_at",) in [a[:1] for a in order_calls], \
            f"Expected order by updated_at, got {order_calls}"

    def test_most_used_filters_and_orders_by_thumbs_up(self):
        from services import validated_qa_service

        mock_client, mock_query = _build_mock_supabase()
        with patch.object(validated_qa_service, "supabase", mock_client):
            validated_qa_service.get_all_verified_answers(sort="most_used")

        # Must filter thumbs_up_count > 0
        gt_calls = [c.args for c in mock_query.gt.call_args_list]
        assert ("thumbs_up_count", 0) in gt_calls, \
            f"Expected .gt('thumbs_up_count', 0), got {gt_calls}"

        # Must order by thumbs_up_count desc with updated_at tie-breaker
        order_cols = [c.args[0] for c in mock_query.order.call_args_list]
        assert order_cols[0] == "thumbs_up_count", \
            f"Primary sort should be thumbs_up_count, got {order_cols}"
        assert "updated_at" in order_cols, \
            f"Expected updated_at tie-breaker, got {order_cols}"

    def test_most_problematic_filters_and_orders_by_thumbs_down(self):
        from services import validated_qa_service

        mock_client, mock_query = _build_mock_supabase()
        with patch.object(validated_qa_service, "supabase", mock_client):
            validated_qa_service.get_all_verified_answers(sort="most_problematic")

        gt_calls = [c.args for c in mock_query.gt.call_args_list]
        assert ("thumbs_down_count", 0) in gt_calls, \
            f"Expected .gt('thumbs_down_count', 0), got {gt_calls}"

        order_cols = [c.args[0] for c in mock_query.order.call_args_list]
        assert order_cols[0] == "thumbs_down_count", \
            f"Primary sort should be thumbs_down_count, got {order_cols}"
        assert "updated_at" in order_cols, \
            f"Expected updated_at tie-breaker, got {order_cols}"

    def test_count_query_uses_same_filter_as_data_query(self):
        """Both the data query and the count query must apply the .gt() filter
        so the 'N verified answers' badge matches the list length."""
        from services import validated_qa_service

        mock_client, mock_query = _build_mock_supabase()
        with patch.object(validated_qa_service, "supabase", mock_client):
            validated_qa_service.get_all_verified_answers(sort="most_used")

        # .gt('thumbs_up_count', 0) should be called at least twice
        # (once for the data query, once for the count query)
        gt_calls = [c.args for c in mock_query.gt.call_args_list]
        thumbs_up_gt_calls = [c for c in gt_calls if c == ("thumbs_up_count", 0)]
        assert len(thumbs_up_gt_calls) >= 2, \
            f"Expected .gt('thumbs_up_count', 0) on both queries, got {gt_calls}"

    def test_search_combines_with_sort_filter(self):
        """Search term must AND with the sort's vote filter."""
        from services import validated_qa_service

        mock_client, mock_query = _build_mock_supabase()
        with patch.object(validated_qa_service, "supabase", mock_client):
            validated_qa_service.get_all_verified_answers(
                sort="most_problematic", search="backup"
            )

        gt_calls = [c.args for c in mock_query.gt.call_args_list]
        ilike_calls = [c.args for c in mock_query.ilike.call_args_list]

        assert ("thumbs_down_count", 0) in gt_calls
        assert any("backup" in str(a) for a in ilike_calls), \
            f"Expected ilike with 'backup', got {ilike_calls}"

    def test_unknown_sort_raises_value_error(self):
        from services import validated_qa_service

        mock_client, _ = _build_mock_supabase()
        with patch.object(validated_qa_service, "supabase", mock_client):
            with pytest.raises(ValueError, match="Invalid sort"):
                validated_qa_service.get_all_verified_answers(sort="bogus")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && pytest tests/test_verified_sort.py -v`
Expected: All six tests FAIL because `sort` parameter doesn't exist yet (TypeError: unexpected keyword argument 'sort').

- [ ] **Step 3: Implement the sort branching**

Replace the existing `get_all_verified_answers` function body at [backend/services/validated_qa_service.py:360-381](backend/services/validated_qa_service.py#L360-L381) with:

```python
_ALLOWED_SORTS = {"recent", "most_used", "most_problematic"}


def get_all_verified_answers(
    search: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    sort: str = "recent",
) -> dict:
    if sort not in _ALLOWED_SORTS:
        raise ValueError(f"Invalid sort: {sort}")

    columns = (
        "id, question_text, validated_answer, equipment_type, fault_code, "
        "validated_by, validated_at, thumbs_up_count, thumbs_down_count, "
        "is_reflagged, updated_at"
    )
    query = supabase.table("validated_qa").select(columns)
    count_query = supabase.table("validated_qa").select("id", count="exact")

    # Apply vote-count filter based on sort
    if sort == "most_used":
        query = query.gt("thumbs_up_count", 0)
        count_query = count_query.gt("thumbs_up_count", 0)
    elif sort == "most_problematic":
        query = query.gt("thumbs_down_count", 0)
        count_query = count_query.gt("thumbs_down_count", 0)

    # Apply search filter (ANDed with sort filter)
    if search:
        query = query.ilike("question_text", f"%{search}%")
        count_query = count_query.ilike("question_text", f"%{search}%")

    # Apply ordering
    if sort == "most_used":
        query = query.order("thumbs_up_count", desc=True).order(
            "updated_at", desc=True
        )
    elif sort == "most_problematic":
        query = query.order("thumbs_down_count", desc=True).order(
            "updated_at", desc=True
        )
    else:  # recent
        query = query.order("updated_at", desc=True)

    data = query.range(offset, offset + limit - 1).execute().data
    count = count_query.execute().count

    return {"items": data, "count": count}
```

Keep the existing `_ALLOWED_SORTS` constant near the top of the module (just below the `REFLAG_*` constants) — do not define it inside the function.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && pytest tests/test_verified_sort.py -v`
Expected: All six tests PASS.

- [ ] **Step 5: Run existing test suite for regression**

Run: `cd backend && pytest tests/test_validated_qa_lookup.py -v`
Expected: All existing tests still PASS (this file does not test `get_all_verified_answers`, so this is a sanity check that imports still work).

- [ ] **Step 6: Commit**

```bash
git add backend/services/validated_qa_service.py backend/tests/test_verified_sort.py
git commit -m "feat(081): add sort parameter to get_all_verified_answers"
```

---

### Task 2: Backend — Route validation

**Files:**
- Modify: [backend/routers/manuals.py:1037-1052](backend/routers/manuals.py#L1037-L1052)
- Test: [backend/tests/test_verified_sort.py](backend/tests/test_verified_sort.py) (append to existing file)

- [ ] **Step 1: Add route-level tests**

Append to `backend/tests/test_verified_sort.py`:

```python
class TestVerifiedAnswersRoute:
    """Route-layer tests for /manuals/verified-answers sort validation."""

    @pytest.mark.asyncio
    async def test_invalid_sort_returns_400(self):
        """Route must reject unrecognized sort values with HTTP 400."""
        from fastapi.testclient import TestClient
        from app import app  # adjust if FastAPI app is created elsewhere

        # Patch admin check and the service
        with patch(
            "routers.manuals._admin_check", return_value=None
        ), patch(
            "routers.manuals.validated_qa_service.get_all_verified_answers"
        ) as mock_get:
            mock_get.return_value = {"items": [], "count": 0}
            client = TestClient(app)
            resp = client.get(
                "/manuals/verified-answers",
                params={"user_email": "admin@test.com", "sort": "bogus"},
            )

        assert resp.status_code == 400
        assert resp.json()["detail"]["error"] == "invalid_sort"
        # The service should NOT have been called for an invalid sort
        mock_get.assert_not_called()

    @pytest.mark.asyncio
    async def test_valid_sort_reaches_service(self):
        from fastapi.testclient import TestClient
        from app import app

        with patch(
            "routers.manuals._admin_check", return_value=None
        ), patch(
            "routers.manuals.validated_qa_service.get_all_verified_answers"
        ) as mock_get:
            mock_get.return_value = {"items": [], "count": 0}
            client = TestClient(app)
            resp = client.get(
                "/manuals/verified-answers",
                params={"user_email": "admin@test.com", "sort": "most_used"},
            )

        assert resp.status_code == 200
        mock_get.assert_called_once()
        assert mock_get.call_args.kwargs.get("sort") == "most_used"

    @pytest.mark.asyncio
    async def test_default_sort_is_recent(self):
        """Omitting the sort param defaults to 'recent'."""
        from fastapi.testclient import TestClient
        from app import app

        with patch(
            "routers.manuals._admin_check", return_value=None
        ), patch(
            "routers.manuals.validated_qa_service.get_all_verified_answers"
        ) as mock_get:
            mock_get.return_value = {"items": [], "count": 0}
            client = TestClient(app)
            resp = client.get(
                "/manuals/verified-answers",
                params={"user_email": "admin@test.com"},
            )

        assert resp.status_code == 200
        assert mock_get.call_args.kwargs.get("sort") == "recent"
```

> **Note on imports:** If `from app import app` fails, find the FastAPI app instance (likely `main.py` or `backend/main.py`) and adjust the import. Check with `grep -rn 'FastAPI()' backend/ --include='*.py'`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && pytest tests/test_verified_sort.py::TestVerifiedAnswersRoute -v`
Expected: All three tests FAIL — the route does not yet accept a `sort` param, so either the call passes through without validation, or a 500 is returned.

- [ ] **Step 3: Add sort param and validation to the route**

Modify [backend/routers/manuals.py:1037-1052](backend/routers/manuals.py#L1037-L1052) to:

```python
_ALLOWED_VERIFIED_SORTS = {"recent", "most_used", "most_problematic"}


@router.get("/manuals/verified-answers")
async def get_verified_answers(
    user_email: str = Query(...),
    search: Optional[str] = Query(None),
    limit: int = Query(50),
    offset: int = Query(0),
    sort: str = Query("recent"),
):
    _admin_check(user_email)

    if sort not in _ALLOWED_VERIFIED_SORTS:
        raise HTTPException(
            status_code=400,
            detail={"error": "invalid_sort", "allowed": sorted(_ALLOWED_VERIFIED_SORTS)},
        )

    try:
        result = validated_qa_service.get_all_verified_answers(
            search=search, limit=limit, offset=offset, sort=sort
        )
        return result
    except Exception:
        raise HTTPException(status_code=500, detail={"error": "fetch_failed"})
```

Place `_ALLOWED_VERIFIED_SORTS` near the top of `manuals.py` among the other module-level constants (check existing placement of `_admin_check` and similar).

- [ ] **Step 4: Run route tests**

Run: `cd backend && pytest tests/test_verified_sort.py -v`
Expected: All nine tests PASS (six service + three route).

- [ ] **Step 5: Commit**

```bash
git add backend/routers/manuals.py backend/tests/test_verified_sort.py
git commit -m "feat(081): add sort query param to /manuals/verified-answers with 400 on invalid"
```

---

### Task 3: Frontend — Service-layer `sort` parameter

**Files:**
- Modify: `frontend/lib/services/manual_assistant_service.dart` — `getVerifiedAnswers()` method

- [ ] **Step 1: Locate the method**

Run: `grep -n 'getVerifiedAnswers' frontend/lib/services/manual_assistant_service.dart`
Expected: A single match at the method definition. Read the method body to understand the current signature (it builds a URL with `search`, `limit`, `offset`).

- [ ] **Step 2: Add the `sort` parameter**

Change the signature from:

```dart
Future<Map<String, dynamic>> getVerifiedAnswers({
  required String userEmail,
  String? search,
  int limit = 50,
  int offset = 0,
}) async {
```

to:

```dart
Future<Map<String, dynamic>> getVerifiedAnswers({
  required String userEmail,
  String? search,
  int limit = 50,
  int offset = 0,
  String sort = 'recent',
}) async {
```

And in the URL-building block, append `&sort=${Uri.encodeComponent(sort)}` to the query string. The exact edit depends on how the existing URL is built — if it uses string concatenation, add it at the end of the query-string segment. If it uses `Uri.parse` with a map, add `'sort': sort` to the map.

**Concrete edit pattern** (adapt to the existing code style):

```dart
// OLD (approximate):
final uri = Uri.parse(
  '${AppConfig.baseUrl}/manuals/verified-answers'
  '?user_email=${Uri.encodeComponent(userEmail)}'
  '&limit=$limit&offset=$offset'
  '${search != null ? "&search=${Uri.encodeComponent(search)}" : ""}',
);

// NEW:
final uri = Uri.parse(
  '${AppConfig.baseUrl}/manuals/verified-answers'
  '?user_email=${Uri.encodeComponent(userEmail)}'
  '&limit=$limit&offset=$offset'
  '&sort=${Uri.encodeComponent(sort)}'
  '${search != null ? "&search=${Uri.encodeComponent(search)}" : ""}',
);
```

- [ ] **Step 3: Verify the Dart analyzer passes**

Run: `cd frontend && flutter analyze lib/services/manual_assistant_service.dart`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/services/manual_assistant_service.dart
git commit -m "feat(081): add sort parameter to ManualAssistantService.getVerifiedAnswers"
```

---

### Task 4: Frontend — Sort dropdown on Verified tab

**Files:**
- Modify: [frontend/lib/screens/manual_assistant/verified_answers_tab.dart](frontend/lib/screens/manual_assistant/verified_answers_tab.dart)

- [ ] **Step 1: Add `_sort` state field**

In the `_VerifiedAnswersTabState` class (after the `_offset = 0; final int _limit = 50;` line around L26-L27), add:

```dart
String _sort = 'recent';
```

- [ ] **Step 2: Pass `_sort` to `_loadEntries`**

In `_loadEntries` (L57-L96), update the service call:

```dart
final result = await _service.getVerifiedAnswers(
  userEmail: widget.userEmail,
  search: searchQuery,
  limit: _limit,
  offset: append ? _offset : 0,
  sort: _sort,  // ADD THIS
);
```

- [ ] **Step 3: Add the dropdown to the UI**

In the `build()` method, just after the search-field `Padding` block (around L388, before the total-count `Container`), insert a dropdown row. The simplest placement is a new `Padding` containing a `Row` with a label and the dropdown:

```dart
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
  child: Row(
    children: [
      const Text('Sort:', style: TextStyle(fontSize: 13)),
      const SizedBox(width: 8),
      DropdownButton<String>(
        value: _sort,
        isDense: true,
        items: const [
          DropdownMenuItem(value: 'recent', child: Text('Most recent')),
          DropdownMenuItem(value: 'most_used', child: Text('Most used')),
          DropdownMenuItem(
            value: 'most_problematic',
            child: Text('Most problematic'),
          ),
        ],
        onChanged: (value) {
          if (value == null || value == _sort) return;
          setState(() {
            _sort = value;
            _offset = 0;
            _loading = true;
            _entries = [];
            _totalCount = 0;
          });
          _loadEntries();
        },
      ),
    ],
  ),
),
```

- [ ] **Step 4: Update the empty-state text to be sort-aware**

Find the empty-state block at L413-L432. Replace the `Text(...)` inside it:

```dart
Text(
  _searchController.text.isNotEmpty
      ? 'No matching answers found.'
      : (_sort == 'most_used'
          ? 'No verified answers have thumbs-up votes yet.'
          : _sort == 'most_problematic'
              ? 'No verified answers have thumbs-down votes yet.'
              : 'No verified answers yet.'),
  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
  textAlign: TextAlign.center,
),
```

Note: the search condition takes precedence, so if an admin is searching within a sort, they see the "no matches" message rather than the sort-specific one.

- [ ] **Step 5: Run flutter analyze**

Run: `cd frontend && flutter analyze lib/screens/manual_assistant/verified_answers_tab.dart`
Expected: No errors.

- [ ] **Step 6: Manual smoke test**

Run the Flutter app against a backend with at least one `validated_qa` row that has `thumbs_up_count > 0` and at least one with `thumbs_down_count > 0`.

- Open the Verified tab → list shows all entries ordered by `updated_at DESC` (unchanged behavior).
- Change sort to "Most used" → list re-orders by thumbs_up_count desc; entries with zero thumbs-up are hidden; count badge reflects filtered total.
- Change sort to "Most problematic" → list shows only entries with thumbs_down_count > 0, ordered by thumbs_down_count desc.
- Change sort with a search term active → both filters ANDed.
- Change sort back to "Most recent" → full list returns, byte-identical to original.

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/screens/manual_assistant/verified_answers_tab.dart
git commit -m "feat(081): add sort dropdown to Verified tab (recent/most_used/most_problematic)"
```

---

### Task 5: Version bump

**Files:**
- Modify: `frontend/pubspec.yaml` — version string

- [ ] **Step 1: Bump version**

Find the `version:` line in `frontend/pubspec.yaml`. The current scheme based on recent commits (`v1.17.9+194`) is `<semver>+<build>`. Bump the build number by one and the patch by one:

```yaml
version: 1.17.10+195   # adjust based on current value
```

Run: `grep '^version:' frontend/pubspec.yaml` first to see the actual current value, then bump.

- [ ] **Step 2: Commit**

```bash
git add frontend/pubspec.yaml
git commit -m "bump version to v1.17.10+195"
```

---

### Task 6: Deploy verification (manual, post-merge)

**No code changes — reference task only.**

After this spec is merged to main and deployed to the Zorin server, verify:

- [ ] Backend responds correctly to `curl -s 'https://zorin.taila92fe8.ts.net/manuals/verified-answers?user_email=<admin>&sort=most_used' | jq .count` — returns a number, and the number matches the count shown in the UI's Verified tab when sorted the same way.
- [ ] `curl -s -o /dev/null -w '%{http_code}\n' 'https://zorin.taila92fe8.ts.net/manuals/verified-answers?user_email=<admin>&sort=bogus'` returns `400`.
- [ ] Admin opens the deployed PWA, changes sort modes, and each mode shows the expected subset.

---

## Self-Review

**1. Spec coverage:**

| Spec FR | Task coverage |
|---|---|
| FR-001 (dropdown with 3 options) | Task 4 step 3 |
| FR-002 (recent = updated_at DESC, no filter) | Task 1 service logic + test `test_default_recent_sort_has_no_vote_filter` |
| FR-003 (most_used filter + order) | Task 1 test `test_most_used_filters_and_orders_by_thumbs_up` |
| FR-004 (most_problematic filter + order) | Task 1 test `test_most_problematic_filters_and_orders_by_thumbs_down` |
| FR-005 (search AND sort) | Task 1 test `test_search_combines_with_sort_filter` |
| FR-006 (sort change resets offset) | Task 4 step 3 onChanged handler |
| FR-007 (count reflects filtered total) | Task 1 test `test_count_query_uses_same_filter_as_data_query` |
| FR-008 (sort-specific empty states) | Task 4 step 4 |
| FR-009 (route 400 on invalid sort) | Task 2 test `test_invalid_sort_returns_400` |
| FR-010 (cards unchanged) | No task — explicit non-change |
| NFR-001 (no schema changes) | No migration task exists — explicit |
| NFR-002 (no new endpoints) | Task 2 extends existing endpoint |
| NFR-003 (server-side filter) | Task 1 implementation |
| NFR-004 (count matches filter) | Task 1 test `test_count_query_uses_same_filter_as_data_query` |

All FRs and NFRs covered.

**2. Placeholder scan:** No "TBD", "TODO", "handle edge cases", or other placeholder phrases. Every code-producing step contains runnable code.

**3. Type consistency:**
- `_ALLOWED_SORTS` (service) vs `_ALLOWED_VERIFIED_SORTS` (route) — intentionally different names because they live in different modules; both have identical string contents.
- `sort` is consistently a `str` in Python, `String` in Dart, with the same three allowed values (`recent`, `most_used`, `most_problematic`) everywhere.
- Return shape `{"items": [...], "count": N}` preserved from the existing function.

No inconsistencies found.
