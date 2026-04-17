import asyncio
import logging
import time
from typing import List, Tuple, AsyncIterator
from utils.app_settings import get_setting, set_setting
from utils.activity import log_activity
from . import PROVIDERS
from .base import AIProvider
from services.ollama_generator import GeneratorModelError, GeneratorTimeoutError

logger = logging.getLogger(__name__)

_cache: dict = {"value": None, "expires_at": 0.0}
_TTL_SECONDS = 60.0
_DEFAULT_PROVIDER = "local"
_FALLBACK_PROVIDER = "local"  # Always fall back to Ollama, regardless of default


async def get_active_provider_key() -> str:
    if _cache["value"] is not None and time.monotonic() < _cache["expires_at"]:
        return _cache["value"]

    try:
        value = await get_setting("ai_provider")
        if value:
            _cache["value"] = value
            _cache["expires_at"] = time.monotonic() + _TTL_SECONDS
            return value
    except Exception as e:
        logger.error(f"Failed to get active provider: {e}")

    if _cache["value"]:
        return _cache["value"]
    return _DEFAULT_PROVIDER


def _resolve_provider(key: str) -> AIProvider:
    provider_class = PROVIDERS.get(key)
    if not provider_class:
        raise ValueError(f"Unknown provider: {key}")
    return provider_class()


def invalidate_cache() -> None:
    _cache["expires_at"] = 0.0


async def generate(
    prompt: str,
    context_chunks: List[str],
    user_email: str | None = None,
    latency_breakdown: dict | None = None,
) -> Tuple[str, str, str, bool, dict | None]:
    # spec-065 contract: returns (answer, provider_key, display_name, fallback_used, fallback_info).
    # When fallback_used is True, fallback_info is a non-null dict that the CALLER must
    # propagate up and the outermost handler (currently backend/routers/manuals.py
    # /manuals/ask) must consume to write exactly one user_activity_log row with
    # action="ai_provider_fallback". Dropping fallback_info on the floor silently loses
    # the audit row. Any new call site must thread it through unchanged.
    # Spec 076: All failures (timeout, error, 429, missing creds) trigger identical per-request fallback to Ollama
    active_key = await get_active_provider_key()
    active = _resolve_provider(active_key)
    active_display = active.display_name

    try:
        _gen_start = time.perf_counter()
        try:
            answer = await asyncio.wait_for(
                active.generate(prompt, context_chunks), timeout=30.0
            )
        finally:
            if latency_breakdown is not None:
                latency_breakdown["generator_ms"] = round(
                    (time.perf_counter() - _gen_start) * 1000
                )
        if not answer or not answer.strip():
            raise GeneratorModelError(active_key, "empty_response")
        return (answer.strip(), active_key, active_display, False, None)
    except asyncio.TimeoutError as exc:
        logger.warning(f"Provider {active_key} timed out")
        if active_key != _FALLBACK_PROVIDER:
            # Clear the primary's partial timing so the fallback can overwrite
            # generator_ms with the successful call's elapsed (FR-013).
            if latency_breakdown is not None:
                latency_breakdown["generator_ms"] = None
            return await _fallback_to_local(
                prompt,
                context_chunks,
                user_email,
                active_key,
                "timeout_30s",
                exc,
                latency_breakdown=latency_breakdown,
            )
        raise GeneratorTimeoutError(f"Provider {active_key} timed out after 30s")
    except Exception as e:
        logger.warning(f"Provider {active_key} failed: {e}")
        if active_key != _FALLBACK_PROVIDER:
            if latency_breakdown is not None:
                latency_breakdown["generator_ms"] = None
            reason = str(e) if str(e) else type(e).__name__
            return await _fallback_to_local(
                prompt,
                context_chunks,
                user_email,
                active_key,
                reason,
                e,
                latency_breakdown=latency_breakdown,
            )
        raise


async def generate_stream(
    prompt: str,
    context_chunks: List[str],
    user_email: str | None = None,
    latency_breakdown: dict | None = None,
    stream_meta: dict | None = None,
) -> AsyncIterator[str]:
    """Yield answer tokens one chunk at a time with fallback support."""
    if stream_meta is None:
        stream_meta = {}

    stream_meta["provider_key"] = ""
    stream_meta["display_name"] = ""
    stream_meta["fallback_used"] = False
    stream_meta["fallback_info"] = None

    active_key = await get_active_provider_key()
    active = _resolve_provider(active_key)
    active_display = active.display_name
    stream_meta["provider_key"] = active_key
    stream_meta["display_name"] = active_display

    _gen_start = time.perf_counter()
    first_chunk_yielded = False

    try:
        async for token in asyncio.wait_for(
            active.generate_stream(prompt, context_chunks), timeout=30.0
        ):
            if not first_chunk_yielded:
                first_chunk_yielded = True
                if latency_breakdown is not None:
                    latency_breakdown["generator_ms"] = round(
                        (time.perf_counter() - _gen_start) * 1000
                    )
            yield token
        return
    except asyncio.TimeoutError as exc:
        logger.warning(f"Provider {active_key} timed out")
        if active_key != _FALLBACK_PROVIDER:
            if latency_breakdown is not None:
                latency_breakdown["generator_ms"] = None
            async for token in _fallback_stream(
                prompt,
                context_chunks,
                user_email,
                active_key,
                "timeout_30s",
                latency_breakdown,
                stream_meta,
            ):
                yield token
            return
        raise GeneratorTimeoutError(f"Provider {active_key} timed out after 30s")
    except Exception as e:
        logger.warning(f"Provider {active_key} failed: {e}")
        if active_key != _FALLBACK_PROVIDER:
            if latency_breakdown is not None:
                latency_breakdown["generator_ms"] = None
            reason = str(e) if str(e) else type(e).__name__
            async for token in _fallback_stream(
                prompt,
                context_chunks,
                user_email,
                active_key,
                reason,
                latency_breakdown,
                stream_meta,
            ):
                yield token
            return
        raise


async def _fallback_stream(
    prompt: str,
    context_chunks: List[str],
    user_email: str | None,
    failed_provider_key: str,
    reason: str,
    latency_breakdown: dict | None,
    stream_meta: dict,
) -> AsyncIterator[str]:
    """Fallback to local provider with streaming."""
    local = _resolve_provider(_FALLBACK_PROVIDER)
    local_display = local.display_name
    stream_meta["provider_key"] = _FALLBACK_PROVIDER
    stream_meta["display_name"] = local_display
    stream_meta["fallback_used"] = True
    stream_meta["fallback_info"] = {
        "user_email": user_email,
        "failed_provider": failed_provider_key,
        "fallback_provider": _FALLBACK_PROVIDER,
        "detail": _classify_fallback_reason(reason, None),
    }

    _fb_start = time.perf_counter()
    first_chunk_yielded = False

    try:
        async for token in local.generate_stream(prompt, context_chunks):
            if not first_chunk_yielded:
                first_chunk_yielded = True
                if latency_breakdown is not None:
                    latency_breakdown["generator_ms"] = round(
                        (time.perf_counter() - _fb_start) * 1000
                    )
            yield token
    except Exception as e:
        if latency_breakdown is not None:
            latency_breakdown["generator_ms"] = round(
                (time.perf_counter() - _fb_start) * 1000
            )
        raise


def _classify_fallback_reason(reason: str, exc: Exception | None = None) -> str:
    if exc is not None:
        if isinstance(exc, asyncio.TimeoutError):
            return "timeout_30s"
        if isinstance(exc, GeneratorModelError):
            bare = (getattr(exc, "detail", "") or "").lower()
            if bare in {
                "quota_exceeded",
                "timeout_30s",
                "empty_response",
                "missing_credentials",
            }:
                return bare
    reason_lower = reason.lower()
    if "timeout" in reason_lower:
        return "timeout_30s"
    if "quota" in reason_lower or "429" in reason_lower:
        return "quota_exceeded"
    if "missing_credentials" in reason_lower:
        return "missing_credentials"
    if "empty_response" in reason_lower:
        return "empty_response"
    return "unknown"


async def _fallback_to_local(
    prompt: str,
    context_chunks: List[str],
    user_email: str | None,
    failed_provider_key: str,
    reason: str,
    exc: Exception | None = None,
    latency_breakdown: dict | None = None,
) -> Tuple[str, str, str, bool, dict | None]:
    local = _resolve_provider(_FALLBACK_PROVIDER)
    local_display = local.display_name
    _fb_start = time.perf_counter()
    try:
        answer = await local.generate(prompt, context_chunks)
    finally:
        if latency_breakdown is not None:
            latency_breakdown["generator_ms"] = round(
                (time.perf_counter() - _fb_start) * 1000
            )
    detail = _classify_fallback_reason(reason, exc)
    fallback_info = None
    if user_email:
        fallback_info = {
            "user_email": user_email,
            "failed_provider": failed_provider_key,
            "fallback_provider": _FALLBACK_PROVIDER,
            "detail": detail,
        }
    return (answer, _FALLBACK_PROVIDER, local_display, True, fallback_info)


async def _migrate_default_provider() -> None:
    """One-time migration: rewrite stored 'gemini' default to 'local' (Ollama).

    Idempotent — runs on every startup but only mutates state when the stored
    value is exactly 'gemini'. Safe across Uvicorn worker restarts: whichever
    worker wins the first UPDATE observes `current == "gemini"` exactly once;
    subsequent starts (same worker or new) observe 'local' and skip.
    Failures are logged and swallowed — migration MUST NOT block startup.
    """
    try:
        current = await get_setting("ai_provider")
        if current == "gemini":
            await set_setting("ai_provider", "local")
            invalidate_cache()
            log_activity(
                "system",
                category="admin",
                action="ai_provider_migrated",
                target_label="local",
                detail="old=gemini",
            )
            logger.info("Migrated ai_provider from 'gemini' to 'local' (Ollama)")
    except Exception as e:
        logger.error(f"ai_provider migration to local failed: {e}")
