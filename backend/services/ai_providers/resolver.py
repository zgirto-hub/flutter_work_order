import asyncio
import logging
import time
from typing import List, Tuple
from utils.app_settings import get_setting
from utils.activity import log_activity
from . import PROVIDERS
from .base import AIProvider
from services.ollama_generator import GeneratorModelError, GeneratorTimeoutError

logger = logging.getLogger(__name__)

_cache: dict = {"value": None, "expires_at": 0.0}
_TTL_SECONDS = 60.0
_DEFAULT_PROVIDER = "local"


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
) -> Tuple[str, str, str, bool]:
    active_key = await get_active_provider_key()
    active = _resolve_provider(active_key)
    active_display = active.display_name

    try:
        answer = await asyncio.wait_for(
            active.generate(prompt, context_chunks), timeout=30.0
        )
        if not answer or not answer.strip():
            raise GeneratorModelError(active_key, "empty_response")
        return (answer.strip(), active_key, active_display, False)
    except asyncio.TimeoutError as exc:
        logger.warning(f"Provider {active_key} timed out")
        if active_key != _DEFAULT_PROVIDER:
            return await _fallback_to_local(
                prompt, context_chunks, user_email, active_key, "timeout_30s", exc
            )
        raise GeneratorTimeoutError(f"Provider {active_key} timed out after 30s")
    except Exception as e:
        logger.warning(f"Provider {active_key} failed: {e}")
        if active_key != _DEFAULT_PROVIDER:
            reason = str(e) if str(e) else type(e).__name__
            return await _fallback_to_local(
                prompt, context_chunks, user_email, active_key, reason, e
            )
        raise


def _classify_fallback_reason(reason: str, exc: Exception | None = None) -> str:
    reason_lower = reason.lower()
    if exc is not None:
        if isinstance(exc, asyncio.TimeoutError):
            return "timeout_30s"
    if "timeout" in reason_lower:
        return "timeout_30s"
    if "quota" in reason_lower or "429" in reason_lower:
        return "quota_exceeded"
    if reason_lower == "missing_credentials":
        return "missing_credentials"
    if reason_lower == "empty_response":
        return "empty_response"
    return "unknown"


async def _fallback_to_local(
    prompt: str,
    context_chunks: List[str],
    user_email: str | None,
    failed_provider_key: str,
    reason: str,
    exc: Exception | None = None,
) -> Tuple[str, str, str, bool]:
    try:
        local = _resolve_provider(_DEFAULT_PROVIDER)
        local_display = local.display_name
        answer = await local.generate(prompt, context_chunks)
        if user_email:
            try:
                detail = _classify_fallback_reason(reason, exc)
                log_activity(
                    user_email,
                    category="admin",
                    action="ai_provider_fallback",
                    target_label=failed_provider_key,
                    target_id=_DEFAULT_PROVIDER,
                    detail=detail,
                )
            except Exception:
                pass
        return (answer, _DEFAULT_PROVIDER, local_display, True)
    except Exception:
        raise GeneratorTimeoutError(f"All providers failed: {reason}")
