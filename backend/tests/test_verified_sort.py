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


class TestVerifiedAnswersRoute:
    """Route-layer tests for /manuals/verified-answers sort validation."""

    @pytest.mark.asyncio
    async def test_invalid_sort_returns_400(self):
        """Route must reject unrecognized sort values with HTTP 400."""
        from fastapi.testclient import TestClient
        from fastapi import FastAPI
        from routers.manuals import router as manuals_router

        app = FastAPI()
        app.include_router(manuals_router)

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
        mock_get.assert_not_called()

    @pytest.mark.asyncio
    async def test_valid_sort_reaches_service(self):
        from fastapi.testclient import TestClient
        from fastapi import FastAPI
        from routers.manuals import router as manuals_router

        app = FastAPI()
        app.include_router(manuals_router)

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
        from fastapi import FastAPI
        from routers.manuals import router as manuals_router

        app = FastAPI()
        app.include_router(manuals_router)

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