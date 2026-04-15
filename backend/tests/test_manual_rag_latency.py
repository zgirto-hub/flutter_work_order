"""
Contract + integration tests for spec 066 per-stage latency breakdown.

Strategy
--------
- Helper-level unit tests for `_StageTimer` and `_empty_latency_breakdown` —
  these are cheap and catch the basic invariants.
- Resolver-level integration test for the generator_ms units bug (the one
  that shipped in round 1 because only unit tests existed). Monkeypatches
  the active provider to sleep a known amount and asserts the breakdown
  records an integer-millisecond value, not seconds.
- Endpoint-level contract tests via FastAPI TestClient against a fresh
  `FastAPI()` that mounts ONLY `routers.manuals:router`, so we can avoid
  `fitz`/Ollama/Supabase imports coming in through `backend/main.py`.

If the full app can't be imported in this environment (e.g. fitz missing),
the TestClient-mounted-subset pattern documented in F5.3 is how we get
endpoint coverage anyway.
"""

from __future__ import annotations

import asyncio
import time
from unittest.mock import patch, AsyncMock

import pytest


# ---------------------------------------------------------------------------
# Helper-level unit tests (the only tests the previous iteration shipped).
# Kept because they ARE the right level for the primitives themselves.
# ---------------------------------------------------------------------------


class TestStageTimerAndInitializer:
    def test_empty_breakdown_has_all_seven_keys(self):
        from services.manual_rag_service import _empty_latency_breakdown

        b = _empty_latency_breakdown()
        for key in (
            "embed_ms",
            "hyde_ms",
            "rewrite_ms",
            "retrieval_ms",
            "rerank_ms",
            "generator_ms",
            "total_ms",
        ):
            assert key in b, f"missing key {key}"
            assert b[key] is None, f"{key} should start as None, got {b[key]!r}"

    def test_stage_timer_records_elapsed_on_success(self):
        from services.manual_rag_service import _StageTimer

        breakdown = {}
        with _StageTimer(breakdown, "embed_ms"):
            time.sleep(0.015)

        assert isinstance(breakdown["embed_ms"], int)
        assert 10 <= breakdown["embed_ms"] < 1000

    def test_stage_timer_records_none_on_exception_and_propagates(self):
        from services.manual_rag_service import _StageTimer

        breakdown = {}
        with pytest.raises(RuntimeError):
            with _StageTimer(breakdown, "embed_ms"):
                raise RuntimeError("boom")
        assert breakdown["embed_ms"] is None


# ---------------------------------------------------------------------------
# Resolver-level test: generator_ms is integer milliseconds, not seconds.
# This is the test that would have caught round-1's seconds-as-ms bug.
# ---------------------------------------------------------------------------


class _FakeProvider:
    display_name = "Fake (Test)"

    def __init__(self, sleep_s: float = 0.05):
        self._sleep_s = sleep_s

    async def generate(self, prompt, context_chunks):
        await asyncio.sleep(self._sleep_s)
        return "ok"


class TestResolverGeneratorMs:
    @pytest.mark.asyncio
    async def test_generator_ms_is_integer_milliseconds_not_seconds(self, monkeypatch):
        """A 50ms provider call must record ~50 ms, never ~0 (seconds treated as ms)."""
        from services.ai_providers import resolver as resolver_mod

        async def _fake_active_key():
            return "local"  # take the no-fallback happy path

        monkeypatch.setattr(
            resolver_mod, "get_active_provider_key", _fake_active_key
        )
        monkeypatch.setattr(
            resolver_mod,
            "_resolve_provider",
            lambda key: _FakeProvider(sleep_s=0.05),
        )

        breakdown = {"generator_ms": None}
        answer, key, disp, fell_back, info = await resolver_mod.generate(
            "prompt", [], user_email=None, latency_breakdown=breakdown
        )
        assert answer == "ok"
        assert fell_back is False
        # 50ms wall clock ± jitter — must be integer ms, not single-digit seconds.
        assert isinstance(breakdown["generator_ms"], int)
        assert 40 <= breakdown["generator_ms"] <= 500

    @pytest.mark.asyncio
    async def test_fallback_generator_ms_reflects_successful_fallback_only(
        self, monkeypatch
    ):
        """Primary raises; fallback succeeds after ~30ms. generator_ms must reflect
        the fallback call, not the failed primary attempt (FR-013)."""
        from services.ai_providers import resolver as resolver_mod

        async def _fake_active_key():
            return "groq"  # not local → fallback path will trigger

        class _FailingPrimary:
            display_name = "Groq (test)"

            async def generate(self, prompt, chunks):
                raise RuntimeError("quota_exceeded")

        def _resolve(key):
            return _FailingPrimary() if key != "local" else _FakeProvider(sleep_s=0.03)

        monkeypatch.setattr(
            resolver_mod, "get_active_provider_key", _fake_active_key
        )
        monkeypatch.setattr(resolver_mod, "_resolve_provider", _resolve)

        breakdown = {"generator_ms": None}
        answer, key, disp, fell_back, info = await resolver_mod.generate(
            "prompt", [], user_email=None, latency_breakdown=breakdown
        )
        assert fell_back is True
        assert key == "local"
        assert isinstance(breakdown["generator_ms"], int)
        assert 20 <= breakdown["generator_ms"] <= 500


# ---------------------------------------------------------------------------
# Endpoint-level contract tests — mount only the manuals router so we avoid
# `fitz` and other heavy deps that make `backend.main` unimportable in CI.
# ---------------------------------------------------------------------------


@pytest.fixture
def client():
    """Mount only routers.manuals on a fresh FastAPI app for contract tests."""
    pytest.importorskip("fastapi.testclient")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient
    from routers.manuals import router as manuals_router

    app = FastAPI()
    app.include_router(manuals_router)
    return TestClient(app)


class TestAskEndpointContract:
    def test_greeting_bypass_returns_six_nulls_and_small_integer_total(self, client):
        """question='hi' → bypass path; all stage keys None, total_ms small int."""
        resp = client.post(
            "/manuals/ask",
            json={"question": "hi", "user_email": "test@example.com", "history": []},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body.get("bypass") == "greeting"
        lb = body["latency_breakdown"]
        for key in (
            "embed_ms",
            "hyde_ms",
            "rewrite_ms",
            "retrieval_ms",
            "rerank_ms",
            "generator_ms",
        ):
            assert lb[key] is None, f"{key} should be null on bypass"
        assert isinstance(lb["total_ms"], int)
        # Guard against the round-1 seconds-since-boot bug: bypass should
        # be well under a second. Generous ceiling for slow CI.
        assert 0 <= lb["total_ms"] < 1000, (
            f"total_ms looks like it is NOT elapsed: {lb['total_ms']}"
        )

    def test_ask_response_contains_all_seven_keys(self, client):
        """Non-bypass request → response shape always has all seven keys."""
        fake_result = {
            "answer": "Mocked answer.",
            "sources": [],
            "grounded": True,
            "agentic": False,
            "tools_used": [],
        }

        async def _fake_run_agentic_loop(
            question, manual_id_filter, *, latency_breakdown=None, **kwargs
        ):
            # Simulate the service populating the breakdown dict in-place,
            # exactly as production does via _StageTimer wrappers.
            if latency_breakdown is not None:
                latency_breakdown["embed_ms"] = 100
                latency_breakdown["hyde_ms"] = 3400
                latency_breakdown["rewrite_ms"] = 200
                latency_breakdown["retrieval_ms"] = 400
                latency_breakdown["rerank_ms"] = 170
                latency_breakdown["generator_ms"] = 1200
            out = dict(fake_result)
            if latency_breakdown is not None:
                out["latency_breakdown"] = latency_breakdown
            return out

        with patch(
            "routers.manuals.agentic_tools.run_agentic_loop",
            new=AsyncMock(side_effect=_fake_run_agentic_loop),
        ):
            resp = client.post(
                "/manuals/ask",
                json={
                    "question": "how do I restart the system?",
                    "user_email": "test@example.com",
                    "history": [],
                },
            )
        assert resp.status_code == 200, resp.text
        lb = resp.json()["latency_breakdown"]
        assert set(lb.keys()) == {
            "embed_ms",
            "hyde_ms",
            "rewrite_ms",
            "retrieval_ms",
            "rerank_ms",
            "generator_ms",
            "total_ms",
        }
        # Stage values that the service populated must survive to the client
        # (the router must NOT overwrite them with synthesized numbers).
        assert lb["embed_ms"] == 100
        assert lb["hyde_ms"] == 3400
        assert lb["rewrite_ms"] == 200
        assert lb["retrieval_ms"] == 400
        assert lb["rerank_ms"] == 170
        assert lb["generator_ms"] == 1200
        # total_ms is the router's wall-clock; must be a reasonable int >= 0,
        # and must NOT be a seconds-since-boot value.
        assert isinstance(lb["total_ms"], int)
        assert 0 <= lb["total_ms"] < 10_000

    def test_router_does_not_overwrite_service_breakdown_with_seconds(self, client):
        """
        Regression test for round-1 bug: router used to synthesize
        `generator_ms: result.get("duration_seconds", 0)`, which treated
        seconds as ms and clobbered the service's real values. Ensure that
        even when duration_seconds IS present in the result, the service's
        breakdown survives unchanged.
        """
        async def _fake_run_agentic_loop(
            question, manual_id_filter, *, latency_breakdown=None, **kwargs
        ):
            if latency_breakdown is not None:
                latency_breakdown["generator_ms"] = 1234  # real ms value
            return {
                "answer": "x",
                "sources": [],
                "grounded": True,
                "agentic": False,
                "tools_used": [],
                "duration_seconds": 22.4,  # the old overwrite trap
                "latency_breakdown": latency_breakdown,
            }

        with patch(
            "routers.manuals.agentic_tools.run_agentic_loop",
            new=AsyncMock(side_effect=_fake_run_agentic_loop),
        ):
            resp = client.post(
                "/manuals/ask",
                json={
                    "question": "tell me about X",
                    "user_email": "test@example.com",
                    "history": [],
                },
            )
        assert resp.status_code == 200, resp.text
        lb = resp.json()["latency_breakdown"]
        # Must be 1234 (the service's real ms), NOT 22 or 22.4 (seconds as ms).
        assert lb["generator_ms"] == 1234
