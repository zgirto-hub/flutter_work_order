"""
Contract tests for bulk delete (spec 082).

Tests validated_qa_service.bulk_delete_ratings_by_qa() and the
POST /manuals/ratings/bulk-delete endpoint.
Patches the local supabase reference in each module since they use
"from db import supabase".
"""

import pytest
from unittest.mock import MagicMock, patch
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "backend"))

import services.validated_qa_service as vqa_svc
import routers.manuals as m_router


class MockResponse:
    """Simple mock response that mimics a Supabase API response with .data."""
    def __init__(self, data):
        self.data = data


class TestBulkDeleteService:
    """Unit tests for validated_qa_service.bulk_delete_ratings_by_qa()."""

    def test_deletes_matching_ratings_and_returns_count(self):
        data = [{"id": "r1"}, {"id": "r2"}, {"id": "r3"}]

        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.eq.return_value.execute.return_value = MockResponse(data)
        mock_table.update.return_value.in_.return_value.execute.return_value = MockResponse(None)
        mock_table.delete.return_value.in_.return_value.execute.return_value = MockResponse(None)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(vqa_svc, "supabase", mock_db):
            result = vqa_svc.bulk_delete_ratings_by_qa("Test question?", "Test answer.")

        assert result == 3
        mock_table.delete.return_value.in_.return_value.execute.assert_called()

    def test_returns_zero_when_no_match(self):
        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.eq.return_value.execute.return_value = MockResponse([])

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(vqa_svc, "supabase", mock_db):
            result = vqa_svc.bulk_delete_ratings_by_qa("Non-existent question?", "Non-existent answer.")

        assert result == 0
        mock_table.update.return_value.in_.return_value.execute.assert_not_called()
        mock_table.delete.return_value.in_.return_value.execute.assert_not_called()

    def test_orphan_step_runs_before_delete(self):
        data = [{"id": "r1"}]

        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.eq.return_value.execute.return_value = MockResponse(data)
        mock_table.update.return_value.in_.return_value.execute.return_value = MockResponse(None)
        mock_table.delete.return_value.in_.return_value.execute.return_value = MockResponse(None)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(vqa_svc, "supabase", mock_db):
            vqa_svc.bulk_delete_ratings_by_qa("Q", "A")

        method_calls = mock_table.method_calls
        call_strings = [str(c) for c in method_calls]
        update_idx = next((i for i, s in enumerate(call_strings) if ".update(" in s), None)
        delete_idx = next((i for i, s in enumerate(call_strings) if ".delete()" in s), None)
        assert update_idx is not None, f"update call not found in {call_strings}"
        assert delete_idx is not None, f"delete call not found in {call_strings}"
        assert update_idx < delete_idx, f"orphan must run before delete: update={update_idx}, delete={delete_idx}"

    def test_does_not_call_update_when_ids_empty(self):
        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.eq.return_value.execute.return_value = MockResponse([])

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(vqa_svc, "supabase", mock_db):
            vqa_svc.bulk_delete_ratings_by_qa("Q", "A")

        mock_table.update.return_value.in_.return_value.execute.assert_not_called()
        mock_table.delete.return_value.in_.return_value.execute.assert_not_called()


class TestBulkDeleteEndpoint:
    """Tests for POST /manuals/ratings/bulk-delete."""

    @pytest.mark.asyncio
    async def test_admin_delete_logs_activity(self):
        data = [{"id": "r1"}]

        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.eq.return_value.execute.return_value = MockResponse(data)
        mock_table.update.return_value.in_.return_value.execute.return_value = MockResponse(None)
        mock_table.delete.return_value.in_.return_value.execute.return_value = MockResponse(None)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        from routers.manuals import bulk_delete_ratings, BulkDeleteRatingsRequest

        with patch.object(m_router, "supabase", mock_db):
            with patch.object(m_router, "_admin_check"):
                with patch.object(m_router, "log_activity") as mock_log:
                    with patch.object(vqa_svc, "supabase", mock_db):
                        req = BulkDeleteRatingsRequest(
                            question_text="Test question?",
                            answer_text="Test answer.",
                        )
                        result = await m_router.bulk_delete_ratings(req, "salah@admin.com")

        assert result == {"deleted_count": 1}
        mock_log.assert_called_once()
        assert mock_log.call_args[0][2] == "admin_bulk_deleted_ratings"
        detail = mock_log.call_args[1]["detail"]
        assert "count=1" in detail

    @pytest.mark.asyncio
    async def test_bulk_delete_returns_zero_when_no_match(self):
        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.eq.return_value.execute.return_value = MockResponse([])

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        from routers.manuals import bulk_delete_ratings, BulkDeleteRatingsRequest

        with patch.object(m_router, "supabase", mock_db):
            with patch.object(m_router, "_admin_check"):
                with patch.object(m_router, "log_activity") as mock_log:
                    with patch.object(vqa_svc, "supabase", mock_db):
                        req = BulkDeleteRatingsRequest(
                            question_text="Non-existent question?",
                            answer_text="Non-existent answer.",
                        )
                        result = await m_router.bulk_delete_ratings(req, "salah@admin.com")

        assert result == {"deleted_count": 0}
        mock_log.assert_called_once()
        detail = mock_log.call_args[1]["detail"]
        assert "count=0" in detail

    @pytest.mark.asyncio
    async def test_non_admin_raises(self):
        mock_db = MagicMock()

        from routers.manuals import bulk_delete_ratings, BulkDeleteRatingsRequest

        with patch.object(m_router, "supabase", mock_db):
            with patch.object(m_router, "_admin_check") as mock_admin:
                mock_admin.side_effect = Exception("not admin")
                req = BulkDeleteRatingsRequest(
                    question_text="Test question?",
                    answer_text="Test answer.",
                )

                with pytest.raises(Exception):
                    await m_router.bulk_delete_ratings(req, "tech@example.com")

    @pytest.mark.asyncio
    async def test_bulk_delete_return_structure(self):
        data = [{"id": str(i)} for i in range(12)]

        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.eq.return_value.execute.return_value = MockResponse(data)
        mock_table.update.return_value.in_.return_value.execute.return_value = MockResponse(None)
        mock_table.delete.return_value.in_.return_value.execute.return_value = MockResponse(None)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        from routers.manuals import bulk_delete_ratings, BulkDeleteRatingsRequest

        with patch.object(m_router, "supabase", mock_db):
            with patch.object(m_router, "_admin_check"):
                with patch.object(m_router, "log_activity"):
                    with patch.object(vqa_svc, "supabase", mock_db):
                        req = BulkDeleteRatingsRequest(
                            question_text="Q", answer_text="A"
                        )
                        result = await m_router.bulk_delete_ratings(req, "salah@admin.com")

        assert "deleted_count" in result
        assert isinstance(result["deleted_count"], int)
        assert result["deleted_count"] == 12