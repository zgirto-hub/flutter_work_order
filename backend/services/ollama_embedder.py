import os
import httpx
import asyncio
from typing import List

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
OLLAMA_EMBED_MODEL = os.environ.get("OLLAMA_EMBED_MODEL", "nomic-embed-text")


class EmbedderTimeoutError(Exception):
    pass


async def embed_single(text: str) -> List[float]:
    async with httpx.AsyncClient(timeout=20.0) as client:
        try:
            response = await client.post(
                f"{OLLAMA_URL}/api/embeddings",
                json={"model": OLLAMA_EMBED_MODEL, "prompt": text},
            )
            response.raise_for_status()
            data = response.json()
            return data.get("embedding", [])
        except httpx.TimeoutException:
            raise EmbedderTimeoutError("Embedding service timed out")


async def embed_many(texts: List[str], concurrency: int = 4) -> List[List[float]]:
    semaphore = asyncio.Semaphore(concurrency)

    async def embed_with_semaphore(text: str) -> List[float]:
        async with semaphore:
            return await embed_single(text)

    tasks = [embed_with_semaphore(text) for text in texts]
    results = await asyncio.gather(*tasks)
    return results
