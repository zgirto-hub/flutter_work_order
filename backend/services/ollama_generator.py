import os
import httpx

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
OLLAMA_GEN_MODEL = os.environ.get("OLLAMA_GEN_MODEL", "gemma3:e2b")


class GeneratorTimeoutError(Exception):
    pass


async def generate(prompt: str, timeout: float = 90.0) -> str:
    async with httpx.AsyncClient(timeout=timeout) as client:
        try:
            response = await client.post(
                f"{OLLAMA_URL}/api/generate",
                json={"model": OLLAMA_GEN_MODEL, "prompt": prompt, "stream": False},
            )
            response.raise_for_status()
            data = response.json()
            return data.get("response", "")
        except httpx.TimeoutException:
            raise GeneratorTimeoutError("Generator timed out")
