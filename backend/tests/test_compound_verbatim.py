"""Compound verbatim: when the query names multiple entities AND we have
multiple topic-matched validated_qa rows, deterministically concatenate
their curated answers instead of asking an LLM to synthesize.

Llama 4 Scout 17B (2026-04-20 production) was refusing one entity even
when given a clean 2-source context with explicit labels — hit its
multi-source reasoning ceiling. Concatenation gives the user the right
answer, can't hallucinate, and runs in <1s.
"""

from services.manual_rag_service import (
    _build_compound_verbatim_answer,
    _should_compound_verbatim,
)


def test_compound_verbatim_concatenates_all_answers():
    matches = [
        {
            "id": "a",
            "question_text": "what is cadas ats server 1 ip?",
            "validated_answer": "CADAS-ATS Server 1:\ncs1-cont 172.31.21.11",
            "similarity": 0.90,
        },
        {
            "id": "b",
            "question_text": "what is cadas ats server 2 ip?",
            "validated_answer": "CADAS-ATS Server 2:\ncs2-cont 172.31.21.12",
            "similarity": 0.88,
        },
    ]
    result = _build_compound_verbatim_answer(matches)
    # Both answers must be present verbatim
    assert "172.31.21.11" in result
    assert "172.31.21.12" in result
    assert "CADAS-ATS Server 1" in result
    assert "CADAS-ATS Server 2" in result


def test_compound_verbatim_dedupes_identical_answers():
    """Paraphrase variants (spec 068) share validated_answer text — don't repeat."""
    matches = [
        {"id": "a", "question_text": "q1", "validated_answer": "same answer", "similarity": 0.90},
        {"id": "b", "question_text": "q2", "validated_answer": "same answer", "similarity": 0.88},
    ]
    result = _build_compound_verbatim_answer(matches)
    # "same answer" should appear exactly once
    assert result.count("same answer") == 1


def test_should_compound_verbatim_requires_compound_and_multiple_distinct():
    """Fire only when the query is compound AND there are >= 2 distinct answers."""
    compound_matches_2 = [
        {"validated_answer": "A"}, {"validated_answer": "B"},
    ]
    compound_matches_1 = [{"validated_answer": "A"}]
    compound_matches_dupes = [
        {"validated_answer": "A"}, {"validated_answer": "A"},
    ]

    assert _should_compound_verbatim(
        "server 1 and server 2", compound_matches_2
    ) is True
    # Single-entity query → don't fire even if multiple distinct matches
    assert _should_compound_verbatim(
        "server 1", compound_matches_2
    ) is False
    # Compound but only one match → nothing to concatenate, fall to single verbatim
    assert _should_compound_verbatim(
        "server 1 and server 2", compound_matches_1
    ) is False
    # Compound but all matches are the same answer (paraphrase variants) → not worth compounding
    assert _should_compound_verbatim(
        "server 1 and server 2", compound_matches_dupes
    ) is False


def test_should_compound_verbatim_empty():
    assert _should_compound_verbatim("server 1 and server 2", []) is False
    assert _should_compound_verbatim("", [{"validated_answer": "A"}]) is False
