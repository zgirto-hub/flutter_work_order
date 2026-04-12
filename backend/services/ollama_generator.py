import os
import httpx

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
OLLAMA_GEN_MODEL = os.environ.get("OLLAMA_GEN_MODEL", "gemma3:e2b")
OLLAMA_KEEP_ALIVE = os.environ.get("OLLAMA_KEEP_ALIVE", "30m")


class GeneratorTimeoutError(Exception):
    pass


async def generate(prompt: str, model: str | None = None, timeout: float = 180.0) -> str:
    use_model = model or OLLAMA_GEN_MODEL
    async with httpx.AsyncClient(timeout=timeout) as client:
        try:
            response = await client.post(
                f"{OLLAMA_URL}/api/generate",
                json={"model": use_model, "prompt": prompt, "stream": False, "keep_alive": OLLAMA_KEEP_ALIVE},
            )
            response.raise_for_status()
            data = response.json()
            return data.get("response", "")
        except httpx.TimeoutException:
            raise GeneratorTimeoutError("Generator timed out")


async def list_models() -> list[dict]:
    """Fetch available models from Ollama, excluding embedding models."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            response = await client.get(f"{OLLAMA_URL}/api/tags")
            response.raise_for_status()
            data = response.json()
            models = []
            for m in data.get("models", []):
                name = m.get("name", "")
                # Skip embedding-only models
                if "embed" in name.lower():
                    continue
                models.append({
                    "name": name,
                    "size_gb": round(m.get("size", 0) / (1024**3), 1),
                })
            return models
        except Exception:
            return []
