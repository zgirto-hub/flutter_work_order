import os
import json
import httpx
from pathlib import Path

from services.ai_queue import submit, PRIORITY_HIGH, is_initialized

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
OLLAMA_GEN_MODEL = os.environ.get("OLLAMA_GEN_MODEL", "gemma4:e2b")
OLLAMA_KEEP_ALIVE = os.environ.get("OLLAMA_KEEP_ALIVE", "30m")

_CONFIG_PATH = Path("ai_model_config.json")


def get_default_model() -> str:
    """Read the saved default model, falling back to env var."""
    if _CONFIG_PATH.exists():
        try:
            data = json.loads(_CONFIG_PATH.read_text())
            return data.get("default_model", OLLAMA_GEN_MODEL)
        except Exception:
            pass
    return OLLAMA_GEN_MODEL


def set_default_model(model_name: str) -> None:
    """Save the default model to a config file."""
    _CONFIG_PATH.write_text(json.dumps({"default_model": model_name}))


class GeneratorTimeoutError(Exception):
    pass


class GeneratorModelError(Exception):
    """Ollama couldn't load the model (RAM, not found, etc.)."""

    def __init__(self, model: str, detail: str = ""):
        self.model = model
        self.detail = detail
        super().__init__(f"Model '{model}' failed: {detail}")


async def _generate_direct(
    prompt: str, model: str | None = None, timeout: float = 180.0
) -> str:
    use_model = model or get_default_model()
    async with httpx.AsyncClient(timeout=timeout) as client:
        try:
            response = await client.post(
                f"{OLLAMA_URL}/api/generate",
                json={
                    "model": use_model,
                    "prompt": prompt,
                    "stream": False,
                    "keep_alive": OLLAMA_KEEP_ALIVE,
                },
            )
            if response.status_code == 500:
                try:
                    err = response.json().get("error", "unknown error")
                except Exception:
                    err = response.text[:200]
                raise GeneratorModelError(use_model, err)
            if response.status_code == 404:
                raise GeneratorModelError(use_model, "model not found")
            response.raise_for_status()
            data = response.json()
            return data.get("response", "")
        except httpx.TimeoutException:
            raise GeneratorTimeoutError("Generator timed out")
        except GeneratorModelError:
            raise


async def generate(
    prompt: str,
    model: str | None = None,
    timeout: float = 180.0,
    priority: int = PRIORITY_HIGH,
) -> str:
    if is_initialized():
        return await submit(
            _generate_direct,
            prompt,
            model=model,
            timeout=timeout,
            priority=priority,
        )
    return await _generate_direct(prompt, model=model, timeout=timeout)


async def generate_stream(
    prompt: str, model: str | None = None, timeout: float = 180.0
):
    """Yield token chunks from Ollama streaming API."""
    use_model = model or get_default_model()
    async with httpx.AsyncClient(timeout=timeout) as client:
        try:
            async with client.stream(
                "POST",
                f"{OLLAMA_URL}/api/generate",
                json={
                    "model": use_model,
                    "prompt": prompt,
                    "stream": True,
                    "keep_alive": OLLAMA_KEEP_ALIVE,
                },
            ) as response:
                if response.status_code == 500:
                    try:
                        err = response.json().get("error", "unknown error")
                    except Exception:
                        err = response.text[:200]
                    raise GeneratorModelError(use_model, err)
                if response.status_code == 404:
                    raise GeneratorModelError(use_model, "model not found")
                response.raise_for_status()
                async for line in response.aiter_lines():
                    if not line.strip():
                        continue
                    data = json.loads(line)
                    token = data.get("response", "")
                    if token:
                        yield token
                    if data.get("done"):
                        break
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
                models.append(
                    {
                        "name": name,
                        "size_gb": round(m.get("size", 0) / (1024**3), 1),
                    }
                )
            return models
        except Exception:
            return []
