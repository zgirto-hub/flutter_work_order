import os
import httpx
import asyncio
from typing import List

from services.ai_queue import submit, PRIORITY_HIGH, is_initialized

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
OLLAMA_EMBED_MODEL = os.environ.get("OLLAMA_EMBED_MODEL", "nomic-embed-text-v2-moe")


class EmbedderTimeoutError(Exception):
    pass


async def _embed_single_direct(text: str) -> List[float]:
    async with httpx.AsyncClient(timeout=20.0) as client:
        try:
            response = await client.post(
                f"{OLLAMA_URL}/api/embed",
                json={
                    "model": OLLAMA_EMBED_MODEL,
                    "input": text,
                    "truncate": True,
                },
            )
            response.raise_for_status()
            data = response.json()
            embeddings = data.get("embeddings", [])
            if not embeddings:
                raise EmbedderTimeoutError("Embedding service returned empty result")
            return embeddings[0]
        except httpx.TimeoutException:
            raise EmbedderTimeoutError("Embedding service timed out")


async def embed_single(text: str, priority: int = PRIORITY_HIGH) -> List[float]:
    if is_initialized():
        return await submit(
            _embed_single_direct,
            text,
            priority=priority,
        )
    return await _embed_single_direct(text)


async def embed_many(
    texts: List[str], priority: int = PRIORITY_HIGH
) -> List[List[float]]:
    results = []
    for text in texts:
        results.append(await embed_single(text, priority=priority))
    return results
