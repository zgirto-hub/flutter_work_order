"""Regression: the rewrite call timeout must be generous enough that
Ollama on a 15GB-RAM Zorin server doesn't consistently time out and
fall back to the raw original question. Production logs (2026-04-20)
showed "Query rewrite failed, using original query: Generator timed out"
firing on follow-up turns when the timeout was 10s.
"""

import inspect

from services.manual_rag_service import REWRITE_GENERATE_TIMEOUT_S, _rewrite_query


def test_rewrite_timeout_is_generous():
    # Previous value was 10s and it timed out in production. Require >= 20s.
    assert REWRITE_GENERATE_TIMEOUT_S >= 20.0


def test_rewrite_uses_the_named_constant():
    # Make sure the hardcoded 10.0 was actually replaced with the constant
    src = inspect.getsource(_rewrite_query)
    assert "timeout=REWRITE_GENERATE_TIMEOUT_S" in src, (
        "_rewrite_query must call generate(..., timeout=REWRITE_GENERATE_TIMEOUT_S) "
        "so the value is centrally controlled and testable"
    )
    assert "timeout=10.0" not in src, (
        "old hardcoded 10.0 timeout should be gone"
    )
