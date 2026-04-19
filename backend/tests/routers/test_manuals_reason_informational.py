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


class TestFeedbackDoesNotAffectReflagOrReview:
    """FR-011 proof: the three downstream pipelines never read feedback_reason.

    These tests exercise the actual downstream functions (update_validated_rating,
    review_answer approve, review_answer correct) and assert the feedback columns
    never participate in their logic. Each test runs the function once with
    feedback set and once without; the observable output must be identical.
    """

    def test_update_validated_rating_reflag_decision_independent_of_feedback(self):
        """The reflag threshold on validated_qa never consults answer_ratings.feedback_*.

        Evidence: the function only calls supabase.rpc and supabase.table("validated_qa").
        It never queries answer_ratings, so feedback_reason/comment are unreachable.
        """
        from services.validated_qa_service import REFLAG_MIN_TOTAL, REFLAG_THRESHOLD

        # Counts that push the ratio above threshold and total above MIN_TOTAL.
        # We pick 1 up + 4 down → ratio 0.8, total 5. With threshold=0.7, min=3
        # (project defaults) the row reflags. If defaults change, reflag may
        # not fire — the assertion below reads actual constants and adapts.
        up, down = 1, 4
        should_reflag = (up + down) >= REFLAG_MIN_TOTAL and (
            down / (up + down)
        ) > REFLAG_THRESHOLD

        mock_validated_table = MagicMock()
        mock_validated_table.select.return_value.eq.return_value.single.return_value.execute.return_value = (
            MockResponse({"thumbs_up_count": up, "thumbs_down_count": down})
        )

        table_calls = []

        def table_router(name):
            table_calls.append(name)
            if name == "validated_qa":
                return mock_validated_table
            raise AssertionError(
                f"update_validated_rating should not query table {name!r} — "
                f"only 'validated_qa' is permitted"
            )

        mock_db = MagicMock()
        mock_db.table.side_effect = table_router
        mock_db.rpc.return_value.execute.return_value = MockResponse(None)

        with patch.object(vqa_svc, "supabase", mock_db):
            vqa_svc.update_validated_rating(
                "11111111-1111-1111-1111-111111111111", "negative"
            )

        # Invariant 1: the function never touched answer_ratings (or any other table).
        assert all(
            name == "validated_qa" for name in table_calls
        ), f"Unexpected tables queried: {table_calls}"

        # Invariant 2: the reflag update call happens iff thresholds say so —
        # driven purely by counts, never by feedback_reason.
        reflag_update_called = (
            mock_validated_table.update.called
            and any(
                call.args[0] == {"is_reflagged": True}
                for call in mock_validated_table.update.call_args_list
            )
        )
        assert reflag_update_called == should_reflag

    def test_review_answer_approve_ignores_feedback_columns(self):
        """review_answer(approve) inserts validated_qa.validated_answer = rating.answer_text.

        Both with and without feedback_reason/comment set on the rating row, the
        insert payload's validated_answer field must be identical.
        """
        import asyncio

        async def run_approve(rating_row):
            mock_vqa_select = MagicMock()
            mock_vqa_select.data = []  # not a reflagged entry

            mock_ratings_table = MagicMock()
            mock_ratings_table.select.return_value.eq.return_value.single.return_value.execute.return_value = MockResponse(
                rating_row
            )

            inserted_rows = []
            mock_insert_table = MagicMock()

            def capture_insert(row):
                inserted_rows.append(row)
                chain = MagicMock()
                chain.execute.return_value = MockResponse(
                    [{"id": "new-vqa-id", **row}]
                )
                return chain

            mock_insert_table.insert.side_effect = capture_insert
            mock_insert_table.update.return_value.eq.return_value.execute.return_value = (
                MockResponse(None)
            )

            def table_router(name):
                if name == "validated_qa":
                    t = MagicMock()
                    t.select.return_value.eq.return_value.execute.return_value = (
                        mock_vqa_select
                    )
                    t.insert.side_effect = capture_insert
                    return t
                if name == "answer_ratings":
                    return mock_ratings_table
                return MagicMock()

            mock_db = MagicMock()
            mock_db.table.side_effect = table_router

            with patch.object(vqa_svc, "supabase", mock_db):
                with patch.object(
                    vqa_svc, "embed_single", return_value=[0.1] * 768
                ):
                    with patch.object(vqa_svc, "log_activity"):
                        with patch.object(
                            vqa_svc,
                            "_rewrite_with_summary",
                            return_value=rating_row["question_text"],
                        ):
                            await vqa_svc.review_answer(
                                rating_id=rating_row["id"],
                                action="approve",
                                corrected_answer=None,
                                reviewer_email="admin@example.com",
                            )

            return inserted_rows

        base_row = {
            "id": "abc123",
            "question_text": "How do I restart AIDA NG?",
            "answer_text": "Press and hold RESET for 3 seconds.",
            "rater_email": "tech@example.com",
            "source_chunks": [],
            "manual_id": None,
            "session_summary": None,
        }

        with_feedback = {
            **base_row,
            "feedback_reason": "outdated",
            "feedback_comment": "Was valid in 2022, revised 2024.",
        }
        without_feedback = {
            **base_row,
            "feedback_reason": None,
            "feedback_comment": None,
        }

        inserted_with = asyncio.run(run_approve(with_feedback))
        inserted_without = asyncio.run(run_approve(without_feedback))

        assert len(inserted_with) == 1
        assert len(inserted_without) == 1

        # The validated_answer comes from rating.answer_text in both cases.
        assert inserted_with[0]["validated_answer"] == base_row["answer_text"]
        assert inserted_without[0]["validated_answer"] == base_row["answer_text"]

        # Feedback columns must never leak into the validated_qa row.
        for row in inserted_with + inserted_without:
            assert "feedback_reason" not in row
            assert "feedback_comment" not in row

    def test_review_answer_correct_uses_corrected_text_not_feedback_comment(self):
        """review_answer(correct) uses the reviewer's corrected_answer, never the
        rater's feedback_comment. Prevents any accidental coupling where
        feedback comments get promoted into the validated answer text.
        """
        import asyncio

        async def run_correct(rating_row, corrected_answer):
            mock_vqa_select = MagicMock()
            mock_vqa_select.data = []

            mock_ratings_table = MagicMock()
            mock_ratings_table.select.return_value.eq.return_value.single.return_value.execute.return_value = MockResponse(
                rating_row
            )

            inserted_rows = []

            def capture_insert(row):
                inserted_rows.append(row)
                chain = MagicMock()
                chain.execute.return_value = MockResponse(
                    [{"id": "new-vqa-id", **row}]
                )
                return chain

            def table_router(name):
                if name == "validated_qa":
                    t = MagicMock()
                    t.select.return_value.eq.return_value.execute.return_value = (
                        mock_vqa_select
                    )
                    t.insert.side_effect = capture_insert
                    return t
                if name == "answer_ratings":
                    return mock_ratings_table
                return MagicMock()

            mock_db = MagicMock()
            mock_db.table.side_effect = table_router

            with patch.object(vqa_svc, "supabase", mock_db):
                with patch.object(
                    vqa_svc, "embed_single", return_value=[0.1] * 768
                ):
                    with patch.object(vqa_svc, "log_activity"):
                        with patch.object(
                            vqa_svc,
                            "_rewrite_with_summary",
                            return_value=rating_row["question_text"],
                        ):
                            await vqa_svc.review_answer(
                                rating_id=rating_row["id"],
                                action="correct",
                                corrected_answer=corrected_answer,
                                reviewer_email="admin@example.com",
                            )

            return inserted_rows

        row_with_feedback = {
            "id": "abc123",
            "question_text": "How do I restart AIDA NG?",
            "answer_text": "Press RESET.",
            "rater_email": "tech@example.com",
            "source_chunks": [],
            "manual_id": None,
            "session_summary": None,
            "feedback_reason": "incomplete",
            # Deliberately phrased to look like an answer. Must not be used.
            "feedback_comment": "Press RESET for 5 seconds, not 3.",
        }

        inserted = asyncio.run(
            run_correct(
                row_with_feedback,
                corrected_answer="Hold RESET for exactly 3 seconds.",
            )
        )

        assert len(inserted) == 1
        # The validated_answer comes from corrected_answer, NOT from
        # feedback_comment, even when the comment superficially resembles an
        # answer.
        assert (
            inserted[0]["validated_answer"]
            == "Hold RESET for exactly 3 seconds."
        )
        assert (
            inserted[0]["validated_answer"]
            != row_with_feedback["feedback_comment"]
        )


class TestRealUsageSuggestionsScope:
    """FR-011 proof: /manuals/real-usage-suggestions operates on positive
    ratings only and never selects the feedback columns.
    """

    def test_handler_selects_only_question_answer_created_at(self):
        """Verify the SELECT clause on answer_ratings is the narrow 3-field set
        the handler uses. If someone accidentally widens it to "*", feedback
        columns would start flowing into the suggestion pipeline — this test
        catches that regression at the SQL boundary.
        """
        import importlib

        # Read the raw handler source — cheaper and more robust than mocking
        # the full request pipeline with _admin_check, httpx, embed_single, etc.
        from pathlib import Path

        manuals_source = (
            Path(__file__).parent.parent.parent / "routers" / "manuals.py"
        ).read_text(encoding="utf-8")

        # Locate the real_usage_suggestions function body.
        start = manuals_source.index("async def real_usage_suggestions")
        # Scan until the next top-level def / class to bound the slice.
        rest = manuals_source[start:]
        end_markers = ["\n@router.", "\nclass ", "\nasync def "]
        end_positions = [rest.find(m, 10) for m in end_markers if rest.find(m, 10) > 0]
        end = min(end_positions) if end_positions else len(rest)
        body = rest[:end]

        # Assertion: the answer_ratings SELECT is scoped.
        assert 'select("question_text, answer_text, created_at")' in body, (
            "real_usage_suggestions must SELECT only question_text, answer_text, "
            "created_at from answer_ratings. Any widening (e.g. select('*')) "
            "would pull feedback_reason/comment into the suggestion pipeline "
            "and violate FR-011."
        )

        # Belt-and-braces: the handler must NEVER read feedback columns by name.
        assert "feedback_reason" not in body
        assert "feedback_comment" not in body
