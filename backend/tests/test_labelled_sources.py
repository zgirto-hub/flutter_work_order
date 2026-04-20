"""Regression: when multiple validated_qa rows are handed to the LLM for
synthesis, each source block must be labelled with the question it answers.
Without the label, Llama 4 Scout was reading only Source 1 and refusing
the other entities ("not mentioned") — observed 2026-04-20 on queries
like "ip of server 1 and server 2".
"""

from services.manual_rag_service import _build_validated_qa_context


def test_context_parts_include_question_label():
    matches = [
        {
            "id": "a",
            "question_text": "what is cadas ats server 2 ip?",
            "validated_answer": "Server 2: 172.31.21.12",
            "similarity": 0.90,
        },
        {
            "id": "b",
            "question_text": "what is cadas ats server 1 ip?",
            "validated_answer": "Server 1: 172.31.21.11",
            "similarity": 0.85,
        },
    ]
    ctx = _build_validated_qa_context(matches)
    # Each source must have a [Source N — answers: "..."] header
    assert "[Source 1 — answers:" in ctx
    assert "[Source 2 — answers:" in ctx
    # The entity names (server 1 / server 2) must appear in their LABELS
    # so the LLM can't claim an entity is "not mentioned"
    assert "server 1" in ctx.lower()
    assert "server 2" in ctx.lower()
    # The actual validated answers must also be in the context
    assert "172.31.21.12" in ctx
    assert "172.31.21.11" in ctx


def test_context_parts_preserve_order():
    """Source N should match the order of matches, so rank is preserved."""
    matches = [
        {"id": "a", "question_text": "q about X", "validated_answer": "AX", "similarity": 0.9},
        {"id": "b", "question_text": "q about Y", "validated_answer": "AY", "similarity": 0.85},
        {"id": "c", "question_text": "q about Z", "validated_answer": "AZ", "similarity": 0.80},
    ]
    ctx = _build_validated_qa_context(matches)
    # Check ordering — Source 1 must come before Source 2 etc.
    assert ctx.index("[Source 1") < ctx.index("[Source 2") < ctx.index("[Source 3")
    # And the label content matches its match
    assert 'answers: "q about X"' in ctx
    assert 'answers: "q about Y"' in ctx
    assert 'answers: "q about Z"' in ctx


def test_context_parts_handles_single_match():
    matches = [{"id": "a", "question_text": "solo", "validated_answer": "only answer", "similarity": 0.9}]
    ctx = _build_validated_qa_context(matches)
    assert "[Source 1 — answers:" in ctx
    assert "only answer" in ctx


def test_context_parts_empty():
    assert _build_validated_qa_context([]) == ""
