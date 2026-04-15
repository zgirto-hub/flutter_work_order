import httpx
import os
from typing import List
from .base import AIProvider


OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")


class OllamaProvider(AIProvider):
    @property
    def display_name(self) -> str:
        return "Local (Ollama)"

    async def generate(self, prompt: str, context_chunks: List[str]) -> str:
        from services.ollama_generator import generate as ollama_generate

        return await ollama_generate(prompt)

    async def health_check(self) -> bool:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(f"{OLLAMA_URL}/api/tags")
                return response.status_code == 200
        except Exception:
            return False
