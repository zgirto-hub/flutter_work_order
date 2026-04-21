import asyncio
import time
from collections import defaultdict
from typing import Tuple

_MINUTE_LIMIT = 10
_DAY_LIMIT = 100
_MINUTE_WINDOW = 60
_DAY_WINDOW = 86400


class RateLimiter:
    def __init__(self):
        self._minute_requests: dict[str, list[float]] = defaultdict(list)
        self._day_requests: dict[str, list[float]] = defaultdict(list)
        self._lock = asyncio.Lock()

    def _prune(self, key: str) -> None:
        now = time.monotonic()
        minute_cutoff = now - _MINUTE_WINDOW
        day_cutoff = now - _DAY_WINDOW
        self._minute_requests[key] = [
            t for t in self._minute_requests[key] if t > minute_cutoff
        ]
        self._day_requests[key] = [
            t for t in self._day_requests[key] if t > day_cutoff
        ]
        if not self._day_requests[key]:
            del self._day_requests[key]
            self._minute_requests.pop(key, None)

    async def check(self, user_email: str) -> Tuple[bool, int]:
        async with self._lock:
            self._prune(user_email)
            minute_count = len(self._minute_requests.get(user_email, []))
            day_count = len(self._day_requests.get(user_email, []))

            if minute_count >= _MINUTE_LIMIT:
                oldest_in_minute = self._minute_requests[user_email][0]
                retry_after = int(
                    oldest_in_minute + _MINUTE_WINDOW - time.monotonic()
                ) + 1
                return False, max(retry_after, 1)

            if day_count >= _DAY_LIMIT:
                oldest_in_day = self._day_requests[user_email][0]
                retry_after = int(
                    oldest_in_day + _DAY_WINDOW - time.monotonic()
                ) + 1
                return False, max(retry_after, 1)

            now = time.monotonic()
            self._minute_requests[user_email].append(now)
            self._day_requests[user_email].append(now)
            return True, 0

    async def check_without_increment(self, user_email: str) -> Tuple[bool, int]:
        async with self._lock:
            self._prune(user_email)
            minute_count = len(self._minute_requests.get(user_email, []))
            day_count = len(self._day_requests.get(user_email, []))

            if minute_count >= _MINUTE_LIMIT:
                oldest_in_minute = self._minute_requests[user_email][0]
                retry_after = int(
                    oldest_in_minute + _MINUTE_WINDOW - time.monotonic()
                ) + 1
                return False, max(retry_after, 1)

            if day_count >= _DAY_LIMIT:
                oldest_in_day = self._day_requests[user_email][0]
                retry_after = int(
                    oldest_in_day + _DAY_WINDOW - time.monotonic()
                ) + 1
                return False, max(retry_after, 1)

            return True, 0

    async def cleanup_stale(self) -> None:
        async with self._lock:
            stale_keys = [
                key
                for key in list(self._day_requests.keys())
                if not self._day_requests[key]
                or all(t < time.monotonic() - _DAY_WINDOW for t in self._day_requests[key])
            ]
            for key in stale_keys:
                self._day_requests.pop(key, None)
                self._minute_requests.pop(key, None)


rate_limiter = RateLimiter()