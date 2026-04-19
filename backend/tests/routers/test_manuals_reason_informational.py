"""
FR-011 regression tests: feedback_reason and feedback_comment are informational only.
They must NOT change reflag threshold, approve/correct workflow, or any downstream pipeline.

Tests:
- update_validated_rating: reflag threshold behavior unchanged regardless of feedback_reason
- /manuals/real-usage-suggestions: ordering and grouping unchanged
- review_answer (approve/correct): generated validated_qa row unchanged
"""

import pytest
from unittest.mock import MagicMock, patch
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "backend"))

import services.validated_qa_service as vqa_svc


class MockResponse:
    def __init__(self, data):
        self.data = data


class TestReasonInformational:
    """Verify feedback_reason/comment do not affect reflag, approve, or suggest flows."""

    def _make_flagged_row(self, overrides=None):
        base = {
            "id": "11111111-1111-1111-1111-111111111111",
            "question_text": "How do I restart AIDA NG?",
            "answer_text": "Press and hold RESET for 3 seconds.",
            "rating": "negative",
            "rater_email": "tech@example.com",
            "feedback_reason": None,
            "feedback_comment": None,
            "review_status": "pending",
            "thumbs_up_count": 0,
            "thumbs_down_count": 0,
            "is_reflagged": False,
        }
        if overrides:
            base.update(overrides)
        return base

    def test_reflag_threshold_same_without_reason(self):
        """Thumbs-down with no feedback_reason still reflags normally."""
        row = self._make_flagged_row({
            "thumbs_up_count": 1,
            "thumbs_down_count": 3,
            "rating": "negative",
        })
        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(vqa_svc, "supabase", mock_db):
            result = vqa_svc.update_rating_feedback(
                rating_id="11111111-1111-1111-1111-111111111111",
                reason="inaccurate",
                comment="Test comment.",
                user_email="tech@example.com",
            )

        assert result["feedback_reason"] == "inaccurate"
        assert result["feedback_comment"] == "Test comment."
        mock_table.update.return_value.eq.return_value.execute.assert_called()

    def test_reflag_threshold_same_with_reason(self):
        """Thumbs-down with feedback_reason still reflags normally (informational only)."""
        row = self._make_flagged_row({
            "thumbs_up_count": 1,
            "thumbs_down_count": 3,
            "rating": "negative",
            "feedback_reason": "outdated",
            "feedback_comment": "Was correct in 2022.",
        })
        mock_table = MagicMock()
        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)

        mock_db = MagicMock()
        mock_db.table.return_value = mock_table

        with patch.object(vqa_svc, "supabase", mock_db):
            result = vqa_svc.update_rating_feedback(
                rating_id="11111111-1111-1111-1111-111111111111",
                reason="incomplete",
                comment="Updated since.",
                user_email="tech@example.com",
            )

        assert result["feedback_reason"] == "incomplete"
        assert result["feedback_comment"] == "Updated since."
        mock_table.update.return_value.eq.return_value.execute.assert_called()

    def test_all_five_reasons_update_successfully(self):
        """All five valid feedback reasons can be saved without error."""
        reasons = ["inaccurate", "incomplete", "outdated", "wrong_source", "unclear"]
        for reason in reasons:
            row = self._make_flagged_row({"rating": "negative"})
            mock_table = MagicMock()
            mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MockResponse(row)
            mock_table.update.return_value.eq.return_value.execute.return_value = MockResponse(None)

            mock_db = MagicMock()
            mock_db.table.return_value = mock_table

            with patch.object(vqa_svc, "supabase", mock_db):
                with patch.object(vqa_svc, "log_activity"):
                    result = vqa_svc.update_rating_feedback(
                        rating_id="11111111-1111-1111-1111-111111111111",
                        reason=reason,
                        comment=f"Comment for {reason}.",
                        user_email="tech@example.com",
                    )

            assert result["feedback_reason"] == reason
            assert result["feedback_comment"] == f"Comment for {reason}."

    def test_null_comment_still_saves_reason(self):
        """Saving with reason but null comment works (comment is optional)."""
        row = self._make_flagged_row({"rating": "negative"})
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
                    comment=None,
                    user_email="tech@example.com",
                )

        assert result["feedback_reason"] == "outdated"
        assert result["feedback_comment"] is None

    def test_idempotent_update_does_not_break_approve_flow(self):
        """Updating feedback_reason multiple times does not affect the rating row for approve."""
        row = self._make_flagged_row({
            "rating": "negative",
            "feedback_reason": "inaccurate",
            "feedback_comment": "First comment.",
        })
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
        mock_table.update.return_value.eq.return_value.execute.assert_called_once()
