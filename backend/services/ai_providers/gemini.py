import os
import logging
from typing import List
from .base import AIProvider
from services.ollama_generator import GeneratorModelError

logger = logging.getLogger(__name__)
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")


class GeminiProvider(AIProvider):
    def __init__(self):
        self._api_key = GEMINI_API_KEY or os.environ.get("GEMINI_API_KEY")

    @property
    def display_name(self) -> str:
        return "Gemini 2.5 Flash"

    async def generate(self, prompt: str, context_chunks: List[str]) -> str:
        if not self._api_key:
            raise GeneratorModelError("gemini", "missing_credentials")

        try:
            from google.generativeai import GenerativeModel
        except ImportError:
            raise GeneratorModelError("gemini", "google-generativeai not installed")

        try:
            model = GenerativeModel("gemini-2.5-flash")
            full_prompt = (
                "You are a technical synthesis expert for civil aviation maintenance.\n"
                "You have received relevant information from technical manuals below.\n\n"
                + "\n\n".join(
                    f"[Context {i + 1}]\n{chunk}"
                    for i, chunk in enumerate(context_chunks)
                )
                + f"\n\nQUESTION: {prompt}\n\n"
                + "Please provide a clear, accurate answer based on the context provided."
            )
            response = await model.generate_content_async(full_prompt)
            answer = response.text.strip()
            if not answer or not answer.strip():
                raise GeneratorModelError("gemini", "empty_response")
            return answer
        except Exception as e:
            error_msg = str(e)
            if "quota" in error_msg.lower():
                raise GeneratorModelError("gemini", "quota_exceeded")
            if "API" in error_msg:
                error_msg = error_msg.replace(self._api_key, "[API_KEY_SCRUBBED]")
            logger.error(f"Gemini generation failed: {error_msg}")
            raise GeneratorModelError("gemini", error_msg[:100])

    async def health_check(self) -> bool:
        if not self._api_key:
            return False

        try:
            import asyncio
            from google.generativeai import GenerativeModel

            async def _check():
                model = GenerativeModel("gemini-2.5-flash")
                response = await model.generate_content_async("ping")
                return response.text

            response = await asyncio.wait_for(_check(), timeout=10.0)
            return bool(response)
        except Exception:
            return False
