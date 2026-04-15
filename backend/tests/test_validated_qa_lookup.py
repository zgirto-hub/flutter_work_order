"""
Tests for validated-QA lookup stability (spec 067).

These tests verify that the pre-rewrite validated-QA fast-path works correctly:
- Identical repeated questions always hit the cache (INV-1)
- Pre-rewrite lookup is skipped on cache hit, so rewrite/HyDE/retrieval aren't called
- Pre-rewrite miss falls through to the existing pipeline
- Context-dependent follow-ups still flow through the post-rewrite path (INV-2)
- System filter is applied on pre-rewrite lookup (INV-3)
- No writes to validated_qa table (INV-4)
- Exceptions in pre-rewrite lookup fall through safely
"""

import pytest
from unittest.mock import AsyncMock, patch, MagicMock


@pytest.fixture
def vqa_direct_hit_fixture():
    return {
        "match_type": "direct",
        "validated_qa": {
            "id": "12345678-1234-1234-1234-123456789abc",
            "validated_question": "what is the password of AIDA NG system?",
            "validated_answer": "Username=SUPERUSER / password=Aftnlinux1",
            "validated_by": "admin@example.com",
            "validated_at": "2026-01-15T10:00:00",
            "distance": 0.05,
        },
    }


@pytest.fixture
def vqa_context_hit_fixture():
    return {
        "match_type": "context",
        "validated_qa": {
            "id": "12345678-1234-1234-1234-123456789abc",
            "validated_question": "what is the password of AIDA NG system?",
            "validated_answer": "Username=SUPERUSER / password=Aftnlinux1",
            "validated_by": "admin@example.com",
            "validated_at": "2026-01-15T10:00:00",
            "distance": 0.20,
        },
    }


@pytest.fixture
def vqa_miss_fixture():
    return {"match_type": "none", "validated_qa": None}


class TestPreRewriteValidatedQALookup:
    @pytest.mark.asyncio
    async def test_pre_rewrite_hit_returns_cached_answer_without_rewrite(
        self, vqa_direct_hit_fixture
    ):
        from services import manual_rag_service

        with patch(
            "services.manual_rag_service.validated_qa_service.check_validated_match",
            new_callable=AsyncMock,
            return_value=vqa_direct_hit_fixture,
        ) as mock_vqa:
            with patch(
                "services.manual_rag_service._rewrite_query",
                new_callable=AsyncMock,
            ) as mock_rewrite:
                with patch(
                    "services.manual_rag_service._generate_hypothetical_answer",
                    new_callable=AsyncMock,
                ) as mock_hyde:
                    with patch(
                        "services.manual_rag_service._compress_history",
                        new_callable=AsyncMock,
                    ):
                        with patch(
                            "services.manual_rag_service.supabase"
                        ) as mock_supabase:
                            mock_supabase.table.return_value.select.return_value.eq.return_value.execute.return_value = MagicMock(
                                data=[{"manual_count": 10}]
                            )

                            result = await manual_rag_service.ask(
                                question="what is the password of AIDA NG system?",
                                history=[],
                                user_email="test@example.com",
                            )

                            assert result["is_verified"] is True
                            assert result["model"] == "validated_qa"
                            assert (
                                result["answer"]
                                == "Username=SUPERUSER / password=Aftnlinux1"
                            )

                            mock_vqa.assert_called_once()
                            mock_rewrite.assert_not_called()
                            mock_hyde.assert_not_called()

    @pytest.mark.asyncio
    async def test_pre_rewrite_miss_falls_through_to_existing_pipeline(
        self, vqa_miss_fixture
    ):
        from services import manual_rag_service

        with patch(
            "services.manual_rag_service.validated_qa_service.check_validated_match",
            new_callable=AsyncMock,
            side_effect=[
                vqa_miss_fixture,
                vqa_miss_fixture,
            ],
        ) as mock_vqa:
            with patch(
                "services.manual_rag_service._rewrite_query",
                new_callable=AsyncMock,
                return_value="rewritten query",
            ) as mock_rewrite:
                with patch(
                    "services.manual_rag_service._generate_hypothetical_answer",
                    new_callable=AsyncMock,
                    return_value=None,
                ):
                    with patch(
                        "services.manual_rag_service._compress_history",
                        new_callable=AsyncMock,
                    ):
                        with patch(
                            "services.ollama_embedder.embed_single",
                            new_callable=AsyncMock,
                            return_value=[0.1] * 4096,
                        ):
                            with patch(
                                "services.manual_rag_service.supabase"
                            ) as mock_supabase:
                                mock_supabase.table.return_value.select.return_value.eq.return_value.execute.return_value = MagicMock(
                                    data=[{"manual_count": 10}]
                                )
                                mock_supabase.rpc.return_value.execute.return_value = (
                                    MagicMock(data=[])
                                )

                                await manual_rag_service.ask(
                                    question="what is the password of AIDA NG system?",
                                    history=[],
                                    user_email="test@example.com",
                                )

                                assert mock_vqa.call_count == 2
                                mock_rewrite.assert_called_once()

    @pytest.mark.asyncio
    async def test_pre_rewrite_hit_ignores_history_length(self, vqa_direct_hit_fixture):
        from services import manual_rag_service

        with patch(
            "services.manual_rag_service.validated_qa_service.check_validated_match",
            new_callable=AsyncMock,
            return_value=vqa_direct_hit_fixture,
        ):
            with patch(
                "services.manual_rag_service._rewrite_query",
                new_callable=AsyncMock,
            ) as mock_rewrite:
                with patch(
                    "services.manual_rag_service._generate_hypothetical_answer",
                    new_callable=AsyncMock,
                ):
                    with patch(
                        "services.manual_rag_service._compress_history",
                        new_callable=AsyncMock,
                    ):
                        with patch(
                            "services.manual_rag_service.supabase"
                        ) as mock_supabase:
                            mock_supabase.table.return_value.select.return_value.eq.return_value.execute.return_value = MagicMock(
                                data=[{"manual_count": 10}]
                            )

                            history_empty = []
                            history_long = [
                                {"question": "unrelated", "answer": "some answer"}
                            ] * 5

                            result_empty = await manual_rag_service.ask(
                                question="what is the password of AIDA NG system?",
                                history=history_empty,
                                user_email="test@example.com",
                            )

                            result_long = await manual_rag_service.ask(
                                question="what is the password of AIDA NG system?",
                                history=history_long,
                                user_email="test@example.com",
                            )

                            assert result_empty["is_verified"] is True
                            assert result_long["is_verified"] is True
                            assert result_empty["answer"] == result_long["answer"]

                            assert mock_rewrite.call_count == 0

    @pytest.mark.asyncio
    async def test_context_dependent_followup_hits_post_rewrite_path(
        self, vqa_miss_fixture, vqa_direct_hit_fixture
    ):
        from services import manual_rag_service

        with patch(
            "services.manual_rag_service.validated_qa_service.check_validated_match",
            new_callable=AsyncMock,
            side_effect=[
                vqa_miss_fixture,
                vqa_direct_hit_fixture,
            ],
        ) as mock_vqa:
            with patch(
                "services.manual_rag_service._rewrite_query",
                new_callable=AsyncMock,
                return_value="any other steps for CADAS-ATS?",
            ) as mock_rewrite:
                with patch(
                    "services.manual_rag_service._generate_hypothetical_answer",
                    new_callable=AsyncMock,
                    return_value=None,
                ):
                    with patch(
                        "services.manual_rag_service._compress_history",
                        new_callable=AsyncMock,
                    ):
                        with patch(
                            "services.ollama_embedder.embed_single",
                            new_callable=AsyncMock,
                            return_value=[0.1] * 4096,
                        ):
                            with patch(
                                "services.manual_rag_service.supabase"
                            ) as mock_supabase:
                                mock_supabase.table.return_value.select.return_value.eq.return_value.execute.return_value = MagicMock(
                                    data=[{"manual_count": 10}]
                                )
                                mock_supabase.rpc.return_value.execute.return_value = (
                                    MagicMock(data=[])
                                )

                                result = await manual_rag_service.ask(
                                    question="any other steps?",
                                    history=[
                                        {
                                            "question": "how do I restart CADAS-ATS?",
                                            "answer": "You restart it by...",
                                        }
                                    ],
                                    user_email="test@example.com",
                                )

                                assert mock_rewrite.call_count == 1
                                assert mock_vqa.call_count == 2
                                assert result["is_verified"] is True

    @pytest.mark.asyncio
    async def test_system_filter_applied_on_pre_rewrite_lookup(
        self, vqa_direct_hit_fixture
    ):
        from services import manual_rag_service

        with patch(
            "services.manual_rag_service.validated_qa_service.check_validated_match",
            new_callable=AsyncMock,
            return_value=vqa_direct_hit_fixture,
        ) as mock_vqa:
            with patch(
                "services.manual_rag_service._rewrite_query",
                new_callable=AsyncMock,
            ):
                with patch(
                    "services.manual_rag_service._generate_hypothetical_answer",
                    new_callable=AsyncMock,
                ):
                    with patch(
                        "services.manual_rag_service._compress_history",
                        new_callable=AsyncMock,
                    ):
                        with patch(
                            "services.manual_rag_service.supabase"
                        ) as mock_supabase:
                            mock_supabase.table.return_value.select.return_value.eq.return_value.execute.return_value = MagicMock(
                                data=[{"manual_count": 10}]
                            )

                            await manual_rag_service.ask(
                                question="what is the password of AIDA NG system?",
                                history=[],
                                user_email="test@example.com",
                            )

                            assert mock_vqa.call_count >= 1
                            first_call_kwargs = mock_vqa.call_args.kwargs
                            assert "detected_system" in first_call_kwargs
                            assert first_call_kwargs["detected_system"] is not None

    @pytest.mark.asyncio
    async def test_validated_qa_never_written_on_read_path(
        self, vqa_direct_hit_fixture
    ):
        from services import manual_rag_service

        with patch(
            "services.manual_rag_service.validated_qa_service.check_validated_match",
            new_callable=AsyncMock,
            return_value=vqa_direct_hit_fixture,
        ):
            with patch(
                "services.manual_rag_service._rewrite_query",
                new_callable=AsyncMock,
            ):
                with patch(
                    "services.manual_rag_service._generate_hypothetical_answer",
                    new_callable=AsyncMock,
                ):
                    with patch(
                        "services.manual_rag_service._compress_history",
                        new_callable=AsyncMock,
                    ):
                        with patch(
                            "services.manual_rag_service.supabase"
                        ) as mock_supabase:
                            mock_supabase.table.return_value.select.return_value.eq.return_value.execute.return_value = MagicMock(
                                data=[{"manual_count": 10}]
                            )

                            table_mock = mock_supabase.table.return_value

                            await manual_rag_service.ask(
                                question="what is the password of AIDA NG system?",
                                history=[],
                                user_email="test@example.com",
                            )

                            insert_calls = [
                                c
                                for c in table_mock.method_calls
                                if "insert" in c[0].lower()
                            ]
                            update_calls = [
                                c
                                for c in table_mock.method_calls
                                if "update" in c[0].lower()
                            ]
                            delete_calls = [
                                c
                                for c in table_mock.method_calls
                                if "delete" in c[0].lower()
                            ]

                            assert len(insert_calls) == 0, (
                                "No inserts should occur on read path"
                            )
                            assert len(update_calls) == 0, (
                                "No updates should occur on read path"
                            )
                            assert len(delete_calls) == 0, (
                                "No deletes should occur on read path"
                            )

    @pytest.mark.asyncio
    async def test_pre_rewrite_exception_falls_through_safely(
        self, vqa_direct_hit_fixture
    ):
        from services import manual_rag_service

        with patch(
            "services.manual_rag_service.validated_qa_service.check_validated_match",
            new_callable=AsyncMock,
            side_effect=Exception("boom"),
        ):
            with patch(
                "services.manual_rag_service._rewrite_query",
                new_callable=AsyncMock,
                return_value="rewritten query",
            ) as mock_rewrite:
                with patch(
                    "services.manual_rag_service._generate_hypothetical_answer",
                    new_callable=AsyncMock,
                    return_value=None,
                ):
                    with patch(
                        "services.manual_rag_service._compress_history",
                        new_callable=AsyncMock,
                    ):
                        with patch(
                            "services.ollama_embedder.embed_single",
                            new_callable=AsyncMock,
                            return_value=[0.1] * 4096,
                        ):
                            with patch(
                                "services.manual_rag_service.supabase"
                            ) as mock_supabase:
                                mock_supabase.table.return_value.select.return_value.eq.return_value.execute.return_value = MagicMock(
                                    data=[{"manual_count": 10}]
                                )
                                mock_supabase.rpc.return_value.execute.return_value = (
                                    MagicMock(data=[])
                                )

                                result = await manual_rag_service.ask(
                                    question="what is the password of AIDA NG system?",
                                    history=[],
                                    user_email="test@example.com",
                                )

                                mock_rewrite.assert_called_once()
                                assert result is not None
