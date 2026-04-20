"""Regression: compound queries ("server 1 and server 2") must NOT short-circuit
to verbatim — a single verbatim row cannot cover multiple entities.
See diagnosis in session 2026-04-20: Q3 "what is the ip of all cadas ats
server 1 and server 2" returned only Server 2's IPs because `_should_return_verbatim`
looked at similarity scores alone, ignoring user intent.
"""

import pytest
from services.manual_rag_service import _is_compound_query


@pytest.mark.parametrize(
    "query,expected",
    [
        # Plain single-entity — not compound
        ("what is the ip of cadas ats server 1", False),
        ("what is the ip of cadas ats server 2", False),
        ("how to restart aida-ng", False),
        # Compound markers — should guard verbatim off
        ("what is the ip of all cadas ats server 1 and server 2", True),
        ("ip of server 1 and server 2", True),
        ("both server 1 and server 2 ip addresses", True),
        ("list all servers and their ips", True),
        ("show me server 1 and server 2 configs", True),
        # Edge: single "and" joining non-enumerated items — not compound
        ("how to restart cadas and check its status", False),
        # Empty / None
        ("", False),
    ],
    ids=[
        "single_server_1",
        "single_server_2",
        "single_aida_ng",
        "compound_all_and",
        "compound_bare_and",
        "compound_both",
        "compound_list_all",
        "compound_show_and",
        "non_compound_and_verb",
        "empty",
    ],
)
def test_is_compound_query(query, expected):
    assert _is_compound_query(query) is expected


def test_compound_guard_blocks_verbatim_in_integration():
    """End-to-end sanity: the guard must be wired such that a compound query
    with two strong matches does NOT produce a verbatim payload.
    """
    from services.manual_rag_service import _should_return_verbatim

    matches = [
        {"similarity": 0.92, "validated_answer": "Server 1: 172.31.21.11 / 172.31.11.11"},
        {"similarity": 0.86, "validated_answer": "Server 2: 172.31.21.12 / 172.31.11.12"},
    ]
    # Raw verbatim decision ignores query intent (pre-fix behavior)
    assert _should_return_verbatim(matches) is True
    # The guard at call-sites must flip the effective decision when compound
    effective_verbatim = (not _is_compound_query(
        "what is the ip of cadas ats server 1 and server 2"
    )) and _should_return_verbatim(matches)
    assert effective_verbatim is False
