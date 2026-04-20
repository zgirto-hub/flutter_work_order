"""Follow-up to test_compound_query_guard.py — covers the synthesis-quality
fixes from session 2026-04-20:

1. _effective_rag_threshold drops from 0.75 to 0.70 for compound queries,
   so phrasings like "both server 1 and server 2 ip" can still enter the
   verified-synthesis branch instead of falling through to manual chunks.
2. VALIDATED_QA_SYSTEM_PROMPT gains a MULTI-ENTITY rule telling the LLM
   to enumerate every named entity across all sources (Q1/Q2 regression
   where Llama 4 Scout answered only one of two servers).
"""

from services.manual_rag_service import (
    RAG_CONFIDENCE_THRESHOLD,
    VALIDATED_QA_SYSTEM_PROMPT,
    _effective_rag_threshold,
)


def test_effective_threshold_single_entity():
    # Single-entity queries keep the default 0.75 floor
    assert _effective_rag_threshold("what is the ip of cadas ats server 1") == RAG_CONFIDENCE_THRESHOLD


def test_effective_threshold_compound_lowered():
    # Compound queries get a looser 0.70 floor so they can still enter
    # the verified-synthesis branch when neither row scores 0.75 on its own
    threshold = _effective_rag_threshold("both server 1 and server 2 ip")
    assert threshold < RAG_CONFIDENCE_THRESHOLD
    assert threshold == 0.70


def test_effective_threshold_none_and_empty():
    # Defensive: None / empty fall back to the default threshold
    assert _effective_rag_threshold(None) == RAG_CONFIDENCE_THRESHOLD
    assert _effective_rag_threshold("") == RAG_CONFIDENCE_THRESHOLD


def test_validated_qa_prompt_has_multi_entity_rule():
    # Prompt must explicitly instruct the LLM to cover EVERY named entity
    # and block the "entity X not mentioned" dodge when another source
    # actually covers it
    prompt = VALIDATED_QA_SYSTEM_PROMPT.lower()
    assert "multi-entity" in prompt or "multiple entities" in prompt or "each entity" in prompt, (
        "VALIDATED_QA_SYSTEM_PROMPT is missing the multi-entity rule"
    )
    # Must warn against the specific failure mode we saw: answering one
    # entity and declaring another "not mentioned"
    assert "not mentioned" in prompt or "not in the sources" in prompt, (
        "Prompt must explicitly forbid the 'not mentioned' dodge on multi-entity questions"
    )
