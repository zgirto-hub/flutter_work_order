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

_cache: dict = {"value": None, "expires_at": 0.0, "last_fallback_used": False}
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


async def generate(
    prompt: str,
    context_chunks: List[str],
    user_email: str | None = None,
) -> Tuple[str, str, bool]:
    active_key = await get_active_provider_key()
    active = _resolve_provider(active_key)

    try:
        answer = await asyncio.wait_for(
            active.generate(prompt, context_chunks), timeout=30.0
        )
        if not answer or not answer.strip():
            raise GeneratorModelError(active_key, "empty_response")
        _cache["last_fallback_used"] = False
        return (answer.strip(), active_key, False)
    except asyncio.TimeoutError:
        logger.warning(f"Provider {active_key} timed out")
        if active_key != _DEFAULT_PROVIDER:
            return await _fallback_to_local(
                prompt, context_chunks, user_email, "timeout>30s"
            )
        raise GeneratorTimeoutError(f"Provider {active_key} timed out after 30s")
    except Exception as e:
        logger.warning(f"Provider {active_key} failed: {e}")
        if active_key != _DEFAULT_PROVIDER:
            reason = type(e).__name__
            return await _fallback_to_local(
                prompt, context_chunks, user_email, f"exception:{reason}"
            )
        raise


async def _fallback_to_local(
    prompt: str,
    context_chunks: List[str],
    user_email: str | None,
    reason: str,
) -> Tuple[str, str, bool]:
    try:
        local = _resolve_provider(_DEFAULT_PROVIDER)
        answer = await local.generate(prompt, context_chunks)
        if user_email:
            try:
                log_activity(
                    user_email,
                    category="admin",
                    action="ai_provider_fallback",
                    target_label=reason,
                    target_id=_DEFAULT_PROVIDER,
                    detail=reason,
                )
            except Exception:
                pass
        _cache["last_fallback_used"] = True
        return (answer, _DEFAULT_PROVIDER, True)
    except Exception:
        raise GeneratorTimeoutError(f"All providers failed: {reason}")


async def get_last_provider_info() -> Tuple[str, bool]:
    return (
        _cache.get("value") or _DEFAULT_PROVIDER,
        _cache.get("last_fallback_used", False),
    )
