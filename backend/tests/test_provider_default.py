import pytest
from unittest.mock import patch, AsyncMock, MagicMock
from services.ai_providers.resolver import (
    _DEFAULT_PROVIDER,
    _FALLBACK_PROVIDER,
    _cache,
    get_active_provider_key,
    _migrate_default_provider,
    invalidate_cache,
)


def test_default_provider_constant_is_gemini():
    assert _DEFAULT_PROVIDER == "gemini"


def test_fallback_provider_is_local():
    assert _FALLBACK_PROVIDER == "local"


async def test_get_active_provider_falls_through_to_gemini_when_db_empty():
    invalidate_cache()
    _cache["value"] = None
    with patch(
        "services.ai_providers.resolver.get_setting", new=AsyncMock(return_value=None)
    ):
        result = await get_active_provider_key()
        assert result == "gemini"


async def test_migrate_rewrites_local_to_gemini():
    invalidate_cache()
    mock_set_setting = AsyncMock()
    mock_invalidate_cache = MagicMock()
    with (
        patch(
            "services.ai_providers.resolver.get_setting",
            new=AsyncMock(return_value="local"),
        ),
        patch(
            "services.ai_providers.resolver.set_setting",
            new=mock_set_setting,
        ),
        patch(
            "services.ai_providers.resolver.invalidate_cache",
            new=mock_invalidate_cache,
        ),
        patch(
            "services.ai_providers.resolver.log_activity",
        ) as mock_log,
    ):
        await _migrate_default_provider()
        mock_set_setting.assert_called_once_with("ai_provider", "gemini")
        mock_invalidate_cache.assert_called_once()
        mock_log.assert_called_once_with(
            "system",
            category="admin",
            action="ai_provider_migrated",
            target_label="gemini",
            detail="old=local",
        )


async def test_migrate_noop_when_already_gemini():
    invalidate_cache()
    mock_set_setting = AsyncMock()
    with (
        patch(
            "services.ai_providers.resolver.get_setting",
            new=AsyncMock(return_value="gemini"),
        ),
        patch(
            "services.ai_providers.resolver.set_setting",
            new=mock_set_setting,
        ),
        patch(
            "services.ai_providers.resolver.log_activity",
        ),
    ):
        await _migrate_default_provider()
        mock_set_setting.assert_not_called()


async def test_migrate_noop_when_no_row():
    invalidate_cache()
    mock_set_setting = AsyncMock()
    with (
        patch(
            "services.ai_providers.resolver.get_setting",
            new=AsyncMock(return_value=None),
        ),
        patch(
            "services.ai_providers.resolver.set_setting",
            new=mock_set_setting,
        ),
        patch(
            "services.ai_providers.resolver.log_activity",
        ),
    ):
        await _migrate_default_provider()
        mock_set_setting.assert_not_called()
