"""Fix B: ensure validated_qa rows always get `manual_ids` populated at
creation time, using the rating's manual_id when present and falling back
to `detect_system(question_text) -> get_manual_ids_for_system()` when not.

Without this, the topic filter in `check_validated_match` is a no-op on
every row (observed in prod 2026-04-20: CADAS-IMS row slipped into
CADAS-ATS synthesis context).
"""

from unittest.mock import AsyncMock, patch

import pytest

from services.validated_qa_service import _derive_manual_ids


@pytest.mark.asyncio
async def test_derive_prefers_rating_manual_id():
    """If the rating row has manual_id, use it verbatim — rating origin is
    authoritative over keyword detection."""
    result = await _derive_manual_ids(
        "how to restart the server",  # ambiguous question
        rating_manual_id="rating-manual-123",
    )
    assert result == ["rating-manual-123"]


@pytest.mark.asyncio
async def test_derive_falls_back_to_keyword_detection():
    """No rating manual_id → detect from question text, resolve to manual IDs."""
    with patch(
        "services.system_registry.get_manual_ids_for_system",
        new_callable=AsyncMock,
        return_value=["ats-manual-1", "ats-manual-2"],
    ):
        result = await _derive_manual_ids(
            "what is the ip of cadas ats server 1",
            rating_manual_id=None,
        )
    assert result == ["ats-manual-1", "ats-manual-2"]


@pytest.mark.asyncio
async def test_derive_returns_empty_when_no_system_detected():
    """Generic questions with no system keyword → empty (filter will fall open
    for these, preserving current behavior for untaggable rows)."""
    result = await _derive_manual_ids(
        "how do I check the database",  # no recognized system alias
        rating_manual_id=None,
    )
    assert result == []


@pytest.mark.asyncio
async def test_derive_returns_empty_when_keyword_detected_but_no_manuals():
    """System keyword matched but no manuals indexed for it → empty list."""
    with patch(
        "services.system_registry.get_manual_ids_for_system",
        new_callable=AsyncMock,
        return_value=[],
    ):
        result = await _derive_manual_ids(
            "what is the ip of cadas ats server 1",
            rating_manual_id=None,
        )
    assert result == []
