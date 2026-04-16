import pytest
from services.contextual_prefix import build_contextual_prefix, apply_contextual_prefix


def test_build_prefix_with_title_and_section():
    result = build_contextual_prefix("CADAS-IMS", "Alarm Config")
    assert result == "CADAS-IMS > Alarm Config: "


def test_build_prefix_with_title_only():
    result = build_contextual_prefix("CADAS-IMS")
    assert result == "CADAS-IMS: "


def test_build_prefix_with_empty_title():
    result = build_contextual_prefix("")
    assert result == ""


def test_build_prefix_with_none_title():
    result = build_contextual_prefix(None)
    assert result == ""


def test_build_prefix_with_whitespace_title():
    result = build_contextual_prefix("  ")
    assert result == ""


def test_build_prefix_with_none_section():
    result = build_contextual_prefix("Doc", None)
    assert result == "Doc: "


def test_build_prefix_with_empty_section():
    result = build_contextual_prefix("Doc", "")
    assert result == "Doc: "


def test_apply_prefix_normal():
    result = apply_contextual_prefix("chunk text", "Doc", "Section")
    assert result == "Doc > Section: chunk text"


def test_apply_prefix_no_title():
    result = apply_contextual_prefix("chunk text", None)
    assert result == "chunk text"


def test_apply_prefix_truncation():
    content = "x" * 29990
    result = apply_contextual_prefix(content, "x" * 100, None)
    assert result.startswith("...x")
    assert result.endswith(content)
