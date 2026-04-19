"""
Unit tests for classify_reason_code in rag_diagnostic_service.py (spec 088, fix 2).

Validates the first-trigger-wins ordering per research.md R-02:
  no_chunks_retrieved → rerank_below_threshold → generator_refused_with_chunks
"""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from services.rag_diagnostic_service import classify_reason_code


def test_zero_chunks_returns_no_chunks_retrieved():
    diagnostic = {
        "retrieval": {"candidates": [], "k": 0},
        "rerank": {"top_score": 0.70, "threshold_applied": 0.55},
        "grounding": {"sentinel_phrase_detected": True},
    }
    decision, reason_code, note = classify_reason_code(
        diagnostic, answer="This information is not in the available manuals.", grounded=False
    )
    assert decision == "ungrounded"
    assert reason_code == "no_chunks_retrieved", f"Expected no_chunks_retrieved, got {reason_code}"


def test_rerank_below_threshold_returns_rerank_below_threshold():
    diagnostic = {
        "retrieval": {"candidates": [{"chunk_id": "x"}] * 5, "k": 5},
        "rerank": {"top_score": 0.40, "threshold_applied": 0.55},
        "grounding": {"sentinel_phrase_detected": False},
    }
    decision, reason_code, note = classify_reason_code(
        diagnostic, answer="some answer text", grounded=False
    )
    assert decision == "ungrounded"
    assert reason_code == "rerank_below_threshold", f"Expected rerank_below_threshold, got {reason_code}"


def test_generator_refused_with_chunks_returns_generator_refused():
    diagnostic = {
        "retrieval": {"candidates": [{"chunk_id": "x"}] * 5, "k": 5},
        "rerank": {"top_score": 0.70, "threshold_applied": 0.55},
        "grounding": {"sentinel_phrase_detected": True},
    }
    decision, reason_code, note = classify_reason_code(
        diagnostic, answer="This information is not in the available manuals.", grounded=False
    )
    assert decision == "ungrounded"
    assert reason_code == "generator_refused_with_chunks", f"Expected generator_refused_with_chunks, got {reason_code}"


def test_pipeline_error_when_answer_is_none():
    decision, reason_code, note = classify_reason_code({}, answer=None, grounded=False)
    assert decision == "error"
    assert reason_code == "pipeline_error"


def test_grounded_answer():
    diagnostic = {"rewrite": {"ran": True}, "retrieval": {"candidates": [{"chunk_id": "x"}], "k": 1}}
    decision, reason_code, note = classify_reason_code(
        diagnostic, answer="The procedure is as follows...", grounded=True
    )
    assert decision == "grounded"
    assert reason_code == "grounded_answer"


def test_short_circuited_no_rag():
    diagnostic = {}
    decision, reason_code, note = classify_reason_code(
        diagnostic, answer="Greetings!", grounded=True
    )
    assert decision == "grounded"
    assert reason_code == "short_circuited_no_rag"


if __name__ == "__main__":
    test_zero_chunks_returns_no_chunks_retrieved()
    test_rerank_below_threshold_returns_rerank_below_threshold()
    test_generator_refused_with_chunks_returns_generator_refused()
    test_pipeline_error_when_answer_is_none()
    test_grounded_answer()
    test_short_circuited_no_rag()
    print("All classify_reason_code tests passed.")