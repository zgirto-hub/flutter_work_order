"""
Contract tests for PATCH /manuals/ratings/{rating_id}/feedback (spec 087).

Tests:
- 200 happy path (both fields)
- 200 reason-only (null comment)
- 200 idempotent second call
- 404 when rating_id does not exist
- 403 when user_email != rater_email
- 422 on unknown reason value
- 422 on comment > 2000 chars
- 400 on rating that is positive
- Activity log event emitted on happy path
"""

import pytest
from unittest.mock import MagicMock, patch
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "backend"))

import services.validated_qa_service as vqa_svc
import routers.manuals as m_router


class MockResponse:
    def __init__(self, data):
        self.data = data


class TestUpdateRatingFeedbackService:
    """Unit tests for validated_qa_service.update_rating_feedback()."""

    def _make_row(self, overrides=None):
        base = {
            "id": "11111111-1111-1111-1111-111111111111",
            "question_text": "How do I restart AIDA NG?",
            "answer_text": "Press and hold RESET for 3 seconds.",
            "rating": "negative",
            "rater_email": "tech@example.com",
            "feedback_reason": None,
            "feedback_comment": None,
        }
        if overrides:
            base.update(overrides)
        return base

    def test_happy_path_updates_both_fields(self):
        row = self._make_row()

        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)
        mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(vqa_svc, "supabase", mock_db):
            with patch.object(vqa_svc, "log_activity"):
                result = vqa_svc.update_rating_feedback(
                    rating_id="11111111-1111-1111-1111-111111111111",
                    reason="outdated",
                    comment="The 2022 SOP was superseded.",
                    user_email="tech@example.com",
                )

        assert result["feedback_reason"] == "outdated"
        assert result["feedback_comment"] == "The 2022 SOP was superseded."
        mock_table.update.return_value.eq.return_value.execute.assert_called()

    def test_reason_only_sets_comment_to_null(self):
        row = self._make_row()

        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)
        mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(vqa_svc, "supabase", mock_db):
            with patch.object(vqa_svc, "log_activity"):
                result = vqa_svc.update_rating_feedback(
                    rating_id="11111111-1111-1111-1111-111111111111",
                    reason="inaccurate",
                    comment=None,
                    user_email="tech@example.com",
                )

        assert result["feedback_reason"] == "inaccurate"
        assert result["feedback_comment"] is None

    def test_raises_rating_not_found_when_row_missing(self):
        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(None)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(vqa_svc, "supabase", mock_db):
            with pytest.raises(vqa_svc.RatingNotFound):
                vqa_svc.update_rating_feedback(
                    rating_id="nonexistent-id",
                    reason="outdated",
                    comment=None,
                    user_email="tech@example.com",
                )

    def test_raises_not_owner_when_email_mismatch(self):
        row = self._make_row({"rater_email": "tech@example.com"})

        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(vqa_svc, "supabase", mock_db):
            with pytest.raises(vqa_svc.NotOwner):
                vqa_svc.update_rating_feedback(
                    rating_id="11111111-1111-1111-1111-111111111111",
                    reason="outdated",
                    comment=None,
                    user_email="attacker@example.com",
                )

    def test_raises_not_negative_when_rating_is_positive(self):
        row = self._make_row({"rating": "positive"})

        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(vqa_svc, "supabase", mock_db):
            with pytest.raises(vqa_svc.NotNegativeRating):
                vqa_svc.update_rating_feedback(
                    rating_id="11111111-1111-1111-1111-111111111111",
                    reason="outdated",
                    comment=None,
                    user_email="tech@example.com",
                )

    def test_idempotent_second_call_succeeds(self):
        row = self._make_row({"feedback_reason": "outdated", "feedback_comment": "First comment."})

        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)
        mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(vqa_svc, "supabase", mock_db):
            with patch.object(vqa_svc, "log_activity"):
                result = vqa_svc.update_rating_feedback(
                    rating_id="11111111-1111-1111-1111-111111111111",
                    reason="incomplete",
                    comment="Second comment.",
                    user_email="tech@example.com",
                )

        assert result["feedback_reason"] == "incomplete"
        assert result["feedback_comment"] == "Second comment."

    def test_activity_log_emitted_on_success(self):
        row = self._make_row()

        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)
        mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(vqa_svc, "supabase", mock_db):
            with patch.object(vqa_svc, "log_activity") as mock_log:
                vqa_svc.update_rating_feedback(
                    rating_id="11111111-1111-1111-1111-111111111111",
                    reason="outdated",
                    comment="Test comment.",
                    user_email="tech@example.com",
                )

        mock_log.assert_called_once()
        call = mock_log.call_args
        assert call[0][2] == "rated_answer_feedback"
        assert call[1]["detail"] == "outdated"


class TestPatchRatingFeedbackEndpoint:
    """Tests for PATCH /manuals/ratings/{rating_id}/feedback endpoint."""

    def _make_row(self, overrides=None):
        base = {
            "id": "11111111-1111-1111-1111-111111111111",
            "question_text": "How do I restart AIDA NG?",
            "answer_text": "Press and hold RESET.",
            "rating": "negative",
            "rater_email": "tech@example.com",
            "feedback_reason": None,
            "feedback_comment": None,
        }
        if overrides:
            base.update(overrides)
        return base

    @pytest.mark.asyncio
    async def test_200_happy_path(self):
        row = self._make_row()

        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)
        mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(m_router, "supabase", mock_db):
            with patch.object(vqa_svc, "supabase", mock_db):
                with patch.object(vqa_svc, "log_activity"):
                    from routers.manuals import RatingFeedbackRequest
                    req = RatingFeedbackRequest(
                        feedback_reason="outdated",
                        feedback_comment="The panel was re-commissioned.",
                        user_email="tech@example.com",
                    )
                    result = await m_router.patch_rating_feedback(
                        "11111111-1111-1111-1111-111111111111", req
                    )

        assert result["status"] == "saved"
        assert result["feedback_reason"] == "outdated"
        assert result["feedback_comment"] == "The panel was re-commissioned."

    @pytest.mark.asyncio
    async def test_200_reason_only_null_comment(self):
        row = self._make_row()

        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)
        mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(m_router, "supabase", mock_db):
            with patch.object(vqa_svc, "supabase", mock_db):
                with patch.object(vqa_svc, "log_activity"):
                    from routers.manuals import RatingFeedbackRequest
                    req = RatingFeedbackRequest(
                        feedback_reason="incomplete",
                        feedback_comment=None,
                        user_email="tech@example.com",
                    )
                    result = await m_router.patch_rating_feedback(
                        "11111111-1111-1111-1111-111111111111", req
                    )

        assert result["status"] == "saved"
        assert result["feedback_reason"] == "incomplete"
        assert result["feedback_comment"] is None

    @pytest.mark.asyncio
    async def test_404_when_rating_not_found(self):
        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(None)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        from fastapi import HTTPException
        with patch.object(m_router, "supabase", mock_db):
            with patch.object(vqa_svc, "supabase", mock_db):
                from routers.manuals import RatingFeedbackRequest
                req = RatingFeedbackRequest(
                    feedback_reason="outdated",
                    feedback_comment=None,
                    user_email="tech@example.com",
                )
                with pytest.raises(HTTPException) as exc_info:
                    await m_router.patch_rating_feedback("nonexistent-id", req)
                assert exc_info.value.status_code == 404

    @pytest.mark.asyncio
    async def test_403_when_not_owner(self):
        row = self._make_row({"rater_email": "tech@example.com"})

        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        from fastapi import HTTPException
        with patch.object(m_router, "supabase", mock_db):
            with patch.object(vqa_svc, "supabase", mock_db):
                from routers.manuals import RatingFeedbackRequest
                req = RatingFeedbackRequest(
                    feedback_reason="outdated",
                    feedback_comment=None,
                    user_email="attacker@example.com",
                )
                with pytest.raises(HTTPException) as exc_info:
                    await m_router.patch_rating_feedback("11111111-1111-1111-1111-111111111111", req)
                assert exc_info.value.status_code == 403

    @pytest.mark.asyncio
    async def test_400_when_rating_positive(self):
        row = self._make_row({"rating": "positive"})

        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        from fastapi import HTTPException
        with patch.object(m_router, "supabase", mock_db):
            with patch.object(vqa_svc, "supabase", mock_db):
                from routers.manuals import RatingFeedbackRequest
                req = RatingFeedbackRequest(
                    feedback_reason="outdated",
                    feedback_comment=None,
                    user_email="tech@example.com",
                )
                with pytest.raises(HTTPException) as exc_info:
                    await m_router.patch_rating_feedback("11111111-1111-1111-1111-111111111111", req)
                assert exc_info.value.status_code == 400

    @pytest.mark.asyncio
    async def test_422_on_unknown_reason(self):
        from pydantic import ValidationError
        from routers.manuals import RatingFeedbackRequest
        with pytest.raises(ValidationError):
            RatingFeedbackRequest(
                feedback_reason="wharrgarbl",
                feedback_comment=None,
                user_email="tech@example.com",
            )

    @pytest.mark.asyncio
    async def test_422_on_comment_over_2000_chars(self):
        from pydantic import ValidationError
        from routers.manuals import RatingFeedbackRequest
        with pytest.raises(ValidationError):
            RatingFeedbackRequest(
                feedback_reason="unclear",
                feedback_comment="x" * 2001,
                user_email="tech@example.com",
            )

    @pytest.mark.asyncio
    async def test_activity_log_on_happy_path(self):
        row = self._make_row()

        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)
        mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(m_router, "supabase", mock_db):
            with patch.object(vqa_svc, "supabase", mock_db):
                with patch.object(vqa_svc, "log_activity") as mock_svc_log:
                    from routers.manuals import RatingFeedbackRequest
                    req = RatingFeedbackRequest(
                        feedback_reason="outdated",
                        feedback_comment="Test.",
                        user_email="tech@example.com",
                    )
                    await m_router.patch_rating_feedback("11111111-1111-1111-1111-111111111111", req)

        mock_svc_log.assert_called_once()
        assert mock_svc_log.call_args[0][2] == "rated_answer_feedback"

    @pytest.mark.asyncio
    async def test_idempotent_second_call(self):
        row = self._make_row({"feedback_reason": "outdated", "feedback_comment": "First."})

        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)
        mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(m_router, "supabase", mock_db):
            with patch.object(vqa_svc, "supabase", mock_db):
                with patch.object(vqa_svc, "log_activity"):
                    from routers.manuals import RatingFeedbackRequest
                    req = RatingFeedbackRequest(
                        feedback_reason="incomplete",
                        feedback_comment="Second.",
                        user_email="tech@example.com",
                    )
                    result = await m_router.patch_rating_feedback("11111111-1111-1111-1111-111111111111", req)

        assert result["status"] == "saved"
        assert result["feedback_reason"] == "incomplete"
        assert result["feedback_comment"] == "Second."


class TestDismissalPath:
    """Tests for US2: negative rating without PATCH leaves NULL reason/comment."""

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


class TestUnrateCleanup:
    """Tests for US3: DELETE /manuals/ratings/{id} removes rating with reason/comment."""

    @pytest.mark.asyncio
    async def test_delete_removes_rating_with_feedback(self):
        rating_id = "11111111-1111-1111-1111-111111111111"
        row = {
            "id": rating_id,
            "question_text": "How do I restart AIDA NG?",
            "answer_text": "Press RESET.",
            "rating": "negative",
            "rater_email": "tech@example.com",
            "feedback_reason": "outdated",
            "feedback_comment": "Test comment.",
        }

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
                        result = await m_router.delete_rating(rating_id, "tech@example.com")

        assert result["status"] == "deleted"
        assert result["existed"] is True
        mock_table.delete.return_value.eq.return_value.execute.assert_called()
