"""
Unit test ensuring every system prompt's "not found" phrase is covered by _SENTINEL_PHRASES.

If a developer changes the wording in a prompt but forgets to update the sentinel list,
this test fails immediately — catching the mismatch in dev, not in production.
"""

import sys
import os
from types import ModuleType
from unittest.mock import MagicMock

# Stub out heavy transitive dependencies so we can import the constants
# without needing pymupdf4llm, supabase, etc. on the dev machine.
for mod_name in (
    "pymupdf4llm",
    "fitz",
    "db",
    "supabase",
    "services.manual_parser",
    "services.ollama_embedder",
    "services.system_registry",
    "services.document_preprocessor",
    "services.contextual_prefix",
    "services.validated_qa_service",
    "services.document_search_service",
):
    if mod_name not in sys.modules:
        sys.modules[mod_name] = MagicMock()

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from services.manual_rag_service import (
    _NOT_FOUND_KNOWLEDGE_BASE,
    _NOT_FOUND_MANUALS,
    _NOT_FOUND_KNOWLEDGE_BASE_AR,
    _SENTINEL_PHRASES,
    VALIDATED_QA_SYSTEM_PROMPT,
    DOCUMENT_QA_SYSTEM_PROMPT,
)


def test_knowledge_base_phrase_in_sentinels():
    """The 'knowledge base' not-found phrase must be caught by the grounding check."""
    assert _NOT_FOUND_KNOWLEDGE_BASE.lower() in _SENTINEL_PHRASES


def test_manuals_phrase_in_sentinels():
    """The 'available manuals' not-found phrase must be caught by the grounding check."""
    assert _NOT_FOUND_MANUALS.lower() in _SENTINEL_PHRASES


def test_arabic_phrase_in_sentinels():
    """The Arabic not-found phrase must be caught by the grounding check."""
    assert _NOT_FOUND_KNOWLEDGE_BASE_AR in _SENTINEL_PHRASES


def test_validated_qa_prompt_uses_constant():
    """VALIDATED_QA_SYSTEM_PROMPT must reference the shared not-found phrase."""
    assert _NOT_FOUND_KNOWLEDGE_BASE in VALIDATED_QA_SYSTEM_PROMPT


def test_document_qa_prompt_uses_constant():
    """DOCUMENT_QA_SYSTEM_PROMPT must reference the shared not-found phrase."""
    assert _NOT_FOUND_KNOWLEDGE_BASE in DOCUMENT_QA_SYSTEM_PROMPT
