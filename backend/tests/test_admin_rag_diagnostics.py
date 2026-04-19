"""
Contract tests for admin RAG diagnostics endpoints (spec 088).

These tests validate the request/response shapes defined in
specs/088-rag-refusal-diagnostic/contracts/diagnostic-api.md.

They run against a seeded Supabase instance and require an admin JWT.
Set ADMIN_EMAIL env var to the admin user's email (default: admin@example.com).
"""

import os
import uuid
from datetime import datetime, timezone

import httpx
import pytest

BASE_URL = os.environ.get("TEST_BASE_URL", "http://localhost:8000/api")
ADMIN_EMAIL = os.environ.get("ADMIN_EMAIL", "admin@example.com")
NON_ADMIN_EMAIL = os.environ.get("NON_ADMIN_EMAIL", "tech@example.com")


def _seed_entries(count: int = 3) -> list[dict]:
    """Insert count test rows and return them."""
    entries = []
    for i in range(count):
        decision = "ungrounded" if i < 2 else "grounded"
        reason_code = (
            "no_chunks_retrieved" if i == 0
            else "rerank_below_threshold" if i == 1
            else "grounded_answer"
        )
        entry = {
            "id": str(uuid.uuid4()),
            "created_at": datetime.now(timezone.utc).isoformat(),
            "user_email": "test@quality-check.local",
            "source": "test_suite",
            "question_raw": f"Test question {i}",
            "decision": decision,
            "reason_code": reason_code,
            "reason_note": f"Test note {i}",
            "pipeline_stages": {"retrieval": {"candidates": [], "k": 0}},
            "thresholds": {"max_chunk_distance": 0.55, "verbatim_match_min": 0.85},
            "latency_breakdown": {"total_ms": 1000 + i * 100},
            "provider_used": "gemini",
        }
        entries.append(entry)
    return entries


def _cleanup(entry_ids: list[str]):
    """Remove seeded entries by ID."""
    from db import supabase
    try:
        supabase.table("rag_diagnostic_log").delete().in_("id", entry_ids).execute()
    except Exception:
        pass


@pytest.fixture
def seeded_data():
    """Seed 3 rows and clean up after the test."""
    from db import supabase
    entries = _seed_entries(3)
    try:
        supabase.table("rag_diagnostic_log").insert(entries).execute()
    except Exception:
        pytest.skip("Cannot seed rag_diagnostic_log — table may not exist yet")
    entry_ids = [e["id"] for e in entries]
    yield entries
    _cleanup(entry_ids)


@pytest.mark.asyncio
async def test_list_endpoint_returns_expected_schema(seeded_data):
    """Contract §2: List endpoint returns entries with expected fields, omitting pipeline_stages and thresholds."""
    params = {
        "user_email": ADMIN_EMAIL,
        "decision": "ungrounded",
        "limit": 50,
        "offset": 0,
    }
    async with httpx.AsyncClient(verify=False, timeout=30) as client:
        resp = await client.get(f"{BASE_URL}/admin/rag-diagnostics", params=params)

    assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
    data = resp.json()

    assert "entries" in data, "Response must have 'entries' key"
    assert "total" in data, "Response must have 'total' key"
    assert "limit" in data, "Response must have 'limit' key"
    assert "offset" in data, "Response must have 'offset' key"

    ungrounded = [e for e in data["entries"] if e["decision"] == "ungrounded"]
    assert len(ungrounded) >= 2, "Should have at least 2 ungrounded entries"

    for entry in ungrounded:
        for field in ["id", "created_at", "user_email", "source", "question_raw",
                       "decision", "reason_code", "reason_note", "provider_used",
                       "latency_breakdown"]:
            assert field in entry, f"Entry missing field: {field}"
        assert "pipeline_stages" not in entry, "pipeline_stages must be omitted from list"
        assert "thresholds" not in entry, "thresholds must be omitted from list"


@pytest.mark.asyncio
async def test_detail_endpoint_returns_full_payload(seeded_data):
    """Contract §3: Detail endpoint returns all 11 columns including JSONB payloads."""
    target = seeded_data[0]
    params = {"user_email": ADMIN_EMAIL}

    async with httpx.AsyncClient(verify=False, timeout=30) as client:
        resp = await client.get(
            f"{BASE_URL}/admin/rag-diagnostics/{target['id']}",
            params=params,
        )

    assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
    data = resp.json()

    for field in ["id", "created_at", "user_email", "source", "question_raw",
                   "decision", "reason_code", "reason_note", "pipeline_stages",
                   "thresholds", "latency_breakdown", "provider_used"]:
        assert field in data, f"Detail missing field: {field}"

    assert isinstance(data["pipeline_stages"], dict)
    assert isinstance(data["thresholds"], dict)


@pytest.mark.asyncio
async def test_detail_endpoint_404():
    """Contract §3: Unknown ID returns 404."""
    fake_id = str(uuid.uuid4())
    params = {"user_email": ADMIN_EMAIL}

    async with httpx.AsyncClient(verify=False, timeout=30) as client:
        resp = await client.get(
            f"{BASE_URL}/admin/rag-diagnostics/{fake_id}",
            params=params,
        )

    assert resp.status_code == 404, f"Expected 404, got {resp.status_code}"


@pytest.mark.asyncio
async def test_detail_endpoint_403_for_non_admin():
    """Contract §3: Non-admin JWT returns 403."""
    fake_id = str(uuid.uuid4())
    params = {"user_email": NON_ADMIN_EMAIL}

    async with httpx.AsyncClient(verify=False, timeout=30) as client:
        resp = await client.get(
            f"{BASE_URL}/admin/rag-diagnostics/{fake_id}",
            params=params,
        )

    assert resp.status_code == 403, f"Expected 403, got {resp.status_code}"


@pytest.mark.asyncio
async def test_list_endpoint_403_for_non_admin():
    """Non-admin JWT returns 403 on list endpoint."""
    params = {"user_email": NON_ADMIN_EMAIL, "limit": 10, "offset": 0}

    async with httpx.AsyncClient(verify=False, timeout=30) as client:
        resp = await client.get(f"{BASE_URL}/admin/rag-diagnostics", params=params)

    assert resp.status_code == 403, f"Expected 403, got {resp.status_code}"