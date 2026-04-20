"""Per-entity validated_qa lookup for compound queries.

Observed 2026-04-20: even with match_count=15, the compound embedding
"cadas ats server 1 and server 2" ranked Server 1's row outside the
top-15 of ~149 total rows (AIDA-NG and other system rows mentioning
"server" crowded it out before topic filter applied).

Fix: for compound queries, decompose the original into one sub-query
per entity and look each up independently. Each sub-query is a
narrow single-entity query that the embedder handles correctly.
"""

from unittest.mock import AsyncMock, patch

import pytest

from services.manual_rag_service import _sub_query_for_entity


@pytest.mark.parametrize(
    "original,entity,others,expected",
    [
        # "A and B" replaced with just A
        (
            "what is the ip of all cadas ats server 1 and server 2",
            "server 1",
            {"server 2"},
            "what is the ip of all cadas ats server 1",
        ),
        # "A and B" replaced with just B (other-and-entity order)
        (
            "what is the ip of all cadas ats server 1 and server 2",
            "server 2",
            {"server 1"},
            "what is the ip of all cadas ats server 2",
        ),
        # Compact phrasing
        (
            "both server 1 and server 2 ip",
            "server 1",
            {"server 2"},
            "both server 1 ip",
        ),
        # Three entities (take entity, strip the other two from "A and B and C" forms)
        (
            "server 1 and server 2 and server 3 configs",
            "server 2",
            {"server 1", "server 3"},
            "server 2 configs",
        ),
    ],
    ids=["entity_first", "entity_second", "bare_compact", "three_entities"],
)
def test_sub_query_for_entity(original, entity, others, expected):
    result = _sub_query_for_entity(original, entity, others)
    # Normalize whitespace for comparison — regex substitutions can leave
    # double-spaces which the actual lookup code also normalizes
    assert " ".join(result.split()) == " ".join(expected.split())


@pytest.mark.asyncio
async def test_try_compound_verbatim_runs_one_lookup_per_entity():
    """For a 2-entity query, _try_compound_verbatim should call
    check_validated_match twice — once per entity — and stitch the
    top match of each."""
    from services.manual_rag_service import _try_compound_verbatim

    calls = []

    async def _fake_lookup(question_text, detected_system=None, match_count=5):
        calls.append(question_text)
        # Each sub-query gets the matching row at top-1
        if "server 1" in question_text:
            return {
                "matches": [
                    {
                        "id": "r1", "question_text": "what is cadas ats server 1 ip?",
                        "validated_answer": "Server 1 IPs", "similarity": 0.92,
                        "validated_by": "x", "validated_at": "2026-01-01",
                    }
                ]
            }
        if "server 2" in question_text:
            return {
                "matches": [
                    {
                        "id": "r2", "question_text": "what is cadas ats server 2 ip?",
                        "validated_answer": "Server 2 IPs", "similarity": 0.92,
                        "validated_by": "x", "validated_at": "2026-01-01",
                    }
                ]
            }
        return {"matches": []}

    with patch(
        "services.validated_qa_service.check_validated_match",
        new=AsyncMock(side_effect=_fake_lookup),
    ):
        text, matches, count = await _try_compound_verbatim(
            "what is the ip of cadas ats server 1 and server 2",
            detected_system="CADAS-ATS",
        )

    assert len(calls) == 2, f"expected one lookup per entity, got {len(calls)}"
    assert text is not None
    assert "Server 1 IPs" in text
    assert "Server 2 IPs" in text
    assert count == 2


@pytest.mark.asyncio
async def test_try_compound_verbatim_requires_at_least_two_entity_matches():
    """If only one entity's row is found (e.g. no Server 1 data), do NOT
    produce a partial compound verbatim — fall back to the normal path."""
    from services.manual_rag_service import _try_compound_verbatim

    async def _fake_lookup(question_text, detected_system=None, match_count=5):
        # Only server 2 sub-query yields a match that mentions server 2
        if "server 2" in question_text:
            return {"matches": [
                {
                    "id": "r2", "question_text": "cadas ats server 2 ip",
                    "validated_answer": "Server 2 IPs", "similarity": 0.92,
                    "validated_by": "x", "validated_at": "2026-01-01",
                }
            ]}
        return {"matches": []}

    with patch(
        "services.validated_qa_service.check_validated_match",
        new=AsyncMock(side_effect=_fake_lookup),
    ):
        text, matches, count = await _try_compound_verbatim(
            "server 1 and server 2 ip", detected_system="CADAS-ATS",
        )

    assert text is None
    assert count == 0


@pytest.mark.asyncio
async def test_try_compound_verbatim_noop_for_single_entity_query():
    """Single-entity queries shouldn't trigger per-entity logic."""
    from services.manual_rag_service import _try_compound_verbatim

    lookup_mock = AsyncMock()
    with patch("services.validated_qa_service.check_validated_match", new=lookup_mock):
        text, matches, count = await _try_compound_verbatim(
            "what is the ip of server 1", detected_system="CADAS-ATS",
        )

    assert text is None
    assert lookup_mock.call_count == 0
