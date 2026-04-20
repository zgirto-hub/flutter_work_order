"""Regression: `check_validated_match` must filter out topic-mismatched
rows *per-row*, not only gate on the best match.

Context (session 2026-04-20, Q1 "ip of server 1 and server 2"):
The top-3 validated_qa matches contained two CADAS-ATS rows (Server 1, Server 2)
and one CADAS-IMS row (VNC connection procedure that happens to mention
"server 1 CONT" / "server 2 CONT" literally). The IMS row slipped into the
LLM context as Source 3 and confused Llama 4 Scout into claiming Server 1
was "not mentioned".

The existing guard only checked the best match — so if the best match was
on-topic, the off-topic rows rode along for free. This test asserts the
per-row filter behavior.
"""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from services import validated_qa_service


@pytest.fixture
def _mock_embed():
    with patch(
        "services.validated_qa_service.embed_single",
        new_callable=AsyncMock,
        return_value=[0.0] * 768,
    ):
        yield


@pytest.mark.asyncio
async def test_off_topic_rows_are_dropped_but_on_topic_rows_survive(_mock_embed):
    """detected_system='CADAS-ATS' → drop the CADAS-IMS row, keep the ATS rows."""

    def _row_lookup(row_id: str):
        # Map row-id to manual_ids so the filter can judge topic
        return {
            "row-ats-server-1": ["manual-ats-1"],
            "row-ats-server-2": ["manual-ats-1"],
            "row-ims-vnc": ["manual-ims-1"],  # off-topic!
        }[row_id]

    rpc_rows = [
        {"id": "row-ats-server-2", "question_text": "server 2 ip",
         "validated_answer": "cs2-cont 172.31.21.12", "validated_by": "x",
         "validated_at": "2026-01-01", "distance": 0.10},
        {"id": "row-ims-vnc", "question_text": "connect ims",
         "validated_answer": "vncviewer cims1-cont", "validated_by": "x",
         "validated_at": "2026-01-01", "distance": 0.22},
        {"id": "row-ats-server-1", "question_text": "server 1 ip",
         "validated_answer": "cs1-cont 172.31.21.11", "validated_by": "x",
         "validated_at": "2026-01-01", "distance": 0.12},
    ]

    def _table_select(_id):
        m = MagicMock()
        m.data = {"manual_ids": _row_lookup(_id)}
        return m

    mock_table = MagicMock()
    mock_table.select.return_value.eq.side_effect = lambda _col, row_id: (
        MagicMock(single=MagicMock(return_value=MagicMock(
            execute=MagicMock(return_value=_table_select(row_id))
        )))
    )

    with patch.object(validated_qa_service, "supabase") as mock_supabase:
        mock_supabase.rpc.return_value.execute.return_value = MagicMock(data=rpc_rows)
        mock_supabase.table.return_value = mock_table
        with patch(
            "services.system_registry.get_manual_ids_for_system",
            new_callable=AsyncMock,
            return_value=["manual-ats-1"],
        ):
            result = await validated_qa_service.check_validated_match(
                "what is the ip of server 1 and server 2",
                detected_system="CADAS-ATS",
            )

    ids = [m["id"] for m in result["matches"]]
    assert "row-ims-vnc" not in ids, "off-topic CADAS-IMS row should be filtered out"
    assert "row-ats-server-1" in ids
    assert "row-ats-server-2" in ids


@pytest.mark.asyncio
async def test_no_detected_system_keeps_every_row(_mock_embed):
    """When the router can't identify a system, don't filter — let the LLM decide."""
    rpc_rows = [
        {"id": "a", "question_text": "q1", "validated_answer": "a1",
         "validated_by": "x", "validated_at": "2026-01-01", "distance": 0.10},
        {"id": "b", "question_text": "q2", "validated_answer": "a2",
         "validated_by": "x", "validated_at": "2026-01-01", "distance": 0.15},
    ]
    with patch.object(validated_qa_service, "supabase") as mock_supabase:
        mock_supabase.rpc.return_value.execute.return_value = MagicMock(data=rpc_rows)
        result = await validated_qa_service.check_validated_match("anything", detected_system=None)
    assert len(result["matches"]) == 2


@pytest.mark.asyncio
async def test_all_rows_off_topic_returns_empty(_mock_embed):
    """If every row is off-topic, fall back to empty (not the old all-or-nothing bug)."""
    rpc_rows = [
        {"id": "row-ims-vnc", "question_text": "ims vnc",
         "validated_answer": "vncviewer cims1-cont", "validated_by": "x",
         "validated_at": "2026-01-01", "distance": 0.12},
    ]

    def _table_select(_id):
        m = MagicMock()
        m.data = {"manual_ids": ["manual-ims-1"]}
        return m

    mock_table = MagicMock()
    mock_table.select.return_value.eq.side_effect = lambda _col, row_id: (
        MagicMock(single=MagicMock(return_value=MagicMock(
            execute=MagicMock(return_value=_table_select(row_id))
        )))
    )

    with patch.object(validated_qa_service, "supabase") as mock_supabase:
        mock_supabase.rpc.return_value.execute.return_value = MagicMock(data=rpc_rows)
        mock_supabase.table.return_value = mock_table
        with patch(
            "services.system_registry.get_manual_ids_for_system",
            new_callable=AsyncMock,
            return_value=["manual-ats-1"],
        ):
            result = await validated_qa_service.check_validated_match(
                "cadas-ats server 1 ip", detected_system="CADAS-ATS"
            )
    assert result["matches"] == []
