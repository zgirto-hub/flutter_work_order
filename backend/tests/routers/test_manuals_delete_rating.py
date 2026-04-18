"""
Contract tests for DELETE /manuals/ratings/{rating_id} (spec 082).

Tests validated_qa_service.delete_rating() and the router-level authorization
logic. Patches the local supabase reference in each module since they use
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


class TestDeleteRatingService:
    """Unit tests for validated_qa_service.delete_rating()."""

    def test_deletes_answer_ratings_row_after_nulling_validated_qa(self):
        rating_id = "11111111-1111-1111-1111-111111111111"
        row_data = {
            "id": rating_id,
            "question_text": "How do I restart AIDA NG?",
            "rating": "negative",
            "rater_email": "tech@example.com",
        }

        mock_table = MagicMock()
        mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)
        mock_table.delete.return_value.eq.return_value.execute.return_value = MockResponse(None)
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row_data)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(vqa_svc, "supabase", mock_db):
            result = vqa_svc.delete_rating(rating_id)

        assert result["existed"] is True
        assert result["question_text"] == "How do I restart AIDA NG?"
        assert result["rating"] == "negative"
        assert result["rater_email"] == "tech@example.com"
        mock_table.update.return_value.eq.return_value.execute.assert_called()
        mock_table.delete.return_value.eq.return_value.execute.assert_called()

    def test_returns_existed_false_when_row_not_found(self):
        rating_id = "22222222-2222-2222-2222-222222222222"

        mock_table = MagicMock()
        mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(None)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(vqa_svc, "supabase", mock_db):
            result = vqa_svc.delete_rating(rating_id)

        assert result["existed"] is False
        assert result["question_text"] is None
        mock_table.delete.return_value.eq.return_value.execute.assert_not_called()

    def test_nulls_validated_qa_regardless_of_whether_rows_exist(self):
        rating_id = "33333333-3333-3333-3333-333333333333"
        row_data = {
            "id": rating_id,
            "question_text": "Test question",
            "rating": "positive",
            "rater_email": "tech@example.com",
        }

        mock_table = MagicMock()
        mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)
        mock_table.delete.return_value.eq.return_value.execute.return_value = MockResponse(None)
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row_data)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(vqa_svc, "supabase", mock_db):
            vqa_svc.delete_rating(rating_id)

        mock_table.update.return_value.eq.return_value.execute.assert_called()


class TestDeleteRatingAuthorization:
    """Tests for the DELETE /manuals/ratings/{rating_id} authorization logic."""

    def _make_row(self, overrides=None):
        base = {
            "id": "44444444-4444-4444-4444-444444444444",
            "rater_email": "tech@example.com",
            "question_text": "How do I restart AIDA NG?",
            "rating": "negative",
        }
        if overrides:
            base.update(overrides)
        return base

    @pytest.mark.asyncio
    async def test_rater_can_delete_own_rating(self):
        row = self._make_row()
        mock_table = MagicMock()
        mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)
        mock_table.delete.return_value.eq.return_value.execute.return_value = MockResponse(None)
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(m_router, "supabase", mock_db):
            with patch.object(m_router, "_admin_check") as mock_admin:
                with patch.object(m_router, "log_activity"):
                    with patch.object(vqa_svc, "supabase", mock_db):
                        result = await m_router.delete_rating("44444444-4444-4444-4444-444444444444", "tech@example.com")

        assert result == {"status": "deleted", "existed": True}
        mock_admin.assert_not_called()

    @pytest.mark.asyncio
    async def test_admin_can_delete_someone_else(self):
        row = self._make_row({"rater_email": "tech@example.com"})
        mock_table = MagicMock()
        mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)
        mock_table.delete.return_value.eq.return_value.execute.return_value = MockResponse(None)
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(m_router, "supabase", mock_db):
            with patch.object(m_router, "_admin_check") as mock_admin:
                with patch.object(m_router, "log_activity"):
                    with patch.object(vqa_svc, "supabase", mock_db):
                        result = await m_router.delete_rating("44444444-4444-4444-4444-444444444444", "salah@admin.com")

        assert result == {"status": "deleted", "existed": True}

    @pytest.mark.asyncio
    async def test_non_rater_non_admin_raises(self):
        row = self._make_row({"rater_email": "tech@example.com"})
        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(m_router, "supabase", mock_db):
            with patch.object(m_router, "_admin_check") as mock_admin:
                mock_admin.side_effect = Exception("not admin")
                with pytest.raises(Exception):
                    await m_router.delete_rating("44444444-4444-4444-4444-444444444444", "other@example.com")

    @pytest.mark.asyncio
    async def test_missing_row_treated_as_success_no_auth(self):
        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(None)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(m_router, "supabase", mock_db):
            with patch.object(m_router, "_admin_check") as mock_admin:
                with patch.object(m_router, "log_activity"):
                    result = await m_router.delete_rating("44444444-4444-4444-4444-444444444444", "any@example.com")

        assert result == {"status": "deleted", "existed": False}
        mock_admin.assert_not_called()

    @pytest.mark.asyncio
    async def test_activity_log_unrated_answer_for_self(self):
        row = self._make_row()
        mock_table = MagicMock()
        mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)
        mock_table.delete.return_value.eq.return_value.execute.return_value = MockResponse(None)
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(m_router, "supabase", mock_db):
            with patch.object(m_router, "_admin_check"):
                with patch.object(m_router, "log_activity") as mock_log:
                    with patch.object(vqa_svc, "supabase", mock_db):
                        await m_router.delete_rating("44444444-4444-4444-4444-444444444444", "tech@example.com")

        mock_log.assert_called_once()
        assert mock_log.call_args[0][2] == "unrated_answer"

    @pytest.mark.asyncio
    async def test_activity_log_admin_deleted_rating_for_admin(self):
        row = self._make_row({"rater_email": "tech@example.com"})
        mock_table = MagicMock()
        mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)
        mock_table.delete.return_value.eq.return_value.execute.return_value = MockResponse(None)
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(m_router, "supabase", mock_db):
            with patch.object(m_router, "_admin_check"):
                with patch.object(m_router, "log_activity") as mock_log:
                    with patch.object(vqa_svc, "supabase", mock_db):
                        await m_router.delete_rating("44444444-4444-4444-4444-444444444444", "admin@example.com")

        mock_log.assert_called_once()
        assert mock_log.call_args[0][2] == "admin_deleted_rating"
        assert mock_log.call_args[1]["detail"] == "tech@example.com"

    @pytest.mark.asyncio
    async def test_concurrent_delete_first_existed_true_second_false(self):
        row = self._make_row()
        mock_table = MagicMock()
        mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)
        mock_table.delete.return_value.eq.return_value.execute.return_value = MockResponse(None)
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(m_router, "supabase", mock_db):
            with patch.object(m_router, "_admin_check"):
                with patch.object(m_router, "log_activity"):
                    with patch.object(vqa_svc, "supabase", mock_db):
                        first = await m_router.delete_rating("44444444-4444-4444-4444-444444444444", "tech@example.com")

        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(None)

        with patch.object(m_router, "supabase", mock_db):
            with patch.object(m_router, "_admin_check"):
                with patch.object(m_router, "log_activity"):
                    with patch.object(vqa_svc, "supabase", mock_db):
                        second = await m_router.delete_rating("44444444-4444-4444-4444-444444444444", "salah@admin.com")

        assert first["existed"] is True
        assert second["existed"] is False