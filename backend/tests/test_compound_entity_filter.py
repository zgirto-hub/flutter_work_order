"""Regression: compound-verbatim must only include matches that actually
address one of the entities named in the query. Otherwise a high-similarity
but topically-irrelevant row (e.g. "cadas ats system username/password"
ranking 2nd on a "server 1 and server 2 ip" query) gets concatenated
into the answer alongside the IPs row.

Observed 2026-04-20: answer contained "Server 2 IPs ... Username: aftn
Password: Aftnlinux1" — Server 1 was missing, credentials were not asked.
"""

import pytest

from services.manual_rag_service import (
    _extract_compound_entities,
    _filter_matches_by_entities,
)


@pytest.mark.parametrize(
    "query,expected",
    [
        ("what is the ip of cadas ats server 1 and server 2",
         {"server 1", "server 2"}),
        ("both server 1 and server 2 ip",
         {"server 1", "server 2"}),
        ("ips of servers 1 and 2",
         set()),  # "servers 1" not matched — entity detector expects singular+number
        ("list device 3 and device 7 configs",
         {"device 3", "device 7"}),
        ("what is the ip of cadas ats server 1",  # single entity
         {"server 1"}),
        ("", set()),
    ],
    ids=["server_1_and_2", "bare_and", "plural_form", "devices", "single", "empty"],
)
def test_extract_compound_entities(query, expected):
    assert _extract_compound_entities(query) == expected


def test_filter_keeps_matches_whose_question_mentions_entity():
    """When the query names server 1 / server 2, drop rows about "cadas ats
    system password" — they match by system but not by entity."""
    matches = [
        {"id": "a", "question_text": "what is cadas ats server 2 ip?",
         "validated_answer": "Server 2 IPs"},
        {"id": "b", "question_text": "what is the username and password for cadas ats system?",
         "validated_answer": "Username: aftn"},
        {"id": "c", "question_text": "what is cadas ats server 1 ip?",
         "validated_answer": "Server 1 IPs"},
    ]
    entities = {"server 1", "server 2"}
    kept = _filter_matches_by_entities(matches, entities)
    kept_ids = {m["id"] for m in kept}
    assert kept_ids == {"a", "c"}


def test_filter_passthrough_when_no_entities():
    """If we couldn't extract entities, don't filter — preserves behavior
    for non-compound paths."""
    matches = [{"id": "a", "question_text": "anything"}]
    kept = _filter_matches_by_entities(matches, set())
    assert kept == matches


def test_filter_empty_matches():
    assert _filter_matches_by_entities([], {"server 1"}) == []


def test_compound_verbatim_uses_entity_filter_and_falls_back_when_insufficient():
    """When entity filtering leaves < 2 distinct matches, caller should
    reject compound-verbatim. The answer builder returns "" so caller
    can detect insufficient-post-filter."""
    from services.manual_rag_service import _build_compound_verbatim_answer_filtered

    matches = [
        {"id": "a", "question_text": "cadas ats server 2 ip", "validated_answer": "Server 2 IPs"},
        {"id": "b", "question_text": "cadas ats username/password", "validated_answer": "creds"},
    ]
    # Only Server 2 survives entity filter → can't do compound → return empty
    result = _build_compound_verbatim_answer_filtered(
        "server 1 and server 2 ip",
        matches,
    )
    assert result == "", "single surviving entity can't be compound-verbatim"


def test_compound_verbatim_filtered_returns_only_entity_matches():
    from services.manual_rag_service import _build_compound_verbatim_answer_filtered

    matches = [
        {"id": "a", "question_text": "cadas ats server 2 ip", "validated_answer": "Server 2 IPs"},
        {"id": "b", "question_text": "cadas ats username/password", "validated_answer": "creds"},
        {"id": "c", "question_text": "cadas ats server 1 ip", "validated_answer": "Server 1 IPs"},
    ]
    result = _build_compound_verbatim_answer_filtered(
        "ip of server 1 and server 2", matches
    )
    assert "Server 1 IPs" in result
    assert "Server 2 IPs" in result
    assert "creds" not in result
