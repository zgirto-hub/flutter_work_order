import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from prompts.paraphrase_prompt import parse_paraphrase_output


class TestParseParaphraseOutput:
    def test_happy_path_four_clean_lines(self):
        raw = "how do I log in to aida ng?\npassword of AIDA NG system\naida ng login credentials\nwhat credentials do I use for aida ng?"
        result = parse_paraphrase_output(raw, "what is aida ng username and password?")
        assert len(result) == 4
        assert result == [
            "how do I log in to aida ng?",
            "password of AIDA NG system",
            "aida ng login credentials",
            "what credentials do I use for aida ng?",
        ]

    def test_numbered_lines_stripped(self):
        raw = "1. how do I log in?\n2) what is the password?\n3 - another variant"
        result = parse_paraphrase_output(raw, "original question")
        assert result == []

    def test_bullet_lines_dropped(self):
        raw = "- first variant\n* second variant"
        result = parse_paraphrase_output(raw, "original question")
        assert result == []

    def test_duplicate_of_original_dropped(self):
        raw = "original question\nanother variant\nOriginal Question"
        result = parse_paraphrase_output(raw, "  Original   Question  ")
        assert result == ["another variant"]

    def test_empty_whitespace_only_dropped(self):
        raw = "first\n\n  \nsecond\n"
        result = parse_paraphrase_output(raw, "original")
        assert result == ["first", "second"]

    def test_seven_lines_capped_at_five(self):
        raw = "variant1\nvariant2\nvariant3\nvariant4\nvariant5\nvariant6\nvariant7"
        result = parse_paraphrase_output(raw, "original")
        assert len(result) == 5

    def test_zero_usable_lines_returns_empty(self):
        raw = "1. numbered\n- bullet\n   "
        result = parse_paraphrase_output(raw, "original")
        assert result == []


class TestParaphraseEndpoints:
    @pytest.mark.asyncio
    async def test_paraphrase_endpoint_happy_path(self):
        from fastapi.testclient import TestClient
        from main import app

        mock_raw_output = "how do I log in to aida ng?\npassword of AIDA NG system\naida ng login credentials\nwhat credentials do I use for aida ng?"

        with patch(
            "services.ai_providers.resolver.generate",
            new=AsyncMock(
                return_value=(
                    mock_raw_output,
                    "mistral",
                    "Mistral",
                    False,
                    None,
                )
            ),
        ):
            client = TestClient(app)
            response = client.post(
                "/api/manuals/paraphrase-variants?user_email=admin@example.com",
                json={"question_text": "what is aida ng username and password?"},
            )

            assert response.status_code == 200
            data = response.json()
            assert "variants" in data
            assert len(data["variants"]) == 4
            assert "what is aida ng username and password?" not in data["variants"]

    @pytest.mark.asyncio
    async def test_paraphrase_endpoint_provider_failure(self):
        from fastapi.testclient import TestClient
        from main import app

        with patch(
            "services.ai_providers.resolver.generate",
            new=AsyncMock(side_effect=RuntimeError("Provider failed")),
        ):
            client = TestClient(app)
            response = client.post(
                "/api/manuals/paraphrase-variants?user_email=admin@example.com",
                json={"question_text": "test question"},
            )

            assert response.status_code == 200
            data = response.json()
            assert data["variants"] == []

    @pytest.mark.asyncio
    async def test_approve_with_variants_inserts_n_rows(self):
        from fastapi.testclient import TestClient
        from main import app

        # Track per-variant embeddings to verify INV-1 (unique embedding per row)
        call_count = 0

        async def mock_embed_single(text, priority=None):
            nonlocal call_count
            call_count += 1
            # Produce a deterministic but distinct embedding per call
            vec = [0.01 * call_count] * 768
            return vec

        # Capture the actual rows passed to .insert()
        captured_insert_payload = None

        def make_insert_mock(rows):
            nonlocal captured_insert_payload
            captured_insert_payload = rows
            result = MagicMock()
            result.data = [{"id": f"uuid-{i}"} for i in range(len(rows))]
            mock_chain = MagicMock()
            mock_chain.execute.return_value = result
            return mock_chain

        mock_table = MagicMock()
        mock_table.insert.side_effect = make_insert_mock
        mock_table.select.return_value.single.return_value.execute.return_value = MagicMock(
            data={
                "id": "rating-uuid",
                "answer_text": "test answer",
                "question_text": "original question",
                "source_chunks": [],
                "manual_id": None,
                "session_summary": None,
            }
        )
        mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock()

        with patch(
            "services.validated_qa_service.embed_single",
            new=mock_embed_single,
        ), patch(
            "services.validated_qa_service.supabase",
        ) as mock_supabase, patch(
            "services.validated_qa_service.log_activity",
        ):
            mock_supabase.table.return_value = mock_table

            client = TestClient(app)
            response = client.post(
                "/api/manuals/review-answer-with-variants?user_email=admin@example.com",
                json={
                    "rating_id": "rating-uuid",
                    "action": "approve",
                    "variants": ["variant1", "variant2", "variant3"],
                },
            )

            assert response.status_code == 200
            data = response.json()
            assert data["inserted_count"] == 3
            assert len(data["validated_qa_ids"]) == 3

            # Verify the actual insert payload (not mock return values)
            assert captured_insert_payload is not None, "insert() was never called"
            assert len(captured_insert_payload) == 3

            # INV-2: all rows share the same validated_answer
            answers = {row["validated_answer"] for row in captured_insert_payload}
            assert answers == {"test answer"}, f"Expected shared answer, got {answers}"

            # INV-2: all rows share the same rating_id
            rating_ids = {row["rating_id"] for row in captured_insert_payload}
            assert rating_ids == {"rating-uuid"}

            # INV-1: each row has distinct question_text
            texts = [row["question_text"] for row in captured_insert_payload]
            assert texts == ["variant1", "variant2", "variant3"]

            # INV-1: each row has a question_embedding and they are distinct
            embeddings = [row["question_embedding"] for row in captured_insert_payload]
            assert len(set(embeddings)) == 3, "Embeddings must be distinct per variant"

    @pytest.mark.asyncio
    async def test_approve_with_variants_rejects_empty_after_trim(self):
        from fastapi.testclient import TestClient
        from main import app

        client = TestClient(app)
        response = client.post(
            "/api/manuals/review-answer-with-variants?user_email=admin@example.com",
            json={
                "rating_id": "rating-uuid",
                "action": "approve",
                "variants": ["   ", ""],
            },
        )

        assert response.status_code == 400

    @pytest.mark.asyncio
    async def test_approve_with_variants_rejects_over_10(self):
        from fastapi.testclient import TestClient
        from main import app

        variants = [f"variant{i}" for i in range(11)]

        client = TestClient(app)
        response = client.post(
            "/api/manuals/review-answer-with-variants?user_email=admin@example.com",
            json={
                "rating_id": "rating-uuid",
                "action": "approve",
                "variants": variants,
            },
        )

        assert response.status_code == 400
