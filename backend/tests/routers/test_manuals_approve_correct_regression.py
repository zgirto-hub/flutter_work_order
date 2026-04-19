"""
SC-006 smoke tests: verify approve/correct flow works on ratings with feedback populated.
Seed one flagged rating with a populated reason + comment. Invoke review_answer(action='approve').
Assert exactly one validated_qa row is produced. Repeat with action='correct' and a corrected_answer,
assert validated_answer equals the corrected text.
"""

import pytest
from unittest.mock import MagicMock, patch, AsyncMock
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "backend"))

import services.validated_qa_service as vqa_svc


class MockResponse:
    def __init__(self, data):
        self.data = data


class TestApproveCorrectWithFeedback:
    """Smoke tests for approve/correct on ratings that have feedback_reason/comment set."""

    def _make_rating_row(self, overrides=None):
        base = {
            "id": "11111111-1111-1111-1111-111111111111",
            "question_text": "How do I restart AIDA NG?",
            "answer_text": "Press and hold RESET for 3 seconds.",
            "rating": "negative",
            "rater_email": "tech@example.com",
            "feedback_reason": "outdated",
            "feedback_comment": "The SOP was updated in 2023.",
            "review_status": "pending",
            "source_chunks": [],
            "session_summary": None,
            "manual_id": None,
        }
        if overrides:
            base.update(overrides)
        return base

    def _build_table_router(self, rating_row):
        validated_qa_call_count = [0]
        answer_ratings_call_count = [0]

        mock_validated_qa_select = MagicMock()
        mock_validated_qa_select.select.return_value.eq.return_value.execute.return_value = MockResponse([])

        mock_validated_qa_insert = MagicMock()
        mock_validated_qa_insert.insert.return_value.execute.return_value = MockResponse([{"id": "new-validated-id"}])

        mock_answer_ratings_select = MagicMock()
        mock_answer_ratings_select.select.return_value.eq.return_value.single.return_value.execute.return_value = MockResponse(rating_row)

        mock_answer_ratings_update = MagicMock()
        mock_answer_ratings_update.update.return_value.eq.return_value.execute.return_value = MockResponse(None)

        def table_router(name):
            if name == "validated_qa":
                validated_qa_call_count[0] += 1
                if validated_qa_call_count[0] == 1:
                    return mock_validated_qa_select
                return mock_validated_qa_insert
            if name == "answer_ratings":
                answer_ratings_call_count[0] += 1
                if answer_ratings_call_count[0] == 1:
                    return mock_answer_ratings_select
                return mock_answer_ratings_update
            return MagicMock()

        return table_router, mock_validated_qa_insert

    @pytest.mark.asyncio
    async def test_approve_produces_one_validated_qa_row(self):
        rating_row = self._make_rating_row()
        table_router, mock_insert = self._build_table_router(rating_row)

        mock_db = MagicMock()
        mock_db.table.side_effect = table_router

        with patch.object(vqa_svc, "supabase", mock_db):
            with patch.object(vqa_svc, "embed_single", new_callable=AsyncMock) as mock_embed:
                mock_embed.return_value = [0.0] * 768
                with patch.object(vqa_svc, "log_activity"):
                    validated_id = await vqa_svc.review_answer(
                        rating_id="11111111-1111-1111-1111-111111111111",
                        action="approve",
                        corrected_answer=None,
                        reviewer_email="admin@example.com",
                    )

        assert validated_id == "new-validated-id"
        mock_insert.insert.assert_called_once()
        insert_call_args = mock_insert.insert.call_args[0][0]
        assert insert_call_args["validated_answer"] == "Press and hold RESET for 3 seconds."
        assert insert_call_args["question_text"] == "How do I restart AIDA NG?"

    @pytest.mark.asyncio
    async def test_correct_replaces_answer_with_corrected_text(self):
        rating_row = self._make_rating_row()
        table_router, mock_insert = self._build_table_router(rating_row)

        mock_db = MagicMock()
        mock_db.table.side_effect = table_router

        corrected = "Press and hold RESET for 5 seconds, then release."

        with patch.object(vqa_svc, "supabase", mock_db):
            with patch.object(vqa_svc, "embed_single", new_callable=AsyncMock) as mock_embed:
                mock_embed.return_value = [0.0] * 768
                with patch.object(vqa_svc, "log_activity"):
                    validated_id = await vqa_svc.review_answer(
                        rating_id="11111111-1111-1111-1111-111111111111",
                        action="correct",
                        corrected_answer=corrected,
                        reviewer_email="admin@example.com",
                    )

        assert validated_id == "new-validated-id"
        mock_insert.insert.assert_called_once()
        insert_call_args = mock_insert.insert.call_args[0][0]
        assert insert_call_args["validated_answer"] == corrected
        assert insert_call_args["question_text"] == "How do I restart AIDA NG?"

    @pytest.mark.asyncio
    async def test_no_extra_supabase_round_trips(self):
        rating_row = self._make_rating_row()
        table_router, mock_insert = self._build_table_router(rating_row)

        table_calls = []

        def counting_router(name):
            table_calls.append(name)
            return table_router(name)

        mock_db = MagicMock()
        mock_db.table.side_effect = counting_router

        with patch.object(vqa_svc, "supabase", mock_db):
            with patch.object(vqa_svc, "embed_single", new_callable=AsyncMock) as mock_embed:
                mock_embed.return_value = [0.0] * 768
                with patch.object(vqa_svc, "log_activity"):
                    await vqa_svc.review_answer(
                        rating_id="11111111-1111-1111-1111-111111111111",
                        action="approve",
                        corrected_answer=None,
                        reviewer_email="admin@example.com",
                    )

        validated_qa_calls = [c for c in table_calls if c == "validated_qa"]
        answer_ratings_calls = [c for c in table_calls if c == "answer_ratings"]
        assert len(validated_qa_calls) == 2
        assert len(answer_ratings_calls) == 2
